# nudge.nvim

コードの行や範囲に **AI エージェント（Claude Code など）へのコメント** を付けて溜めておき、
[herdr](https://herdr.dev) の同じタブで動いているエージェントのペインへ **まとめて送る** プラグインです。
PR レビューでインラインコメントを書く感覚で、エージェントに直してほしい箇所を指示できます。

[English README](README.en.md)

## 機能

- **行・範囲にコメント**（`:Nudge add`、ビジュアルモードの選択範囲にも）。範囲の全行にサインと薄い背景色が付き、先頭行の行末にコメントが出ます。
  コメントを入力している間も、対象の範囲はハイライトされたままです。
  コメントは extmark として行に付くので、送る前に上の行を編集しても位置がずれません。
- **まとめて送る**（`:Nudge send`）。全コメントを「ファイル:行 + 該当コード + コメント」の Markdown にまとめ、
  エージェントの入力欄へ bracketed paste で 1 つの貼り付けとして入れます。**Enter は押しません**。
  内容を確認してから自分で送信してください（`submit = true` で自動送信）。
- パスはエージェントのペインの作業ディレクトリからの相対パスにします。
- 送り先は同じ herdr タブの `claude` ペインです。複数あるときは最初に選び、そのタブでは選んだペインを使い続けます
  （`:Nudge target` で選び直し）。
- 一覧は quickfix に出せます（`:Nudge list`）。

送られる内容の例：

````markdown
Review comments on the code below. Please address each one.

## 1. lua/foo.lua:12-14
```lua
local function f(x)
  return x + 1
end
```
名前をもっと具体的に
````

## 必要なもの

- Neovim 0.10 以上
- [herdr](https://herdr.dev)（Neovim を herdr のペインで起動していること。`$HERDR_PANE_ID` を使います）
- 送り先のエージェントが herdr に認識されていること（`herdr pane list` の `agent` が `claude`）

## インストール

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

キーは設定しません。上は一例です。

## コマンド

| コマンド | 動作 |
| --- | --- |
| `:[range]Nudge add [text]` | 行（範囲）にコメントを追加。text を省くと入力欄が出ます |
| `:Nudge edit` / `:Nudge delete` | カーソル下のコメントを編集 / 削除 |
| `:Nudge list` | コメントを quickfix に一覧表示 |
| `:Nudge clear` | 全コメントを削除 |
| `:Nudge send` | 全コメントをエージェントのペインへ送る |
| `:Nudge target` | 送り先のペインを選び直す |

Lua からは `require("nudge").add({ line1, line2, text })` などの同名関数と、件数を返す `count()`（ステータスライン用）が使えます。

## 設定

既定値：

```lua
require("nudge").setup({
  agent = "claude",        -- 送り先（herdr の agent 名）。false ならエージェントなら何でも
  header = "Review comments on the code below. Please address each one.", -- 先頭の 1 段落。"" で無し
  submit = false,          -- 貼り付けたあと Enter も押す
  clear_on_send = true,    -- 送れたらコメントを消す
  sign = "▍",              -- 範囲の先頭行のサイン。false で無し
  virt_text_prefix = "  ✎ ",
  max_virt_text = 60,      -- 行末に出すコメントの最大文字数（0 で出さない）
})
```

ハイライトグループ：

| グループ | 用途 | 既定 |
| --- | --- | --- |
| `NudgeRange` | コメントした範囲の行の背景 | `DiagnosticHint` の色を背景に薄く混ぜた色 |
| `NudgePending` | コメントを入力している間の範囲 | `Visual` |
| `NudgeSign` | 範囲の各行のサイン | `DiagnosticSignHint` |
| `NudgeVirtText` | 行末のコメント | `DiagnosticVirtualTextHint` |

## 既知の制限

- コメントはメモリ上だけにあり、Neovim を閉じると消えます。
- 保存していない変更があるバッファの行番号は、エージェントが読むディスク上のファイルとずれることがあります（送信時に警告します）。
- コメントの入力は 1 行です（`vim.ui.input`）。
- ファイルが外から書き換えられてバッファを読み直すと、コメントの位置は保証されません。

## 開発

```sh
make test   # nvim --headless でテストを実行（herdr は偽物に差し替え）
make lint   # stylua --check
```

## ライセンス

MIT
