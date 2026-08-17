local git = require("diffwalk.git")

local M = {}

--- files with their hunks, each hunk pointing at its first changed line
--- @param diff string output of git diff
--- @return table[] files
function M.parse(diff)
  local files, file, hunk, lnum = {}, nil, nil, nil

  for _, line in ipairs(vim.split(diff, "\n", { plain = true })) do
    local old = line:match("^%-%-%- a/(.*)$")
    local new = line:match("^%+%+%+ b/(.*)$")
    local start = line:match("^@@ %-[%d,]+ %+(%d+)")
    local kind = line:sub(1, 1)

    if line:match("^diff %-%-git ") then
      file, hunk = nil, nil
    elseif old then
      file = { path = old, added = 0, removed = 0, hunks = {} }
    elseif new or line == "+++ /dev/null" then
      file = file or { added = 0, removed = 0, hunks = {} }
      file.path = new or file.path -- a deleted file keeps its old path
      table.insert(files, file)
    elseif start and file then
      lnum = tonumber(start)
      hunk = { lnum = lnum, added = 0, removed = 0 }
      table.insert(file.hunks, hunk)
    elseif hunk and kind == "+" then
      file.added, hunk.added = file.added + 1, hunk.added + 1
      if not hunk.text then
        hunk.lnum, hunk.sign, hunk.text = lnum, "+", vim.trim(line:sub(2))
      end
      lnum = lnum + 1
    elseif hunk and kind == "-" then
      file.removed, hunk.removed = file.removed + 1, hunk.removed + 1
      if not hunk.text then
        hunk.lnum, hunk.sign, hunk.text = lnum, "-", vim.trim(line:sub(2))
      end
    elseif hunk and kind == " " then
      lnum = lnum + 1
    end
  end

  return files
end

--- one line per file, one per hunk; targets[line] is where <CR> jumps
--- @param files table[]
--- @return string[] lines, table[] marks, table<integer, table> targets
function M.render(files)
  local lines, marks, targets = {}, {}, {}
  local root = git.root()

  for _, file in ipairs(files) do
    local path = root .. "/" .. file.path
    local added = ("+%d"):format(file.added)
    local removed = ("-%d"):format(file.removed)

    table.insert(lines, ("%s  %s %s"):format(file.path, added, removed))
    targets[#lines] = {
      file = path,
      lnum = file.hunks[1] and file.hunks[1].lnum or 1,
      header = true,
    }

    local col = #file.path + 2
    table.insert(marks, { #lines, 0, #file.path, "Directory" })
    table.insert(marks, { #lines, col, col + #added, "Added" })
    table.insert(marks, { #lines, col + #added + 1, col + #added + 1 + #removed, "Removed" })

    for _, hunk in ipairs(file.hunks) do
      local number = ("%6d"):format(hunk.lnum)
      local sign = hunk.sign or " "
      table.insert(lines, ("%s  %s %s"):format(number, sign, hunk.text or ""))
      targets[#lines] = { file = path, lnum = hunk.lnum }
      table.insert(marks, { #lines, 0, #number, "LineNr" })
      table.insert(marks, { #lines, #number + 2, #number + 3, sign == "-" and "Removed" or "Added" })
    end
  end

  return lines, marks, targets
end

--- @param entries table[] as returned by git.commits
--- @return string[] lines, table[] marks, table<integer, table> targets
function M.render_commits(entries)
  local lines, marks, targets = {}, {}, {}
  local width = 0

  for _, entry in ipairs(entries) do
    width = math.max(width, #entry.age)
  end

  for _, entry in ipairs(entries) do
    local age = ("%-" .. width .. "s"):format(entry.age)
    table.insert(lines, ("%s  %s  %s"):format(entry.rev, age, entry.subject))
    targets[#lines] = entry

    local age_at = #entry.rev + 2
    table.insert(marks, { #lines, 0, #entry.rev, "Added" })
    table.insert(marks, { #lines, age_at, age_at + #age, "Comment" })
  end

  return lines, marks, targets
end

return M
