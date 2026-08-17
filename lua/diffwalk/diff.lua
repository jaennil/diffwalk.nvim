local git = require("diffwalk.git")
local viewed = require("diffwalk.viewed")

local M = {}

local MARK = "\u{2713} "

--- files with their hunks, each hunk pointing at its first changed line
--- @param diff string output of git diff
--- @return table[] files
function M.parse(diff)
  local files, file, hunk, lnum, run = {}, nil, nil, nil, nil

  for _, line in ipairs(vim.split(diff, "\n", { plain = true })) do
    local old = line:match("^%-%-%- a/(.*)$")
    local new = line:match("^%+%+%+ b/(.*)$")
    local start = line:match("^@@ %-[%d,]+ %+(%d+)")
    local kind = line:sub(1, 1)

    if line:match("^diff %-%-git ") then
      file, hunk, run = nil, nil, nil
    elseif old then
      file = { path = old, added = 0, removed = 0, hunks = {} }
    elseif new or line == "+++ /dev/null" then
      file = file or { added = 0, removed = 0, hunks = {} }
      file.path = new or file.path -- a deleted file keeps its old path
      table.insert(files, file)
    elseif start and file then
      lnum = tonumber(start)
      -- lines carries the added lines only, so marking a viewed hunk in the
      -- file never dims the context around it
      -- deletions are kept as runs, each anchored where it sits in the new
      -- file: a hunk interleaves - and +, and collapsing them into one block
      -- would show every removal before every addition
      hunk = { lnum = lnum, first = lnum, lines = {}, deletions = {}, added = 0, removed = 0 }
      run = nil
      table.insert(file.hunks, hunk)
    elseif hunk and kind == "+" then
      run = nil
      file.added, hunk.added = file.added + 1, hunk.added + 1
      table.insert(hunk.lines, lnum)
      if not hunk.text then
        hunk.lnum, hunk.sign, hunk.text = lnum, "+", vim.trim(line:sub(2))
      end
      lnum = lnum + 1
    elseif hunk and kind == "-" then
      file.removed, hunk.removed = file.removed + 1, hunk.removed + 1
      hunk.first = math.min(hunk.first, lnum)
      hunk.deleted_at = hunk.deleted_at or lnum -- where the first removal was

      if not run then
        run = { at = lnum, lines = {} }
        table.insert(hunk.deletions, run)
      end

      table.insert(run.lines, line:sub(2))
      if not hunk.text then
        hunk.lnum, hunk.sign, hunk.text = lnum, "-", vim.trim(line:sub(2))
      end
    elseif hunk and kind == " " then
      run = nil
      lnum = lnum + 1
    end
  end

  return files
end

--- one line per file, one per hunk; targets[line] is where <CR> jumps.
--- Hunks already looked at carry a check mark and are dimmed, and can be left
--- out entirely.
--- @param files table[]
--- @param base string revision the diff is against, part of the viewed key
--- @param hide_viewed? boolean drop hunks and files that are fully viewed
--- @return string[] lines, table[] marks, table<integer, table> targets
function M.render(files, base, hide_viewed)
  local lines, marks, targets = {}, {}, {}
  local root = git.root()

  for _, file in ipairs(files) do
    local path = root .. "/" .. file.path
    local keys, pending = {}, {}

    for _, hunk in ipairs(file.hunks) do
      local key = viewed.key(base, file.path, hunk.lnum)
      table.insert(keys, key)
      if not viewed.has(key) then
        table.insert(pending, { hunk = hunk, key = key })
      end
    end

    local seen_count = #keys - #pending
    local done = #pending == 0 and #keys > 0

    if not (hide_viewed and done) then
      local added = ("+%d"):format(file.added)
      local removed = ("-%d"):format(file.removed)
      local mark = done and MARK or "  "
      local progress = ("%d/%d"):format(seen_count, #keys)

      table.insert(lines, ("%s%s  %s %s  %s"):format(mark, file.path, added, removed, progress))
      targets[#lines] = {
        file = path,
        lnum = file.hunks[1] and file.hunks[1].lnum or 1,
        header = true,
        keys = keys,
      }

      if done then
        table.insert(marks, { #lines, 0, -1, "Comment" })
      else
        local at = #mark + #file.path + 2
        table.insert(marks, { #lines, #mark, #mark + #file.path, "Directory" })
        table.insert(marks, { #lines, at, at + #added, "Added" })
        table.insert(marks, { #lines, at + #added + 1, at + #added + 1 + #removed, "Removed" })
        table.insert(marks, { #lines, at + #added + #removed + 2, -1, "Comment" })
      end

      local shown = hide_viewed and pending or nil
      for index, hunk in ipairs(file.hunks) do
        local key = keys[index]
        local skip = shown and viewed.has(key)

        if not skip then
          local seen = viewed.has(key)
          local mark_hunk = seen and MARK or "  "
          local number = ("%6d"):format(hunk.lnum)
          local sign = hunk.sign or " "

          table.insert(lines, ("%s%s  %s %s"):format(mark_hunk, number, sign, hunk.text or ""))
          targets[#lines] = { file = path, lnum = hunk.lnum, keys = { key } }

          if seen then
            table.insert(marks, { #lines, 0, -1, "Comment" })
          else
            table.insert(marks, { #lines, #mark_hunk, #mark_hunk + #number, "LineNr" })
            local sign_at = #mark_hunk + #number + 2
            table.insert(marks, { #lines, sign_at, sign_at + 1, sign == "-" and "Removed" or "Added" })
          end
        end
      end
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
