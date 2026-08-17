local config = require("diffwalk.config")

local M = {}

local ns = vim.api.nvim_create_namespace("diffwalk")
local NAME = "diffwalk://"

--- buffers and window left over from a previous list; the buffer survives
--- closing the window, and its name would collide with the new one
local function previous()
  local bufs = {}

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf):find(NAME, 1, true) then
      table.insert(bufs, buf)
    end
  end

  local win
  for _, candidate in ipairs(vim.api.nvim_list_wins()) do
    if vim.tbl_contains(bufs, vim.api.nvim_win_get_buf(candidate)) then
      win = candidate
    end
  end

  return { bufs = bufs, win = win }
end

--- a scratch buffer in a split, reusing the window of a list opened earlier
--- @param name string suffix of the buffer name
--- @param lines string[]
--- @param marks table[] {line, from_col, to_col, group}
--- @return integer buf, integer win, integer origin window the files open in
function M.open(name, lines, marks)
  local opts = config.options
  local stale = previous()

  local origin = vim.api.nvim_get_current_win()
  if stale.win and origin == stale.win then
    origin = vim.fn.win_getid(vim.fn.winnr("#"))
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "diffwalk"
  vim.bo[buf].bufhidden = "wipe"

  for _, mark in ipairs(marks) do
    local line, from, to, group = unpack(mark)
    vim.api.nvim_buf_set_extmark(buf, ns, line - 1, from, { end_col = to, hl_group = group })
  end

  vim.bo[buf].modifiable = false

  if vim.api.nvim_win_is_valid(stale.win or -1) then
    vim.api.nvim_win_set_buf(stale.win, buf)
    vim.api.nvim_set_current_win(stale.win)
  else
    vim.cmd(("%s %dsplit"):format(opts.position, opts.height))
    vim.api.nvim_win_set_buf(0, buf)
  end

  for _, old in ipairs(stale.bufs) do
    if vim.api.nvim_buf_is_valid(old) then
      vim.api.nvim_buf_delete(old, { force = true })
    end
  end

  vim.api.nvim_buf_set_name(buf, NAME .. name)
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.signcolumn = "no"
  vim.wo.wrap = false
  vim.wo.cursorline = true
  vim.wo.winfixheight = true

  return buf, vim.api.nvim_get_current_win(), origin
end

--- @param buf integer
--- @param lhs string?
--- @param rhs string|function
--- @param desc string
function M.map(buf, lhs, rhs, desc)
  if lhs and lhs ~= "" then
    vim.keymap.set("n", lhs, rhs, { buffer = buf, desc = desc })
  end
end

--- a hunk list: jumping into the file, walking files, going back, closing
--- @param name string
--- @param lines string[]
--- @param marks table[]
--- @param targets table<integer, table>
--- @param back? function what <BS> returns to
function M.hunks(name, lines, marks, targets, back)
  local keys = config.options.keys
  local buf, list, origin = M.open(name, lines, marks)

  local function open(focus)
    local target = targets[vim.fn.line(".")]
    if not target then
      return
    end

    if not vim.uv.fs_stat(target.file) then
      vim.notify(target.file .. " is gone in the working tree", vim.log.levels.WARN)
      return
    end

    if vim.api.nvim_win_is_valid(origin) then
      vim.api.nvim_set_current_win(origin)
    else
      vim.cmd("wincmd p")
    end

    vim.cmd("edit " .. vim.fn.fnameescape(target.file))
    local last = vim.api.nvim_buf_line_count(0)
    vim.api.nvim_win_set_cursor(0, { math.min(math.max(target.lnum, 1), last), 0 })
    vim.cmd("normal! zz")

    if not focus and vim.api.nvim_win_is_valid(list) then
      vim.api.nvim_set_current_win(list)
    end
  end

  --- next/previous file header, so ]f skips over the hunks in between
  local function to_file(step)
    local line = vim.fn.line(".")
    for i = line + step, step > 0 and #lines or 1, step do
      if targets[i] and targets[i].header then
        vim.api.nvim_win_set_cursor(list, { i, 0 })
        return
      end
    end
  end

  M.map(buf, keys.open, function()
    open(true)
  end, "Open hunk")
  M.map(buf, keys.preview, function()
    open(false)
  end, "Preview hunk, keep focus on the list")
  M.map(buf, keys.next_file, function()
    to_file(1)
  end, "Next file")
  M.map(buf, keys.prev_file, function()
    to_file(-1)
  end, "Previous file")
  M.map(buf, keys.close, "<CMD>close<CR>", "Close the list")

  if back then
    M.map(buf, keys.back, back, "Back to the commit list")
  end

  return buf
end

return M
