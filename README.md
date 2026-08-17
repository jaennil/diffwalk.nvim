# diffwalk.nvim

Walk a review the way you read code: the diff is highlighted **in the file itself**, and the panel at the bottom is pure navigation.

Most diff viewers put the change in a separate buffer, where your LSP, your jumps and your muscle memory don't work. diffwalk keeps you in the real file — gitsigns paints what the branch added and removed, and a list of files and hunks tells you where to go next.

```
✓ lua/jaennil/plugins/gitsigns.lua  +25 -0  1/1
✓      9  + on_attach = function(bufnr)
  lazy-lock.json  +15 -11  0/2
       2  - "fidget.nvim": { "branch": "main", ...
      14  + "gitlab.nvim": { "branch": "develop", ...
```

## What it does

- **Branch review** — every hunk between the merge base with the default branch and your working tree. The merge base, not the branch tip, so commits that landed upstream after you branched stay out.
- **Commit review** — pick a commit from a list, walk its own diff, come back, pick the next one.
- **Reading what was removed** — deleted lines are drawn as virtual lines, and the cursor cannot enter virtual text. `:DiffwalkOld` opens the file as it was at the base in a real buffer next to it, both sides in diff mode, so a removed signature can be walked, searched and yanked.
- **Keeping track** — mark a hunk (or a whole file) as viewed, and it dims in both places at once: in the list, and in the file itself, where it drops out of the loud green and picks up a `✓` in the sign column. What is still bright is what is left to read.
- **Two colors, everywhere** — green for what the change adds, red for what it removes, in the line background, in the word diff and in the sign column.
- **Hunk borders** — each hunk is underlined where it starts and where it ends, so two of them in a row never read as one block. An underline costs no line, unlike a separator row.
- **Deleted lines that line up** — they are drawn by diffwalk rather than gitsigns, so their indent matches the code beside them, tabs included.

## Requirements

- Neovim 0.10+
- [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) — draws the in-file highlights
- `git` in `PATH`

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "jaennil/diffwalk.nvim",
  dependencies = { "lewis6991/gitsigns.nvim" },
  keys = {
    { "<leader>mh", "<CMD>DiffwalkBranch<CR>", desc = "Walk the branch diff" },
    { "<leader>mc", "<CMD>DiffwalkCommits<CR>", desc = "Walk the diff of a commit" },
    { "<leader>mo", "<CMD>DiffwalkOld<CR>", desc = "Open the base version of the file" },
    { "<leader>md", "<CMD>DiffwalkToggleDeleted<CR>", desc = "Toggle deleted lines" },
    { "<leader>mB", "<CMD>DiffwalkReset<CR>", desc = "Reset the diff base" },
  },
}
```

`setup()` is optional — the plugin works with its defaults.

## Commands

| Command | What it does |
| --- | --- |
| `:DiffwalkBranch` | Hunks of the branch against the default branch |
| `:DiffwalkCommits [n]` | Pick a commit and walk its diff (default 100 commits) |
| `:DiffwalkCommit {rev}` | Walk one commit's diff directly |
| `:DiffwalkFiles` | Changed files of the branch in the quickfix list |
| `:DiffwalkOld` | Open the base version of the file beside it, in diff mode |
| `:DiffwalkToggleDeleted` | Show or hide removed lines in the file |
| `:DiffwalkReset` | Drop the diff base and every highlight it turned on |

## In the panel

| Key | Action |
| --- | --- |
| `<CR>` | Show the hunk, cursor stays in the list |
| `o` | Show it and jump into the file |
| `]f` / `[f` | Next / previous file |
| `x` | Mark the hunk as viewed; on a file line, the whole file |
| `a` | Toggle between all hunks and only the unviewed ones |
| `<BS>` | Back to the commit list |
| `q` | Close |

## Configuration

Defaults:

```lua
require("diffwalk").setup({
  remote = "origin",
  branches = { "master", "main" }, -- fallbacks when the remote has no HEAD symref
  fetch = true,                    -- fetch the default branch before diffing

  commits = 100,
  position = "right",  -- right, left, bottom or top
  size = 60,           -- columns on a side, lines otherwise

  vertical = true,   -- :DiffwalkOld splits vertically
  edges = true,      -- underline where each hunk starts and ends
  linehl = true,     -- paint the whole line, not just the sign
  deleted = true,    -- show removed lines as virtual lines
  word_diff = true,  -- highlight the changed regions inside a line

  colors = {
    added = "#005f00",
    added_word = "#008700",
    added_sign = "#5fd75f",
    removed = "#5f0000",
    removed_word = "#870000",
    removed_sign = "#ff005f",
    viewed = "#1c2a1c",
    viewed_sign = "#5f875f",
    edge = "#6c7079",
  },

  keys = {
    open = "<CR>",
    focus = "o",
    next_file = "]f",
    prev_file = "[f",
    mark = "x",
    filter = "a",
    back = "<BS>",
    close = "q",
  },
})
```

Set a key to `false` or `""` to leave it unmapped.

### Why the colors are hardcoded by default

Themes keep `DiffAdd` and `DiffDelete` a couple of shades above the background, which is fine for a side-by-side diff and useless when the color has to survive on top of syntax highlighting. The defaults are the 256-color diff palette, deliberately saturated. Point them at your theme if you prefer:

```lua
colors = { added = "#1d2214", removed = "#2d2220", ... }
```

## Caveats

- `<CR>` opens the **current** version of the file. For a branch review that's exact; for an old commit the line numbers drift as far as the file has moved since.
- Removed lines are virtual lines — they push the real code down. `:DiffwalkToggleDeleted` turns them off, `:DiffwalkOld` gives you a buffer to walk them in.
- Only the changed lines of a viewed hunk are dimmed, never the context around them.
- Viewed marks live in memory for the session and are keyed by file and line, so they are dropped by `:DiffwalkReset` and stop matching once the hunks move under them.
- The buffer `:DiffwalkOld` opens is not a file on disk: treesitter highlights it, but no LSP attaches to it.

## License

MIT
