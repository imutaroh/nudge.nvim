-- Test helpers: scratch files under tests/.tmp/run, a fake herdr, fakes for vim.ui and vim.notify, assertions.
local M = {}

local uv = vim.uv or vim.loop

M.root = nil ---@type string
M.tmp = nil ---@type string

local real_select = vim.ui.select
local real_input = vim.ui.input
local real_notify = vim.notify
local real_run = require("nudge.herdr").run
local notes = {}
local calls = {}
local counter = 0

---@param root string repository root of nudge.nvim
function M.init(root)
  M.root = root
  M.tmp = root .. "/tests/.tmp/run"
  vim.fn.delete(M.tmp, "rf")
  vim.fn.mkdir(M.tmp, "p")
  M.tmp = uv.fs_realpath(M.tmp)
end

function M.teardown()
  vim.fn.delete(M.tmp, "rf")
end

function M.reset()
  require("nudge.store").clear()
  require("nudge.herdr")._reset()
  require("nudge").setup()
  vim.cmd("silent! %bwipeout!")
  vim.ui.select = real_select
  vim.ui.input = real_input
  require("nudge.herdr").run = real_run
  vim.env.HERDR_PANE_ID = nil
  notes = {}
  calls = {}
  vim.notify = function(msg, level)
    notes[#notes + 1] = { msg = tostring(msg), level = level or vim.log.levels.INFO }
  end
end

---@return { msg: string, level: integer }[]
function M.notifications()
  return notes
end

---Open a new file buffer with `lines` (written to disk, so it is unmodified).
---@param name string
---@param lines string[]
---@param dir? string directory to create it in (default: a fresh one)
---@return integer buf, string path
function M.file(name, lines, dir)
  if not dir then
    counter = counter + 1
    dir = M.tmp .. "/" .. counter
  end
  vim.fn.mkdir(dir, "p")
  local path = dir .. "/" .. name
  vim.fn.writefile(lines, path)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  return vim.api.nvim_get_current_buf(), path
end

---Replace herdr with a fake. `panes` is what `herdr pane list` reports; every call is recorded.
---@param panes table[]
---@param fail? table<string, boolean> subcommands ("send-text", "send-keys", "list") that should fail
function M.fake_herdr(panes, fail)
  fail = fail or {}
  require("nudge.herdr").run = function(args)
    calls[#calls + 1] = args
    local sub = args[3]
    if fail[sub] then
      return { code = 1, stdout = "", stderr = sub .. " broke" }
    end
    if sub == "list" then
      return { code = 0, stdout = vim.json.encode({ result = { panes = panes } }), stderr = "" }
    end
    return { code = 0, stdout = "{}", stderr = "" }
  end
end

---@return string[][]
function M.calls()
  return calls
end

---Calls whose subcommand (`herdr pane <sub>`) matches.
---@param sub string
---@return string[][]
function M.calls_of(sub)
  return vim.tbl_filter(function(c)
    return c[3] == sub
  end, calls)
end

---Answer the next vim.ui.select with the item for which `pick(item)` is true (nil = cancel).
---@param pick fun(item: any): boolean
function M.answer_select(pick)
  vim.ui.select = function(items, _, cb)
    M.select_count = (M.select_count or 0) + 1
    for _, it in ipairs(items) do
      if pick(it) then
        return cb(it)
      end
    end
    cb(nil)
  end
end

---@param text string|nil
function M.answer_input(text)
  vim.ui.input = function(_, cb)
    cb(text)
  end
end

function M.eq(expected, actual, msg)
  if not vim.deep_equal(expected, actual) then
    error(("%sexpected %s, got %s"):format(msg and (msg .. ": ") or "", vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

function M.truthy(v, msg)
  if not v then
    error(msg or "expected a truthy value", 2)
  end
end

return M
