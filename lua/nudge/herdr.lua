-- Finds the agent pane next to Neovim and sends text into it.
--
-- Two backends, chosen by the environment Neovim was started in:
--   * the Herdr desktop app ($HC_TERMINAL_ID): `herdr-app ls` lists the tab, `hc send` delivers the text
--   * the herdr TUI ($HERDR_PANE_ID): the `herdr pane` CLI
local M = {}

---Runs a command and returns { code, stdout, stderr }. Replaced in tests.
---@param args string[]
---@return { code: integer, stdout: string, stderr: string }
function M.run(args)
  local ok, res = pcall(function()
    return vim.system(args, { text = true }):wait()
  end)
  if not ok then
    return { code = 127, stdout = "", stderr = tostring(res) }
  end
  return { code = res.code, stdout = res.stdout or "", stderr = res.stderr or "" }
end

---Runs a command without blocking Neovim and calls `cb` with the same table as `run`. Replaced in tests.
---`hc send` waits while a person is typing in the target terminal (up to a minute), so it must not block.
---@param args string[]
---@param cb fun(res: { code: integer, stdout: string, stderr: string })
function M.start(args, cb)
  local ok, err = pcall(vim.system, args, { text = true }, function(res)
    vim.schedule(function()
      cb({ code = res.code, stdout = res.stdout or "", stderr = res.stderr or "" })
    end)
  end)
  if not ok then
    cb({ code = 127, stdout = "", stderr = tostring(err) })
  end
end

-- Bracketed paste (herdr TUI only): the agent's prompt takes the whole message as one paste instead of
-- submitting it at the first newline. `hc send` pastes by itself.
M.PASTE_START = "\27[200~"
M.PASTE_END = "\27[201~"

-- `hc send` exits with this code when the program is waiting on a dialog (a permission prompt, a question).
local HC_BLOCKED = 9

---@type table<string, string> tab id -> pane id chosen last time
local chosen = {}

---@class nudge.Pane
---@field pane_id string what the text is sent to: a herdr pane id, or a terminal address (`t7`) in the app
---@field tab_id string
---@field cwd string|nil
---@field agent string|nil
---@field title string|nil

---@param v string|nil
---@return string|nil
local function env(v)
  local s = vim.env[v]
  return (s and s ~= "") and s or nil
end

---@return "hc"|"herdr"|nil
function M.backend()
  if env("HC_TERMINAL_ID") then
    return "hc"
  end
  if env("HERDR_PANE_ID") then
    return "herdr"
  end
  return nil
end

---@param s string
---@return table|nil
local function decode(s)
  local ok, decoded = pcall(vim.json.decode, s, { luanil = { object = true, array = true } })
  return (ok and type(decoded) == "table") and decoded or nil
end

---What a failed command said. hc and herdr report errors as JSON: `{"error":{"message":"..."}}`.
---@param res { code: integer, stdout: string, stderr: string }
---@return string
local function output(res)
  local text = vim.trim(res.stderr ~= "" and res.stderr or res.stdout)
  local decoded = decode(text)
  local err = decoded and decoded.error
  if type(err) == "table" and type(err.message) == "string" then
    return err.message
  end
  return text
end

---The app reports Claude Code as `claude-code`; the TUI as `claude`. `agent = "claude"` matches both.
---@param name string|nil agent name as the backend reports it
---@param agent string|false false = any agent
---@return boolean
local function matches(name, agent)
  if not name then
    return false
  end
  return not agent or name == agent or vim.startswith(name, agent .. "-")
end

---herdr TUI: every pane, and this pane's id.
---@return nudge.Pane[]|nil panes
---@return string|nil self_or_err
local function list_herdr()
  local res = M.run({ "herdr", "pane", "list" })
  if res.code ~= 0 then
    return nil, "herdr pane list failed: " .. output(res)
  end
  local decoded = decode(res.stdout)
  if not decoded or type(decoded.result) ~= "table" then
    return nil, "unexpected output from herdr pane list"
  end
  local panes = {}
  for _, p in ipairs(decoded.result.panes or {}) do
    panes[#panes + 1] = {
      pane_id = p.pane_id,
      tab_id = p.tab_id,
      cwd = p.cwd,
      agent = p.agent,
      title = p.terminal_title_stripped,
    }
  end
  return panes, env("HERDR_PANE_ID")
end

---Herdr app: every terminal shown in a tab, and this terminal's address. cwd and title are filled in later,
---for the candidates only (`describe`), because they need one `hc get` per terminal.
---@return nudge.Pane[]|nil panes
---@return string|nil self_or_err
local function list_hc()
  local res = M.run({ "herdr-app", "ls" })
  if res.code ~= 0 then
    return nil, "herdr-app ls failed: " .. output(res)
  end
  local decoded = decode(res.stdout)
  if not decoded or type(decoded.spaces) ~= "table" then
    return nil, "unexpected output from herdr-app ls"
  end
  local panes = {}
  for _, space in ipairs(decoded.spaces) do
    for _, tab in ipairs(space.tabs or {}) do
      for _, t in ipairs(tab.terminals or {}) do
        panes[#panes + 1] = { pane_id = t.terminal, tab_id = tab.id, agent = t.app }
      end
    end
  end
  return panes, env("HC_TERMINAL_ID")
end

---Herdr app: the agent's working directory and the terminal title. Left empty when `hc get` fails: paths
---are then sent as absolute paths.
---@param pane nudge.Pane
local function describe(pane)
  local res = M.run({ "hc", "get", pane.pane_id, "--json" })
  local got = res.code == 0 and decode(res.stdout) or nil
  if not got then
    return
  end
  -- The terminal's own cwd is where its shell started; the agent runs where the foreground program does.
  pane.cwd = type(got.foreground) == "table" and got.foreground.cwd or got.cwd
  pane.title = got.title
end

---Agent panes in the same herdr tab as Neovim.
---@param agent string|false false = any agent
---@return nudge.Pane[]|nil candidates
---@return string|nil tab
---@return string|nil err
function M.candidates(agent)
  local backend = M.backend()
  if not backend then
    return nil, nil, "not running inside herdr (neither $HC_TERMINAL_ID nor $HERDR_PANE_ID is set)"
  end
  local panes, self
  if backend == "hc" then
    panes, self = list_hc()
  else
    panes, self = list_herdr()
  end
  if not panes then
    return nil, nil, self
  end
  local tab
  for _, p in ipairs(panes) do
    if p.pane_id == self then
      tab = p.tab_id
    end
  end
  if not tab then
    return nil, nil, ("this pane (%s) is not in a herdr tab"):format(self)
  end
  local out = {}
  for _, p in ipairs(panes) do
    if p.tab_id == tab and p.pane_id ~= self and matches(p.agent, agent) then
      if backend == "hc" then
        describe(p)
      end
      out[#out + 1] = p
    end
  end
  return out, tab
end

---Picks the target pane: the only candidate, the one chosen last time in this tab, or asks.
---@param opts { agent: string|false, ask: boolean|nil }
---@param cb fun(pane: nudge.Pane|nil, err: string|nil)
function M.target(opts, cb)
  local cands, tab, err = M.candidates(opts.agent)
  if not cands then
    return cb(nil, err)
  end
  if #cands == 0 then
    return cb(nil, ("no %s pane in this herdr tab"):format(opts.agent or "agent"))
  end
  if not opts.ask then
    if #cands == 1 then
      chosen[tab] = cands[1].pane_id
      return cb(cands[1])
    end
    for _, p in ipairs(cands) do
      if p.pane_id == chosen[tab] then
        return cb(p)
      end
    end
  end
  vim.ui.select(cands, {
    prompt = "Send to which pane?",
    format_item = function(p)
      return ("%s  %s"):format(p.title or p.agent, p.pane_id)
    end,
  }, function(p)
    if not p then
      return cb(nil, "cancelled")
    end
    chosen[tab] = p.pane_id
    cb(p)
  end)
end

---herdr TUI: bracketed paste, then Enter when `submit`.
---@param pane_id string
---@param text string
---@param submit boolean
---@param cb fun(ok: boolean, err: string|nil)
local function paste_herdr(pane_id, text, submit, cb)
  local res = M.run({ "herdr", "pane", "send-text", pane_id, M.PASTE_START .. text .. M.PASTE_END })
  if res.code ~= 0 then
    return cb(false, "herdr pane send-text failed: " .. output(res))
  end
  if submit then
    res = M.run({ "herdr", "pane", "send-keys", pane_id, "enter" })
    if res.code ~= 0 then
      return cb(false, "herdr pane send-keys failed: " .. output(res))
    end
  end
  cb(true)
end

---Herdr app: `hc send` pastes the text and presses Enter. It cannot paste without submitting.
---@param terminal string
---@param text string
---@param cb fun(ok: boolean, err: string|nil)
local function paste_hc(terminal, text, cb)
  -- Messages attributed to a terminal reach an agent as `<hc from="t7">` reports from a helper, not as the
  -- person's own words. Dropping $HC_TERMINAL_ID is meant to keep this one unattributed.
  M.start({ "env", "-u", "HC_TERMINAL_ID", "hc", "send", "--", terminal, text }, function(res)
    if res.code == 0 then
      return cb(true)
    end
    if res.code == HC_BLOCKED then
      return cb(false, "the agent is waiting on a permission prompt or a question: answer it, then send again")
    end
    cb(false, "hc send failed: " .. output(res))
  end)
end

---@param pane_id string
---@param text string
---@param submit boolean press Enter afterwards (herdr TUI only: the app always submits)
---@param cb fun(ok: boolean, err: string|nil) called once the text was delivered, or not
function M.paste(pane_id, text, submit, cb)
  -- A stray end marker inside the text would end the paste early and submit the rest line by line. Removing
  -- the marker string is not enough (ESC[20 ESC[201~ 1~ becomes a marker again), so drop ESC and every
  -- other control character except tab and newline.
  text = text:gsub("[%z\1-\8\11-\31\127]", "")
  if M.backend() == "hc" then
    return paste_hc(pane_id, text, cb)
  end
  paste_herdr(pane_id, text, submit, cb)
end

function M._reset()
  chosen = {}
end

return M
