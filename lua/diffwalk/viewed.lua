--- Which hunks have already been looked at, per diff base. Kept in memory for
--- the session: a review is something you finish, and the keys stop matching
--- as soon as the files move under them anyway.
local M = {}

local seen = {}

--- @param base string
--- @param path string relative to the repo root
--- @param lnum integer
--- @return string
function M.key(base, path, lnum)
  return ("%s\0%s:%d"):format(base, path, lnum)
end

--- @param key string
--- @return boolean
function M.has(key)
  return seen[key] == true
end

--- @param key string
--- @param value boolean
function M.set(key, value)
  seen[key] = value or nil
end

--- @param key string
--- @return boolean now marked
function M.toggle(key)
  M.set(key, not M.has(key))
  return M.has(key)
end

--- @param keys string[]
--- @return boolean now marked, the whole group flipped together
function M.toggle_all(keys)
  local all = true
  for _, key in ipairs(keys) do
    if not M.has(key) then
      all = false
      break
    end
  end

  for _, key in ipairs(keys) do
    M.set(key, not all)
  end

  return not all
end

function M.clear()
  seen = {}
end

return M
