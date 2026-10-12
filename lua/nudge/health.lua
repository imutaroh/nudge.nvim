local M = {}

function M.check()
  local health = vim.health
  health.start("nudge")

  local v = vim.version()
  local vstr = ("%d.%d.%d"):format(v.major, v.minor, v.patch)
  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim " .. vstr)
  else
    health.error("Neovim >= 0.10 required, found " .. vstr)
  end

  if vim.fn.executable("herdr") ~= 1 then
    health.error("herdr not found in PATH")
    return
  end
  health.ok("herdr found")

  if not vim.env.HERDR_PANE_ID or vim.env.HERDR_PANE_ID == "" then
    health.warn("$HERDR_PANE_ID is not set: start Neovim inside a herdr pane to send comments")
    return
  end
  local agent = require("nudge.config").options.agent
  local cands, _, err = require("nudge.herdr").candidates(agent)
  if not cands then
    health.warn(err or "could not list herdr panes")
  elseif #cands == 0 then
    health.info(("no %s pane in this herdr tab yet"):format(agent or "agent"))
  else
    for _, p in ipairs(cands) do
      health.ok(("target candidate: %s (%s)"):format(p.title or p.agent, p.pane_id))
    end
  end
end

return M
