-- Test runner: nvim --headless --clean -l tests/run.lua [filter]
-- Discovers tests/*_spec.lua (each returns { ["test name"] = fn, ... }), runs them in sorted order and exits
-- non-zero on any failure. No external dependencies; herdr is replaced by a fake.

local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(vim.fn.fnamemodify(source, ":p"), ":h:h")
vim.opt.rtp:prepend(root)
package.path = root .. "/tests/?.lua;" .. package.path

-- --clean implies -u NONE, which skips plugin/ scripts.
vim.cmd("runtime! plugin/nudge.lua")

local h = require("helpers")
h.init(root)

local filter = _G.arg and _G.arg[1] or nil

local files = vim.fn.glob(root .. "/tests/*_spec.lua", false, true)
table.sort(files)

local passed, failed, failures = 0, 0, {}

for _, file in ipairs(files) do
  local suite = vim.fn.fnamemodify(file, ":t:r")
  local ok, tests = pcall(dofile, file)
  if not ok or type(tests) ~= "table" then
    failed = failed + 1
    failures[#failures + 1] = ("%s: failed to load: %s"):format(suite, tostring(tests))
    io.write(("FAIL %s (load)\n  %s\n"):format(suite, tostring(tests)))
  else
    local names = vim.tbl_keys(tests)
    table.sort(names)
    for _, name in ipairs(names) do
      local full = suite .. " :: " .. name
      if not filter or full:find(filter, 1, true) then
        h.reset()
        local tok, err = xpcall(tests[name], debug.traceback)
        if tok then
          passed = passed + 1
          io.write("ok   " .. full .. "\n")
        else
          failed = failed + 1
          failures[#failures + 1] = full .. "\n    " .. tostring(err):gsub("\n", "\n    ")
          io.write("FAIL " .. full .. "\n")
        end
      end
    end
  end
end

h.teardown()

if #failures > 0 then
  io.write("\nFailures:\n")
  for _, f in ipairs(failures) do
    io.write("  " .. f .. "\n")
  end
end
io.write(("\n%d passed, %d failed\n"):format(passed, failed))
io.flush()
os.exit(failed > 0 and 1 or 0)
