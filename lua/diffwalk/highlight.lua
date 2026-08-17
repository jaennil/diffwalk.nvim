local config = require("diffwalk.config")

local M = {}

--- gitsigns derives its highlight groups from the sign type, so a changed line
--- gets the theme's blue "changed" color and word diff regions fall back to
--- TermCursor, which is reverse video and reads as random bright blocks. Every
--- group is pinned to the two review colors instead.
function M.palette()
  local colors = config.options.colors

  -- a changed line is the added half of the change: green line, with the
  -- deleted original shown above it in red
  for _, group in ipairs({ "GitSignsAddLn", "GitSignsChangeLn" }) do
    vim.api.nvim_set_hl(0, group, { bg = colors.added })
  end

  vim.api.nvim_set_hl(0, "GitSignsDeleteVirtLn", { bg = colors.removed })

  for _, group in ipairs({ "GitSignsAdd", "GitSignsChange", "GitSignsUntracked" }) do
    vim.api.nvim_set_hl(0, group, { fg = colors.added_sign })
  end

  for _, group in ipairs({ "GitSignsDelete", "GitSignsTopdelete", "GitSignsChangedelete" }) do
    vim.api.nvim_set_hl(0, group, { fg = colors.removed_sign })
  end

  for _, group in ipairs({
    "GitSignsAddInline",
    "GitSignsAddLnInline",
    "GitSignsChangeInline",
    "GitSignsChangeLnInline",
  }) do
    vim.api.nvim_set_hl(0, group, { bg = colors.added_word })
  end

  for _, group in ipairs({ "GitSignsDeleteInline", "GitSignsDeleteLnInline" }) do
    vim.api.nvim_set_hl(0, group, { bg = colors.removed_word })
  end

  -- inside a fully deleted line the word diff covers arbitrary chunks, leading
  -- whitespace included, which only breaks the line into ragged shades
  vim.api.nvim_set_hl(0, "GitSignsDeleteVirtLnInLine", { bg = colors.removed })

  -- a hunk that has been looked at drops out of the loud palette
  vim.api.nvim_set_hl(0, "DiffwalkViewed", { bg = colors.viewed })
  vim.api.nvim_set_hl(0, "DiffwalkViewedSign", { fg = colors.viewed_sign })

  -- gitsigns does not attach to a file that is absent from the base, so those
  -- are painted here instead, in the same green
  vim.api.nvim_set_hl(0, "DiffwalkAdded", { bg = colors.added })
  vim.api.nvim_set_hl(0, "DiffwalkAddedSign", { fg = colors.added_sign })

  -- deleted lines are drawn by diffwalk, not gitsigns, so that their indent
  -- lines up with the real code
  vim.api.nvim_set_hl(0, "DiffwalkRemoved", { bg = colors.removed })

  -- an underline is a border that costs no line: it marks where a hunk ends
  -- without pushing the code apart, and leaves the background under it intact
  vim.api.nvim_set_hl(0, "DiffwalkEdge", { underline = true, sp = colors.edge })
end

--- @param base string revision the file buffers are diffed against
function M.enable(base)
  local gitsigns = require("gitsigns")
  local opts = config.options

  require("diffwalk.git").active(base)
  M.palette()
  gitsigns.change_base(base, true)
  gitsigns.toggle_linehl(opts.linehl)
  gitsigns.toggle_word_diff(opts.word_diff)

  -- gitsigns anchors its deleted lines to the left edge of the window
  -- (virt_lines_leftcol), which shifts them out of line with the code by the
  -- width of the sign column; diffwalk.overlay draws them instead
  gitsigns.toggle_deleted(false)
end

function M.disable()
  local gitsigns = require("gitsigns")

  gitsigns.change_base(nil, true)
  gitsigns.toggle_linehl(false)
  gitsigns.toggle_deleted(false)
  gitsigns.toggle_word_diff(false)
end

--- deleted lines are the noisiest part of a review, so keep them togglable
--- @return boolean shown
function M.toggle_deleted()
  return require("diffwalk.overlay").toggle_deleted()
end

return M
