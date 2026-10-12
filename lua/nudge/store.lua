-- Comments live as extmarks: their position follows edits made before sending, and rows are read back only
-- when the comments are listed or sent.
-- One extmark in M.ns holds the range and the end-of-line text. Signs and line highlights are per row (an
-- extmark's sign only shows on its first row), so they live in M.deco_ns and are redrawn from the range
-- whenever the buffer changes.
local config = require("nudge.config")

local M = {}

M.ns = vim.api.nvim_create_namespace("nudge")
M.deco_ns = vim.api.nvim_create_namespace("nudge_deco")
M.pending_ns = vim.api.nvim_create_namespace("nudge_pending")

---@class nudge.Item
---@field buf integer
---@field id integer Extmark id in M.ns
---@field text string
---@field deco integer[] Extmark ids in M.deco_ns

---@type nudge.Item[] in insertion order
local items = {}

---@class nudge.Resolved
---@field item nudge.Item
---@field start_row integer 0-based
---@field end_row integer 0-based, inclusive

local function first_line(text)
  return (text:gsub("\n.*", " …"))
end

local function marks_opts(text)
  local cfg = config.options
  local o = {
    right_gravity = false,
    end_right_gravity = true,
    -- The extmark is flagged invalid when its whole range is deleted; undo brings it back.
    invalidate = true,
    undo_restore = true,
  }
  if cfg.max_virt_text > 0 then
    local shown = first_line(text)
    if vim.fn.strchars(shown) > cfg.max_virt_text then
      shown = vim.fn.strcharpart(shown, 0, cfg.max_virt_text) .. "…"
    end
    o.virt_text = { { cfg.virt_text_prefix .. shown, "NudgeVirtText" } }
    o.virt_text_pos = "eol"
  end
  return o
end

---Sign and line highlight on every row of [start_row, end_row].
---@return integer[] ids
local function paint(buf, ns, start_row, end_row, line_hl)
  local cfg = config.options
  local ids = {}
  for row = start_row, end_row do
    local o = { line_hl_group = line_hl }
    if cfg.sign then
      o.sign_text = cfg.sign
      o.sign_hl_group = "NudgeSign"
    end
    ids[#ids + 1] = vim.api.nvim_buf_set_extmark(buf, ns, row, 0, o)
  end
  return ids
end

---@param item nudge.Item
---@return nudge.Resolved|nil nil when the buffer is gone or the commented lines were deleted
function M.resolve(item)
  if not vim.api.nvim_buf_is_valid(item.buf) then
    return nil
  end
  local pos = vim.api.nvim_buf_get_extmark_by_id(item.buf, M.ns, item.id, { details = true })
  if #pos == 0 or pos[3].invalid then
    return nil
  end
  return { item = item, start_row = pos[1], end_row = pos[3].end_row or pos[1] }
end

---Redraw the per-row decorations of an item from its current range.
---@param item nudge.Item
local function decorate(item)
  if not vim.api.nvim_buf_is_valid(item.buf) then
    return
  end
  for _, id in ipairs(item.deco) do
    vim.api.nvim_buf_del_extmark(item.buf, M.deco_ns, id)
  end
  local r = M.resolve(item)
  item.deco = r and paint(item.buf, M.deco_ns, r.start_row, r.end_row, "NudgeRange") or {}
end

---Highlight a range while its comment is being typed. Returns a function that removes the highlight.
---@param buf integer
---@param start_row integer 0-based
---@param end_row integer 0-based, inclusive
---@return fun()
function M.preview(buf, start_row, end_row)
  paint(buf, M.pending_ns, start_row, end_row, "NudgePending")
  vim.cmd("redraw")
  return function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, M.pending_ns, 0, -1)
    end
  end
end

---@param buf integer
---@param start_row integer 0-based
---@param end_row integer 0-based, inclusive
---@param text string
---@return nudge.Item
function M.add(buf, start_row, end_row, text)
  local last = vim.api.nvim_buf_get_lines(buf, end_row, end_row + 1, true)[1]
  local o = marks_opts(text)
  o.end_row = end_row
  o.end_col = #last
  local id = vim.api.nvim_buf_set_extmark(buf, M.ns, start_row, 0, o)
  local item = { buf = buf, id = id, text = text, deco = {} }
  items[#items + 1] = item
  decorate(item)
  return item
end

---@param item nudge.Item
---@param text string
function M.update(item, text)
  local r = M.resolve(item)
  item.text = text
  if r then
    local pos = vim.api.nvim_buf_get_extmark_by_id(item.buf, M.ns, item.id, { details = true })
    local o = marks_opts(text)
    o.id = item.id
    o.end_row = pos[3].end_row
    o.end_col = pos[3].end_col
    vim.api.nvim_buf_set_extmark(item.buf, M.ns, pos[1], pos[2], o)
  end
  decorate(item)
end

---Redraw the decorations of a buffer's comments (after its text changed).
---@param buf integer
function M.refresh(buf)
  for _, it in ipairs(items) do
    if it.buf == buf then
      decorate(it)
    end
  end
end

---@param item nudge.Item
function M.remove(item)
  for i, it in ipairs(items) do
    if it == item then
      table.remove(items, i)
      break
    end
  end
  if vim.api.nvim_buf_is_valid(item.buf) then
    pcall(vim.api.nvim_buf_del_extmark, item.buf, M.ns, item.id)
    for _, id in ipairs(item.deco) do
      pcall(vim.api.nvim_buf_del_extmark, item.buf, M.deco_ns, id)
    end
  end
end

---@param buf? integer only this buffer
function M.clear(buf)
  for _, it in ipairs(vim.list_slice(items)) do
    if buf == nil or it.buf == buf then
      M.remove(it)
    end
  end
end

---Drop the items of a buffer that is being wiped (its extmarks go with it).
---@param buf integer
function M.forget(buf)
  for i = #items, 1, -1 do
    if items[i].buf == buf then
      table.remove(items, i)
    end
  end
end

---@return nudge.Item[]
function M.all()
  return vim.list_slice(items)
end

---The comment covering `row` in `buf`; the most recently added one wins when several overlap.
---@param buf integer
---@param row integer 0-based
---@return nudge.Item|nil
function M.at(buf, row)
  for i = #items, 1, -1 do
    local it = items[i]
    if it.buf == buf then
      local r = M.resolve(it)
      if r and r.start_row <= row and row <= r.end_row then
        return it
      end
    end
  end
  return nil
end

---Re-render every extmark (after the config changed).
function M.redraw()
  for _, it in ipairs(items) do
    M.update(it, it.text)
  end
end

return M
