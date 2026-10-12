-- Turns resolved comments into the message pasted into the agent. Pure functions: no herdr, no UI.
local M = {}

---@class nudge.Entry
---@field path string As shown to the agent
---@field start_line integer 1-based
---@field end_line integer 1-based, inclusive
---@field lines string[] Code of the range
---@field lang string Fence language (filetype)
---@field text string The comment

---Fence longer than any backtick run in the code, so the code cannot close it.
---@param lines string[]
---@return string
function M.fence(lines)
  local longest = 0
  for _, l in ipairs(lines) do
    for run in l:gmatch("`+") do
      longest = math.max(longest, #run)
    end
  end
  return string.rep("`", math.max(3, longest + 1))
end

---Path relative to `cwd` when the file is inside it, absolute otherwise.
---@param path string absolute
---@param cwd string|nil absolute
---@return string
function M.relative(path, cwd)
  if not cwd or cwd == "" then
    return path
  end
  cwd = cwd:gsub("/+$", "")
  if path:sub(1, #cwd + 1) == cwd .. "/" then
    return path:sub(#cwd + 2)
  end
  return path
end

---@param e nudge.Entry
---@return string
function M.location(e)
  if e.start_line == e.end_line then
    return ("%s:%d"):format(e.path, e.start_line)
  end
  return ("%s:%d-%d"):format(e.path, e.start_line, e.end_line)
end

---Sort by path, then line, so the agent reads the comments file by file.
---@param entries nudge.Entry[]
function M.sort(entries)
  table.sort(entries, function(a, b)
    if a.path ~= b.path then
      return a.path < b.path
    end
    if a.start_line ~= b.start_line then
      return a.start_line < b.start_line
    end
    return a.end_line < b.end_line
  end)
end

---@param entries nudge.Entry[] already sorted
---@param header string|nil
---@return string
function M.build(entries, header)
  local out = {}
  if header and header ~= "" then
    out[#out + 1] = header
    out[#out + 1] = ""
  end
  for i, e in ipairs(entries) do
    if i > 1 then
      out[#out + 1] = ""
    end
    local f = M.fence(e.lines)
    out[#out + 1] = ("## %d. %s"):format(i, M.location(e))
    out[#out + 1] = f .. e.lang
    vim.list_extend(out, e.lines)
    out[#out + 1] = f
    out[#out + 1] = e.text
  end
  return table.concat(out, "\n")
end

return M
