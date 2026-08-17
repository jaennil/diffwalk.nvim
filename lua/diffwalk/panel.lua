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

--- @param buf integer
--- @param lines string[]
--- @param marks table[] {line, from_col, to_col, group}; to_col -1 means end of line
function M.paint(buf, lines, marks)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  for _, mark in ipairs(marks) do
    local line, from, to, group = unpack(mark)
    local last = #(lines[line] or "")
    vim.api.nvim_buf_set_extmark(buf, ns, line - 1, math.min(from, last), {
      end_col = to == -1 and last or math.min(to, last),
      hl_group = group,
    })
  end
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

  M.paint(buf, lines, marks)
  vim.bo[buf].modifiable = false

  if vim.api.nvim_win_is_valid(stale.win or -1) then
    vim.api.nvim_win_set_buf(stale.win, buf)
    vim.api.nvim_set_current_win(stale.win)
  else
    local side = opts.position == "right" or opts.position == "left"
    local anchor = (opts.position == "right" or opts.position == "bottom") and "botright" or "topleft"
    vim.cmd(("%s %d%s"):format(anchor, opts.size, side and "vsplit" or "split"))
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
  vim.wo.winfixwidth = true
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

--- a hunk list: jumping into the file, walking files, marking what has been
--- looked at, hiding it, going back, closing
--- @param name string
--- @param files table[] as returned by diff.parse
--- @param base string revision the diff is against
--- @param back? function what <BS> returns to
function M.hunks(name, files, base, back)
  local diff = require("diffwalk.diff")
  local viewed = require("diffwalk.viewed")
  local opts = config.options
  local keys = opts.keys

  local hide = false
  local lines, marks, targets = diff.render(files, base, hide)
  local buf, list, origin = M.open(name, lines, marks)

  local function redraw()
    local cursor = vim.api.nvim_win_get_cursor(list)

    lines, marks, targets = diff.render(files, base, hide)

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    M.paint(buf, lines, marks)

    vim.api.nvim_win_set_cursor(list, { math.min(math.max(cursor[1], 1), math.max(#lines, 1)), 0 })
  end

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

    -- gitsigns attaches and diffs asynchronously: the first paint of a buffer
    -- lands before any of it exists, leaving the file looking unchanged and
    -- deleted virtual lines missing their indent until something redraws.
    -- The update event is the usual cue, but it can fire before this even
    -- subscribes, so the screen is nudged a few times regardless.
    vim.api.nvim_create_autocmd("User", {
      pattern = "GitSignsUpdate",
      once = true,
      callback = function()
        vim.cmd("redraw!")
      end,
    })

    local timer = vim.uv.new_timer()
    local tries = 0
    timer:start(
      60,
      220,
      vim.schedule_wrap(function()
        tries = tries + 1
        vim.cmd("redraw!")

        if tries >= 3 and not timer:is_closing() then
          timer:stop()
          timer:close()
        end
      end)
    )

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
    open(false)
  end, "Show the hunk, keep the cursor in the list")
  M.map(buf, keys.focus, function()
    open(true)
  end, "Show the hunk and jump into the file")
  M.map(buf, keys.next_file, function()
    to_file(1)
  end, "Next file")
  M.map(buf, keys.prev_file, function()
    to_file(-1)
  end, "Previous file")
  M.map(buf, keys.mark, function()
    local target = targets[vim.fn.line(".")]
    if target and target.keys then
      viewed.toggle_all(target.keys)
      redraw()
      require("diffwalk.overlay").refresh_all()
    end
  end, "Mark the hunk, or the whole file, as viewed")
  M.map(buf, keys.filter, function()
    hide = not hide
    redraw()
    vim.notify("diffwalk: showing " .. (hide and "unviewed hunks" or "all hunks"))
  end, "Show all hunks or only the unviewed ones")
  M.map(buf, keys.close, "<CMD>close<CR>", "Close the list")

  if back then
    M.map(buf, keys.back, back, "Back to the commit list")
  end

  return buf
end

return M
