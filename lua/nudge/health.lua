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

  local herdr = require("nudge.herdr")
  local backend = herdr.backend()
  if not backend then
    health.warn("neither $HC_TERMINAL_ID nor $HERDR_PANE_ID is set: start Neovim inside a herdr pane to send comments")
    return
  end
  local needed = backend == "hc" and { "herdr-app", "hc" } or { "herdr" }
  for _, exe in ipairs(needed) do
    if vim.fn.executable(exe) ~= 1 then
      health.error(exe .. " not found in PATH")
      return
    end
  end
  health.ok(("%s (%s found)"):format(backend == "hc" and "Herdr app" or "herdr TUI", table.concat(needed, ", ")))

  local agent = require("nudge.config").options.agent
  local cands, _, err = herdr.candidates(agent)
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
