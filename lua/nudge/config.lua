local M = {}

---@class nudge.Config
---@field agent string|false Agent name to send to, as herdr reports it (`.agent` in `herdr pane list`); false = any agent
---@field header string|nil First paragraph of the message; nil or "" = none
---@field submit boolean Press Enter after pasting (false: leave the message in the agent's prompt to review)
---@field clear_on_send boolean Remove the comments once they were sent successfully
---@field sign string|false Sign shown on the first line of a commented range; false = no sign
---@field virt_text_prefix string Prefix of the comment shown at the end of the first line
---@field max_virt_text integer Truncate the end-of-line comment to this many characters (0 = do not show it)

---@type nudge.Config
M.defaults = {
  agent = "claude",
  header = "Review comments on the code below. Please address each one.",
  submit = false,
  clear_on_send = true,
  sign = "▍",
  virt_text_prefix = "  ✎ ",
  max_virt_text = 60,
}

---@type nudge.Config
M.options = vim.deepcopy(M.defaults)

---@param opts? table
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
