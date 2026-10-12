local h = require("helpers")
local herdr = require("nudge.herdr")
local nudge = require("nudge")
local store = require("nudge.store")

local T = {}

local function pane(id, tab, agent, cwd)
  return { pane_id = id, tab_id = tab, agent = agent, cwd = cwd, terminal_title_stripped = "title " .. id }
end

local function sent_text()
  local c = h.calls_of("send-text")
  return c[#c] and c[#c][5]
end

T["send pastes every comment into the only claude pane of this tab"] = function()
  local _, path = h.file("a.lua", { "local x = 1", "return x" })
  local dir = vim.fs.dirname(path)
  vim.env.HERDR_PANE_ID = "w:nvim"
  h.fake_herdr({
    pane("w:nvim", "t1"),
    pane("w:claude", "t1", "claude", dir),
    pane("w:other", "t2", "claude", dir),
    pane("w:codex", "t1", "codex", dir),
  })
  nudge.add({ line1 = 2, line2 = 2, text = "inline this" })
  nudge.send()

  local c = h.calls_of("send-text")
  h.eq(1, #c)
  h.eq("w:claude", c[1][4])
  local text = sent_text()
  h.truthy(vim.startswith(text, herdr.PASTE_START) and vim.endswith(text, herdr.PASTE_END), "bracketed paste")
  h.truthy(text:find("## 1. a.lua:2\n```lua\nreturn x\n```\ninline this", 1, true), text)
  h.eq(0, #h.calls_of("send-keys"), "no Enter by default")
  h.eq(0, #store.all(), "cleared after sending")
end

T["comments from several files are sorted by path"] = function()
  vim.env.HERDR_PANE_ID = "w:nvim"
  local _, pb = h.file("b.lua", { "b" })
  local dir = vim.fs.dirname(pb)
  h.fake_herdr({ pane("w:nvim", "t1"), pane("w:claude", "t1", "claude", dir) })
  nudge.add({ line1 = 1, line2 = 1, text = "B" })
  h.file("a.lua", { "a" }, dir)
  nudge.add({ line1 = 1, line2 = 1, text = "A" })
  nudge.send()
  local text = sent_text()
  local ia = text:find("## 1. a.lua:1", 1, true)
  local ib = text:find("## 2. b.lua:1", 1, true)
  h.truthy(ia and ib, text)
end

T["submit presses Enter after pasting"] = function()
  vim.env.HERDR_PANE_ID = "w:nvim"
  h.fake_herdr({ pane("w:nvim", "t1"), pane("w:claude", "t1", "claude", "/") })
  nudge.setup({ submit = true })
  h.file("a.lua", { "a" })
  nudge.add({ line1 = 1, line2 = 1, text = "x" })
  nudge.send()
  h.eq({ { "herdr", "pane", "send-keys", "w:claude", "enter" } }, h.calls_of("send-keys"))
end

T["a failed send keeps the comments"] = function()
  vim.env.HERDR_PANE_ID = "w:nvim"
  h.fake_herdr({ pane("w:nvim", "t1"), pane("w:claude", "t1", "claude", "/") }, { ["send-text"] = true })
  h.file("a.lua", { "a" })
  nudge.add({ line1 = 1, line2 = 1, text = "x" })
  nudge.send()
  h.eq(1, #store.all())
  h.eq(vim.log.levels.ERROR, h.notifications()[1].level)
end

T["outside herdr, send warns and sends nothing"] = function()
  h.fake_herdr({})
  h.file("a.lua", { "a" })
  nudge.add({ line1 = 1, line2 = 1, text = "x" })
  nudge.send()
  h.eq(0, #h.calls())
  h.truthy(h.notifications()[1].msg:find("HERDR_PANE_ID", 1, true))
  h.eq(1, #store.all())
end

T["no claude pane in the tab is reported"] = function()
  vim.env.HERDR_PANE_ID = "w:nvim"
  h.fake_herdr({ pane("w:nvim", "t1"), pane("w:claude", "t2", "claude", "/") })
  h.file("a.lua", { "a" })
  nudge.add({ line1 = 1, line2 = 1, text = "x" })
  nudge.send()
  h.eq(0, #h.calls_of("send-text"))
  h.truthy(h.notifications()[1].msg:find("no claude pane", 1, true))
end

T["with several claude panes it asks once, then remembers the choice"] = function()
  vim.env.HERDR_PANE_ID = "w:nvim"
  h.fake_herdr({ pane("w:nvim", "t1"), pane("w:c1", "t1", "claude", "/"), pane("w:c2", "t1", "claude", "/") })
  h.select_count = 0
  h.answer_select(function(p)
    return p.pane_id == "w:c2"
  end)
  h.file("a.lua", { "a" })
  nudge.add({ line1 = 1, line2 = 1, text = "x" })
  nudge.send()
  nudge.add({ line1 = 1, line2 = 1, text = "y" })
  nudge.send()
  h.eq(1, h.select_count)
  h.eq(
    { "w:c2", "w:c2" },
    vim.tbl_map(function(c)
      return c[4]
    end, h.calls_of("send-text"))
  )
end

T["agent = false sends to any agent"] = function()
  vim.env.HERDR_PANE_ID = "w:nvim"
  h.fake_herdr({ pane("w:nvim", "t1"), pane("w:codex", "t1", "codex", "/") })
  nudge.setup({ agent = false })
  h.file("a.lua", { "a" })
  nudge.add({ line1 = 1, line2 = 1, text = "x" })
  nudge.send()
  h.eq("w:codex", h.calls_of("send-text")[1][4])
end

T["a paste end marker inside a comment is removed"] = function()
  vim.env.HERDR_PANE_ID = "w:nvim"
  h.fake_herdr({ pane("w:nvim", "t1"), pane("w:claude", "t1", "claude", "/") })
  h.file("a.lua", { "a" })
  nudge.add({ line1 = 1, line2 = 1, text = "bad\27[201~rest" })
  nudge.send()
  local text = sent_text()
  local inner = text:sub(#herdr.PASTE_START + 1, -#herdr.PASTE_END - 1)
  h.eq(nil, inner:find("\27[201~", 1, true))
  h.truthy(inner:find("badrest", 1, true))
end

T["unsaved buffers are warned about"] = function()
  vim.env.HERDR_PANE_ID = "w:nvim"
  h.fake_herdr({ pane("w:nvim", "t1"), pane("w:claude", "t1", "claude", "/") })
  local buf = h.file("a.lua", { "a" })
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "new" })
  nudge.add({ line1 = 2, line2 = 2, text = "x" })
  nudge.send()
  local warned = vim.tbl_filter(function(n)
    return n.level == vim.log.levels.WARN and n.msg:find("unsaved", 1, true)
  end, h.notifications())
  h.eq(1, #warned)
end

return T
