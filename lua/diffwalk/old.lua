local config = require("diffwalk.config")
local git = require("diffwalk.git")

local M = {}

local NAME = "diffwalk-old://"

--- @param name string
local function wipe_existing(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == name then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
end

--- Deleted lines are drawn as virtual lines, and virtual text cannot hold the
--- cursor. This opens the file as it looks at the diff base in a real buffer
--- beside the current one, both in diff mode, so a removed signature can be
--- moved through, searched and yanked.
function M.open()
  local base = git.active()
  if not base then
    vim.notify("diffwalk: no diff base yet, start a review first", vim.log.levels.WARN)
    return
  end

  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    vim.notify("diffwalk: this window holds no file", vim.log.levels.WARN)
    return
  end

  local relpath = git.relpath(file)
  if not relpath then
    vim.notify("diffwalk: " .. file .. " is outside the repository", vim.log.levels.WARN)
    return
  end

  local text = git.show(base, relpath)
  if not text then
    vim.notify("diffwalk: " .. relpath .. " does not exist at " .. base:sub(1, 7), vim.log.levels.WARN)
    return
  end

  local lnum = vim.fn.line(".")
  local source = vim.api.nvim_get_current_win()
  local name = ("%s%s/%s"):format(NAME, base:sub(1, 7), relpath)

  wipe_existing(name)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].filetype = vim.filetype.match({ filename = relpath, buf = buf }) or vim.bo.filetype
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  vim.cmd(config.options.vertical and "leftabove vsplit" or "leftabove split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_cursor(win, { math.min(lnum, #text), 0 })

  -- both sides in diff mode, so the halves line up and ]c / [c work
  vim.cmd("diffthis")
  vim.api.nvim_set_current_win(source)
  vim.cmd("diffthis")
  vim.api.nvim_set_current_win(win)
  vim.cmd("normal! zz")

  vim.keymap.set("n", config.options.keys.close, function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_win_is_valid(source) then
      vim.api.nvim_set_current_win(source)
      vim.cmd("diffoff")
    end
  end, { buffer = buf, desc = "Close the base version" })

  return buf, win
end

return M
