local config = require("diffwalk.config")
local diff = require("diffwalk.diff")
local git = require("diffwalk.git")
local highlight = require("diffwalk.highlight")
local overlay = require("diffwalk.overlay")
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

  local files = diff.parse(out)
  overlay.set(base, files)
  panel.hunks(base:sub(1, 7), files, base)
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
--- @param back? function what <BS> returns to
function M.commit(rev, back)
  local parent = git.parent(rev)
  local out = git.run({ "git", "diff", "--no-color", parent, rev })

  if not out or out == "" then
    vim.notify("diffwalk: no changes in " .. rev)
    return
  end

  highlight.enable(parent)

  local files = diff.parse(out)
  overlay.set(parent, files)
  panel.hunks(rev, files, parent, back)
end

--- pick a commit, then walk its diff; <CR> drills in, <BS> comes back here
--- @param limit? integer
function M.commits(limit)
  limit = limit or config.options.commits

  local entries = git.commits(limit)
  if not entries or #entries == 0 then
    vim.notify("diffwalk: no commits", vim.log.levels.WARN)
    return
  end

  local lines, marks, targets = diff.render_commits(entries)
  local buf = panel.open("commits", lines, marks)
  local keys = config.options.keys

  panel.map(buf, keys.open, function()
    local entry = targets[vim.fn.line(".")]
    if entry then
      M.commit(entry.rev, function()
        M.commits(limit)
      end)
    end
  end, "Show this commit's diff")
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
  require("diffwalk.viewed").clear()
  overlay.clear()
  git.forget()
  highlight.disable()
  vim.cmd("diffoff!")
end

return M
