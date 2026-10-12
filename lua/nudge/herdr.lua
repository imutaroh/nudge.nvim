-- Finds the agent pane next to Neovim and pastes text into it, through the herdr CLI.
local M = {}

---Runs a command and returns { code, stdout, stderr }. Replaced in tests.
---@param args string[]
---@return { code: integer, stdout: string, stderr: string }
function M.run(args)
  local res = vim.system(args, { text = true }):wait()
  return { code = res.code, stdout = res.stdout or "", stderr = res.stderr or "" }
end

-- Bracketed paste: the agent's prompt takes the whole message as one paste instead of submitting it at the
-- first newline.
M.PASTE_START = "\27[200~"
M.PASTE_END = "\27[201~"

---@type table<string, string> tab id -> pane id chosen last time
local chosen = {}

---@class nudge.Pane
---@field pane_id string
---@field tab_id string
---@field cwd string|nil
---@field agent string|nil
---@field title string|nil

---@return nudge.Pane[]|nil panes
---@return string|nil err
local function list()
  local res = M.run({ "herdr", "pane", "list" })
  if res.code ~= 0 then
    return nil, "herdr pane list failed: " .. vim.trim(res.stderr ~= "" and res.stderr or res.stdout)
  end
  local ok, decoded = pcall(vim.json.decode, res.stdout, { luanil = { object = true, array = true } })
  if not ok or type(decoded) ~= "table" or type(decoded.result) ~= "table" then
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
  return panes
end

---Agent panes in the same herdr tab as Neovim.
---@param agent string|false false = any agent
---@return nudge.Pane[]|nil candidates
---@return string|nil tab
---@return string|nil err
function M.candidates(agent)
  local self = vim.env.HERDR_PANE_ID
  if not self or self == "" then
    return nil, nil, "not running inside herdr ($HERDR_PANE_ID is not set)"
  end
  local panes, err = list()
  if not panes then
    return nil, nil, err
  end
  local tab
  for _, p in ipairs(panes) do
    if p.pane_id == self then
      tab = p.tab_id
    end
  end
  if not tab then
    return nil, nil, "this pane (" .. self .. ") is not in herdr pane list"
  end
  local out = {}
  for _, p in ipairs(panes) do
    if p.tab_id == tab and p.pane_id ~= self and p.agent and (not agent or p.agent == agent) then
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

---@param pane_id string
---@param text string
---@param submit boolean press Enter afterwards
---@return boolean ok
---@return string|nil err
function M.paste(pane_id, text, submit)
  -- A stray end marker inside the text would end the paste early and submit the rest line by line.
  text = text:gsub("\27%[201~", "")
  local res = M.run({ "herdr", "pane", "send-text", pane_id, M.PASTE_START .. text .. M.PASTE_END })
  if res.code ~= 0 then
    return false, "herdr pane send-text failed: " .. vim.trim(res.stderr ~= "" and res.stderr or res.stdout)
  end
  if submit then
    res = M.run({ "herdr", "pane", "send-keys", pane_id, "enter" })
    if res.code ~= 0 then
      return false, "herdr pane send-keys failed: " .. vim.trim(res.stderr ~= "" and res.stderr or res.stdout)
    end
  end
  return true
end

function M._reset()
  chosen = {}
end

return M
