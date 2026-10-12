if vim.g.loaded_nudge then
  return
end
vim.g.loaded_nudge = true

if vim.fn.has("nvim-0.10") ~= 1 then
  vim.notify("nudge: requires Neovim >= 0.10", vim.log.levels.WARN)
  return
end

vim.api.nvim_create_user_command("Nudge", function(cmd)
  require("nudge")._command(cmd)
end, {
  nargs = "*",
  range = true,
  desc = "Comment on code for an agent (add, edit, delete, list, clear, send, target)",
  complete = function(arglead, cmdline)
    -- Only the subcommand is completed; `add` takes free text.
    if cmdline:match("Nudge%s+%S+%s") then
      return {}
    end
    return vim.tbl_filter(function(s)
      return vim.startswith(s, arglead)
    end, require("nudge")._subcommands())
  end,
})
