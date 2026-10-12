# nudge.nvim

Leave **comments for an AI coding agent (Claude Code, …)** on lines and ranges of your code, then **send them all
at once** to the agent running in the same [herdr](https://herdr.dev) tab. Like inline PR review comments, but for
your agent.

[日本語 README](README.md)

## Features

- **Comment on a line or a range** (`:Nudge add`, also from a visual selection). Every line of a commented range gets a
  sign and a tinted background, and the comment shows at the end of the first line. While you type a comment, its range
  stays highlighted. Comments are extmarks, so they stay on their lines while you keep editing.
- **Send them together** (`:Nudge send`): every comment becomes "file:line + code + comment" Markdown, pasted into the
  agent's prompt as a single bracketed paste. **Enter is not pressed**: review it and submit it yourself
  (or set `submit = true`).
- Paths are relative to the agent pane's working directory.
- The target is the `claude` pane in the same herdr tab. With several, you pick one the first time and it is
  remembered for that tab (`:Nudge target` to pick again).
- List them in the quickfix list (`:Nudge list`).

## Requirements

- Neovim >= 0.10
- [herdr](https://herdr.dev), with Neovim running in a herdr pane (`$HERDR_PANE_ID` is used)
- The agent recognized by herdr (`agent` is `claude` in `herdr pane list`)

## Installation

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "imutaroh/nudge.nvim",
  cmd = "Nudge",
  keys = {
    { "<leader>aa", function() require("nudge").add() end, mode = { "n", "x" }, desc = "Comment for the agent" },
    { "<leader>ae", function() require("nudge").edit() end, desc = "Edit comment" },
    { "<leader>ad", function() require("nudge").delete() end, desc = "Delete comment" },
    { "<leader>al", function() require("nudge").list() end, desc = "List comments" },
    { "<leader>as", function() require("nudge").send() end, desc = "Send comments to the agent" },
  },
  opts = {},
}
```

No keys are mapped by default.

## Commands

| Command | Action |
| --- | --- |
| `:[range]Nudge add [text]` | Comment on the line (range); prompts when text is omitted |
| `:Nudge edit` / `:Nudge delete` | Edit / delete the comment under the cursor |
| `:Nudge list` | Comments in the quickfix list |
| `:Nudge clear` | Delete every comment |
| `:Nudge send` | Send every comment to the agent pane |
| `:Nudge target` | Pick the target pane again |

The same functions are available from Lua (`require("nudge").add({ line1, line2, text })`, …), plus `count()` for
statuslines.

## Configuration

Defaults:

```lua
require("nudge").setup({
  agent = "claude",        -- target agent as named by herdr; false = any agent
  header = "Review comments on the code below. Please address each one.", -- first paragraph; "" = none
  submit = false,          -- also press Enter after pasting
  clear_on_send = true,    -- remove the comments once sent
  sign = "▍",              -- sign on the first line of a range; false = none
  virt_text_prefix = "  ✎ ",
  max_virt_text = 60,      -- max characters of end-of-line text (0 = hide)
})
```

Highlight groups:

| Group | Used for | Default |
| --- | --- | --- |
| `NudgeRange` | Background of commented lines | A faint tint of `DiagnosticHint` over the background |
| `NudgePending` | The range while its comment is typed | `Visual` |
| `NudgeSign` | Sign on every line of a range | `DiagnosticSignHint` |
| `NudgeVirtText` | End-of-line comment | `DiagnosticVirtualTextHint` |

## Known limitations

- Comments live in memory only and are gone when Neovim exits.
- Line numbers of a buffer with unsaved changes may not match the file on disk that the agent reads (warned on send).
- Comments are a single line (`vim.ui.input`).
- When the file changes on disk and the buffer is reloaded, comment positions are not guaranteed.

## Development

```sh
make test   # headless tests (herdr is faked)
make lint   # stylua --check
```

## License

MIT
