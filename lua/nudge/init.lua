local config = require("nudge.config")
local herdr = require("nudge.herdr")
local payload = require("nudge.payload")
local store = require("nudge.store")

local M = {}

local uv = vim.uv or vim.loop

local function notify(msg, level)
  vim.notify("nudge: " .. msg, level or vim.log.levels.INFO)
end

---Mix `fg` into `bg` by `alpha` (0..1). Colors are 24-bit integers.
local function blend(fg, bg, alpha)
  local out = 0
  for shift = 16, 0, -8 do
    local f = bit.band(bit.rshift(fg, shift), 0xff)
    local b = bit.band(bit.rshift(bg, shift), 0xff)
    out = out + bit.lshift(math.floor(b + (f - b) * alpha + 0.5), shift)
  end
  return out
end

local function set_highlights()
  vim.api.nvim_set_hl(0, "NudgeSign", { link = "DiagnosticSignHint", default = true })
  vim.api.nvim_set_hl(0, "NudgeVirtText", { link = "DiagnosticVirtualTextHint", default = true })
  vim.api.nvim_set_hl(0, "NudgePending", { link = "Visual", default = true })
  -- A faint tint of the hint color, so commented lines stand apart from CursorLine and Visual.
  local hint = vim.api.nvim_get_hl(0, { name = "DiagnosticHint", link = false }).fg
  local bg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
    or (vim.o.background == "light" and 0xffffff or 0x000000)
  if hint then
    vim.api.nvim_set_hl(0, "NudgeRange", { bg = blend(hint, bg, 0.18), default = true })
  else
    vim.api.nvim_set_hl(0, "NudgeRange", { link = "CursorLine", default = true })
  end
end

local group = vim.api.nvim_create_augroup("nudge", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlights })
-- Rows inserted inside a range need their own sign and highlight.
vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
  group = group,
  callback = function(ev)
    store.refresh(ev.buf)
  end,
})
vim.api.nvim_create_autocmd("BufWipeout", {
  group = group,
  callback = function(ev)
    store.forget(ev.buf)
  end,
})
set_highlights()

---@param opts? nudge.Config
function M.setup(opts)
  config.setup(opts)
  set_highlights()
  store.redraw()
end

---Line range of the current visual selection (leaving visual mode), or the cursor line.
---@return integer line1, integer line2 1-based
local function current_range()
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    local a, b = vim.fn.line("v"), vim.fn.line(".")
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
    return math.min(a, b), math.max(a, b)
  end
  local l = vim.fn.line(".")
  return l, l
end

---Add a comment to a line range of the current buffer.
---@param opts? { line1: integer, line2: integer, text: string }
function M.add(opts)
  opts = opts or {}
  local buf = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(buf) == "" or vim.bo[buf].buftype ~= "" then
    return notify("comments need a file buffer", vim.log.levels.WARN)
  end
  local line1, line2 = opts.line1, opts.line2
  if not line1 then
    line1, line2 = current_range()
  end
  local function done(text)
    if not text or vim.trim(text) == "" then
      return
    end
    store.add(buf, line1 - 1, line2 - 1, text)
  end
  if opts.text then
    return done(opts.text)
  end
  -- Leaving visual mode drops the selection: keep the range visible while the comment is typed.
  -- Input windows usually open just above the cursor, so put it on the first line to keep them off the range.
  if vim.api.nvim_win_get_buf(0) == buf then
    vim.api.nvim_win_set_cursor(0, { line1, 0 })
  end
  local unpreview = store.preview(buf, line1 - 1, line2 - 1)
  local where = line1 == line2 and ("line %d"):format(line1) or ("lines %d-%d"):format(line1, line2)
  vim.ui.input({ prompt = ("Comment on %s: "):format(where) }, function(text)
    unpreview()
    done(text)
  end)
end

---Edit the comment under the cursor.
function M.edit()
  local item = store.at(vim.api.nvim_get_current_buf(), vim.fn.line(".") - 1)
  if not item then
    return notify("no comment under the cursor", vim.log.levels.WARN)
  end
  vim.ui.input({ prompt = "Comment: ", default = item.text }, function(text)
    if text == nil then
      return
    end
    if vim.trim(text) == "" then
      return store.remove(item)
    end
    store.update(item, text)
  end)
end

---Delete the comment under the cursor.
function M.delete()
  local item = store.at(vim.api.nvim_get_current_buf(), vim.fn.line(".") - 1)
  if not item then
    return notify("no comment under the cursor", vim.log.levels.WARN)
  end
  store.remove(item)
end

---Delete every comment (or only those of the current buffer).
---@param opts? { buffer: boolean }
function M.clear(opts)
  store.clear((opts and opts.buffer) and vim.api.nvim_get_current_buf() or nil)
end

---@return integer
function M.count()
  local n = 0
  for _, it in ipairs(store.all()) do
    if store.resolve(it) then
      n = n + 1
    end
  end
  return n
end

---Show the comments in the quickfix list.
function M.list()
  local qf = {}
  for _, it in ipairs(store.all()) do
    local r = store.resolve(it)
    if r then
      qf[#qf + 1] = { bufnr = it.buf, lnum = r.start_row + 1, end_lnum = r.end_row + 1, text = it.text }
    end
  end
  if #qf == 0 then
    return notify("no comments")
  end
  table.sort(qf, function(a, b)
    if a.bufnr ~= b.bufnr then
      return vim.api.nvim_buf_get_name(a.bufnr) < vim.api.nvim_buf_get_name(b.bufnr)
    end
    return a.lnum < b.lnum
  end)
  vim.fn.setqflist({}, " ", { title = "nudge", items = qf })
  vim.cmd("botright copen")
end

---@param path string
---@return string
local function real(path)
  return uv.fs_realpath(path) or vim.fs.normalize(path)
end

---Build the entries to send, relative to the target pane's cwd.
---@param cwd string|nil
---@return nudge.Entry[] entries, nudge.Item[] sent, nudge.Item[] stale, string[] modified
function M._entries(cwd)
  local entries, sent, stale, modified, seen = {}, {}, {}, {}, {}
  cwd = cwd and real(cwd) or nil
  for _, it in ipairs(store.all()) do
    local r = store.resolve(it)
    if not r then
      stale[#stale + 1] = it
    else
      local path = payload.relative(real(vim.api.nvim_buf_get_name(it.buf)), cwd)
      entries[#entries + 1] = {
        path = path,
        start_line = r.start_row + 1,
        end_line = r.end_row + 1,
        lines = vim.api.nvim_buf_get_lines(it.buf, r.start_row, r.end_row + 1, false),
        lang = vim.bo[it.buf].filetype,
        text = it.text,
      }
      sent[#sent + 1] = it
      if vim.bo[it.buf].modified and not seen[path] then
        seen[path] = true
        modified[#modified + 1] = path
      end
    end
  end
  payload.sort(entries)
  return entries, sent, stale, modified
end

---Paste every comment into the agent pane of this herdr tab.
---@param opts? { ask: boolean } ask which pane even when one was chosen before
function M.send(opts)
  opts = opts or {}
  local cfg = config.options
  if M.count() == 0 then
    return notify("no comments to send")
  end
  herdr.target({ agent = cfg.agent, ask = opts.ask }, function(pane, err)
    if not pane then
      return notify(err or "no target pane", vim.log.levels.WARN)
    end
    local entries, sent, stale, modified = M._entries(pane.cwd)
    local ok, perr = herdr.paste(pane.pane_id, payload.build(entries, cfg.header), cfg.submit)
    if not ok then
      return notify(perr or "send failed", vim.log.levels.ERROR)
    end
    if cfg.clear_on_send then
      for _, it in ipairs(vim.list_extend(sent, stale)) do
        store.remove(it)
      end
    end
    notify(("sent %d comment(s) to %s"):format(#entries, pane.title or pane.pane_id))
    if #modified > 0 then
      notify(
        "unsaved changes in "
          .. table.concat(modified, ", ")
          .. ": the agent reads the file on disk, so line numbers may not match",
        vim.log.levels.WARN
      )
    end
  end)
end

---Choose the target pane again (it is remembered per herdr tab).
function M.target()
  herdr.target({ agent = config.options.agent, ask = true }, function(pane, err)
    if not pane then
      return notify(err or "no target pane", vim.log.levels.WARN)
    end
    notify("target: " .. (pane.title or pane.pane_id))
  end)
end

local subcommands = {
  add = function(cmd, rest)
    local text = #rest > 0 and table.concat(rest, " ") or nil
    if cmd.range > 0 then
      M.add({ line1 = cmd.line1, line2 = cmd.line2, text = text })
    else
      local l = vim.fn.line(".")
      M.add({ line1 = l, line2 = l, text = text })
    end
  end,
  edit = M.edit,
  delete = M.delete,
  clear = function()
    M.clear()
  end,
  list = M.list,
  send = function()
    M.send()
  end,
  target = M.target,
}

---@return string[]
function M._subcommands()
  local names = vim.tbl_keys(subcommands)
  table.sort(names)
  return names
end

---@param cmd table nvim_create_user_command callback argument
function M._command(cmd)
  local name = cmd.fargs[1] or "add"
  local fn = subcommands[name]
  if not fn then
    return notify("unknown subcommand: " .. name, vim.log.levels.WARN)
  end
  fn(cmd, vim.list_slice(cmd.fargs, 2))
end

return M
