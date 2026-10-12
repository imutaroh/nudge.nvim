local h = require("helpers")
local nudge = require("nudge")
local store = require("nudge.store")

local T = {}

T["a comment follows lines inserted above it"] = function()
  local buf = h.file("a.lua", { "one", "two", "three", "four" })
  nudge.add({ line1 = 2, line2 = 3, text = "look here" })
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "new1", "new2" })
  local r = store.resolve(store.all()[1])
  h.eq({ 3, 4 }, { r.start_row, r.end_row })
end

T["a comment whose lines were deleted is skipped, and undo brings it back"] = function()
  local buf = h.file("a.lua", { "one", "two", "three" })
  nudge.add({ line1 = 2, line2 = 2, text = "x" })
  vim.cmd("2delete")
  h.eq(nil, store.resolve(store.all()[1]))
  h.eq(0, nudge.count())
  vim.cmd("undo")
  h.eq(1, nudge.count())
  h.eq(1, store.resolve(store.all()[1]).start_row)
  h.eq(true, vim.api.nvim_buf_is_valid(buf))
end

T["add asks for the text and ignores an empty answer"] = function()
  h.file("a.lua", { "one" })
  h.answer_input("")
  nudge.add({ line1 = 1, line2 = 1 })
  h.eq(0, #store.all())
  h.answer_input("fix this")
  nudge.add({ line1 = 1, line2 = 1 })
  h.eq("fix this", store.all()[1].text)
end

T["add refuses buffers without a file"] = function()
  vim.cmd("enew")
  nudge.add({ line1 = 1, line2 = 1, text = "x" })
  h.eq(0, #store.all())
  h.eq(vim.log.levels.WARN, h.notifications()[1].level)
end

T["edit and delete act on the comment under the cursor"] = function()
  h.file("a.lua", { "one", "two", "three" })
  nudge.add({ line1 = 1, line2 = 2, text = "first" })
  nudge.add({ line1 = 3, line2 = 3, text = "second" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  h.answer_input("edited")
  nudge.edit()
  h.eq(
    { "edited", "second" },
    vim.tbl_map(function(i)
      return i.text
    end, store.all())
  )
  nudge.delete()
  h.eq(
    { "second" },
    vim.tbl_map(function(i)
      return i.text
    end, store.all())
  )
end

T["the end-of-line text is truncated and shows only the first line"] = function()
  local buf = h.file("a.lua", { "one" })
  nudge.setup({ max_virt_text = 5 })
  nudge.add({ line1 = 1, line2 = 1, text = "abcdefgh\nsecond" })
  local mark = vim.api.nvim_buf_get_extmarks(buf, store.ns, 0, -1, { details = true })[1]
  h.eq("  ✎ abcde…", mark[4].virt_text[1][1])
end

---Rows (0-based) carrying a decoration in `ns`, with their sign and line highlight.
local function painted(buf, ns)
  return vim.tbl_map(function(m)
    return { m[2], m[4].sign_text, m[4].line_hl_group }
  end, vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }))
end

T["sign = false shows no sign"] = function()
  local buf = h.file("a.lua", { "one" })
  nudge.setup({ sign = false })
  nudge.add({ line1 = 1, line2 = 1, text = "x" })
  h.eq({ { 0, nil, "NudgeRange" } }, painted(buf, store.deco_ns))
end

T["every row of a range gets a sign and a line highlight"] = function()
  local buf = h.file("a.lua", { "one", "two", "three", "four" })
  nudge.add({ line1 = 2, line2 = 4, text = "x" })
  -- sign_text is padded to the sign column width
  h.eq(
    { { 1, "▍ ", "NudgeRange" }, { 2, "▍ ", "NudgeRange" }, { 3, "▍ ", "NudgeRange" } },
    painted(buf, store.deco_ns)
  )
end

T["rows inserted inside a range are painted after the text changes"] = function()
  local buf = h.file("a.lua", { "one", "two", "three" })
  nudge.add({ line1 = 1, line2 = 2, text = "x" })
  vim.api.nvim_buf_set_lines(buf, 1, 1, false, { "inserted" })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  h.eq(
    { 0, 1, 2 },
    vim.tbl_map(function(p)
      return p[1]
    end, painted(buf, store.deco_ns))
  )
end

T["deleting the lines removes the decorations and undo restores them"] = function()
  local buf = h.file("a.lua", { "one", "two", "three" })
  nudge.add({ line1 = 2, line2 = 2, text = "x" })
  vim.cmd("2delete")
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  h.eq({}, painted(buf, store.deco_ns))
  vim.cmd("undo")
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  h.eq(1, #painted(buf, store.deco_ns))
end

T["the range stays highlighted while the comment is typed"] = function()
  local buf = h.file("a.lua", { "one", "two", "three" })
  local during
  vim.ui.input = function(_, cb)
    during = painted(buf, store.pending_ns)
    cb(nil)
  end
  nudge.add({ line1 = 1, line2 = 2 })
  h.eq({ { 0, "▍ ", "NudgePending" }, { 1, "▍ ", "NudgePending" } }, during)
  h.eq({}, painted(buf, store.pending_ns), "cleared after the input closes")
  h.eq(0, #store.all(), "cancelled")
end

T["delete removes the decorations too"] = function()
  local buf = h.file("a.lua", { "one", "two" })
  nudge.add({ line1 = 1, line2 = 2, text = "x" })
  nudge.delete()
  h.eq({}, painted(buf, store.deco_ns))
end

T["wiping a buffer forgets its comments"] = function()
  local buf = h.file("a.lua", { "one" })
  nudge.add({ line1 = 1, line2 = 1, text = "x" })
  vim.cmd("bwipeout! " .. buf)
  h.eq(0, #store.all())
end

T[":Nudge add takes a range and text"] = function()
  h.file("a.lua", { "one", "two", "three" })
  vim.cmd("2,3Nudge add please rename")
  local r = store.resolve(store.all()[1])
  h.eq({ 1, 2, "please rename" }, { r.start_row, r.end_row, r.item.text })
end

return T
