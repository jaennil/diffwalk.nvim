local M = {}

--- @class DiffwalkColors
--- @field added string background of a line the change adds
--- @field added_word string background of an added word diff region
--- @field added_sign string foreground of the sign next to an added line
--- @field removed string background of a line the change removes
--- @field removed_word string background of a removed word diff region
--- @field removed_sign string foreground of the sign next to a removed line

--- @class DiffwalkConfig
--- @field remote string remote the default branch is looked up on
--- @field branches string[] fallbacks when the remote has no HEAD symref
--- @field fetch boolean fetch the default branch before diffing
--- @field commits integer how many commits the picker lists
--- @field height integer height of the panel
--- @field position string modifier for the panel split
--- @field linehl boolean paint the whole line, not just the sign
--- @field deleted boolean show removed lines as virtual lines
--- @field word_diff boolean highlight the changed regions inside a line
--- @field vertical boolean open the base version of a file in a vertical split
--- @field colors DiffwalkColors
--- @field keys table<string, string>
local defaults = {
  remote = "origin",
  branches = { "master", "main" },
  fetch = true,

  commits = 100,
  height = 15,
  position = "botright",

  linehl = true,
  deleted = true,
  word_diff = true,
  vertical = true,

  -- most themes keep their diff colors a few shades above the background,
  -- which barely reads as green or red; these are deliberately saturated
  colors = {
    added = "#005f00",
    added_word = "#008700",
    added_sign = "#5fd75f",
    removed = "#5f0000",
    removed_word = "#870000",
    removed_sign = "#ff005f",
  },

  keys = {
    open = "<CR>",
    preview = "o",
    next_file = "]f",
    prev_file = "[f",
    back = "<BS>",
    close = "q",
  },
}

--- @type DiffwalkConfig
M.options = vim.deepcopy(defaults)

--- @param opts? table
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  return M.options
end

return M
