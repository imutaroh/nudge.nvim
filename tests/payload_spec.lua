local h = require("helpers")
local payload = require("nudge.payload")

local T = {}

T["relative strips the cwd only for files inside it"] = function()
  h.eq("lua/a.lua", payload.relative("/repo/lua/a.lua", "/repo"))
  h.eq("lua/a.lua", payload.relative("/repo/lua/a.lua", "/repo/"))
  h.eq("/repository/a.lua", payload.relative("/repository/a.lua", "/repo"))
  h.eq("/repo/a.lua", payload.relative("/repo/a.lua", nil))
end

T["the fence is longer than any backtick run in the code"] = function()
  h.eq("```", payload.fence({ "plain" }))
  h.eq("````", payload.fence({ "x = ```" }))
end

T["build formats header, location, code and comment"] = function()
  local text = payload.build({
    { path = "a.go", start_line = 3, end_line = 4, lines = { "foo()", "bar()" }, lang = "go", text = "why?" },
    { path = "b.go", start_line = 7, end_line = 7, lines = { "baz()" }, lang = "go", text = "rename" },
  }, "Please review.")
  h.eq(
    table.concat({
      "Please review.",
      "",
      "## 1. a.go:3-4",
      "```go",
      "foo()",
      "bar()",
      "```",
      "why?",
      "",
      "## 2. b.go:7",
      "```go",
      "baz()",
      "```",
      "rename",
    }, "\n"),
    text
  )
end

T["build without a header starts with the first comment"] = function()
  local text = payload.build({ { path = "a", start_line = 1, end_line = 1, lines = {}, lang = "", text = "t" } }, "")
  h.eq("## 1. a:1", vim.split(text, "\n")[1])
end

T["sort orders by path then line"] = function()
  local e = {
    { path = "b", start_line = 1, end_line = 1 },
    { path = "a", start_line = 9, end_line = 9 },
    { path = "a", start_line = 2, end_line = 5 },
  }
  payload.sort(e)
  h.eq(
    { "a2", "a9", "b1" },
    vim.tbl_map(function(x)
      return x.path .. x.start_line
    end, e)
  )
end

return T
