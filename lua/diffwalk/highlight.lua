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
end

--- @param base string revision the file buffers are diffed against
function M.enable(base)
  local gitsigns = require("gitsigns")
  local opts = config.options

  require("diffwalk.git").active(base)
  M.palette()
  gitsigns.change_base(base, true)
  gitsigns.toggle_linehl(opts.linehl)
  gitsigns.toggle_deleted(opts.deleted)
  gitsigns.toggle_word_diff(opts.word_diff)
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
  return require("gitsigns").toggle_deleted()
end

return M
