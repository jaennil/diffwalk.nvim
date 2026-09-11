local config = require("diffwalk.config")
local diff = require("diffwalk.diff")
local git = require("diffwalk.git")
local highlight = require("diffwalk.highlight")
local overlay = require("diffwalk.overlay")
local viewed = require("diffwalk.viewed")
local panel = require("diffwalk.panel")

local M = {}

--- @param opts? table see :help diffwalk-config
function M.setup(opts)
  config.setup(opts)
end

--- hunks of the current branch against the merge base with the default branch
function M.branch()
  local base, branch = git.base(false)
  if not base then
    return
  end

  local out = git.run({ "git", "diff", "--no-color", base })
  if not out then
    return
  end

  if out == "" then
    vim.notify("diffwalk: no changes against " .. config.options.remote .. "/" .. branch)
    return
  end

  highlight.enable(base)

  viewed.load(git.root())

  local files = diff.parse(out)
  overlay.set(base, files)
  panel.hunks(base:sub(1, 7), function()
    return diff.snapshot(base)
  end, base)
end

--- changed files of the branch in the quickfix list
function M.files()
  local base, branch = git.base(true)
  if not base then
    return
  end

  local out = git.run({ "git", "diff", "--name-only", base })
  if not out then
    return
  end

  highlight.enable(base)

  local items = {}
  for file in vim.gsplit(out, "\n", { plain = true, trimempty = true }) do
    table.insert(items, { filename = file, lnum = 1, col = 1, text = file })
  end

  local title = ("changes against %s/%s"):format(config.options.remote, branch)
  vim.fn.setqflist({}, " ", { title = title, items = items })
  vim.cmd("copen")
end

--- one commit's own changes, diffed against its parent
--- @param rev string
--- @param opts? {back?: function, next?: function, prev?: function, title?: string}
function M.commit(rev, opts)
  local parent = git.parent(rev)
  local out = git.run({ "git", "diff", "--no-color", parent, rev })

  if not out or out == "" then
    vim.notify("diffwalk: no changes in " .. rev)
    return
  end

  highlight.enable(parent)
  viewed.load(git.root())

  local files = diff.parse(out)
  overlay.set(parent, files)
  panel.hunks(rev, function()
    return files -- a commit does not change under you
  end, parent, opts)
end

--- Walk a list of commits: <CR> drills into one, the commit keys step to its
--- neighbour without coming back here, and <BS> returns to the row you left
--- rather than to the top of the list.
--- @param limit? integer
--- @param at? integer row to put the cursor on
function M.commits(limit, at)
  limit = limit or config.options.commits

  local entries = git.commits(limit)
  if not entries or #entries == 0 then
    vim.notify("diffwalk: no commits", vim.log.levels.WARN)
    return
  end

  viewed.load(git.root())

  local lines, marks, targets = diff.render_commits(entries)
  local buf, win = panel.open("commits", lines, marks)
  local keys = config.options.keys

  local function redraw()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    lines, marks, targets = diff.render_commits(entries)

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    panel.paint(buf, lines, marks)

    vim.api.nvim_win_set_cursor(win, { math.min(row, #lines), 0 })
  end

  if at then
    vim.api.nvim_win_set_cursor(win, { math.min(math.max(at, 1), #lines), 0 })
  end

  --- @param row integer index into the list
  local function walk(row)
    local entry = targets[row]
    if not entry then
      return
    end

    M.commit(entry.rev, {
      auto = true,
      title = ("%s  %s  %s"):format(entry.rev, entry.age, entry.subject),
      back = function()
        M.commits(limit, row)
      end,
      next = function()
        if targets[row + 1] then
          walk(row + 1)
        else
          vim.notify("diffwalk: last commit")
        end
      end,
      prev = function()
        if targets[row - 1] then
          walk(row - 1)
        else
          vim.notify("diffwalk: first commit")
        end
      end,
    })
  end

  panel.map(buf, keys.open, function()
    walk(vim.fn.line("."))
  end, "Show this commit's diff")
  panel.map(buf, keys.mark, function()
    local entry = targets[vim.fn.line(".")]
    if entry then
      viewed.toggle_all(entry.keys)
      redraw()
    end
  end, "Mark this commit as gone through")
  panel.map(buf, keys.next_commit, function()
    vim.api.nvim_win_set_cursor(win, { math.min(vim.fn.line(".") + 1, #lines), 0 })
  end, "Next commit")
  panel.map(buf, keys.prev_commit, function()
    vim.api.nvim_win_set_cursor(win, { math.max(vim.fn.line(".") - 1, 1), 0 })
  end, "Previous commit")
  panel.map(buf, keys.close, "<CMD>close<CR>", "Close the commit list")
end

--- open the version of the current file the diff is against, side by side, so
--- the cursor can walk the removed lines; see |diffwalk-old|
function M.old()
  return require("diffwalk.old").open()
end

--- show or hide the removed lines in the file buffers
function M.toggle_deleted()
  return highlight.toggle_deleted()
end

--- drop the diff base and every highlight it turned on
function M.reset()
  viewed.clear()
  overlay.clear()
  git.forget()
  highlight.disable()
  vim.cmd("diffoff!")
end

return M
