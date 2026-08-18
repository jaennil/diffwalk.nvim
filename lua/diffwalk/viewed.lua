--- Which hunks have already been looked at, keyed by the diff base, the file
--- and the hunk's own content. Written to disk per repository, so a review
--- survives closing Neovim.
local M = {}

local seen = {}
local root = nil

--- @param base string
--- @param path string relative to the repo root
--- @param id string hash of the hunk's patch text
--- @return string
function M.key(base, path, id)
  return ("%s\0%s\0%s"):format(base, path, id)
end

--- @return string? path of the state file for the current repository
local function store()
  if not root or not require("diffwalk.config").options.persist then
    return nil
  end

  local dir = vim.fs.joinpath(vim.fn.stdpath("state"), "diffwalk")
  vim.fn.mkdir(dir, "p")

  return vim.fs.joinpath(dir, vim.fn.sha256(root):sub(1, 16) .. ".json")
end

--- @param repo string repo root, which the state file is named after
function M.load(repo)
  if root == repo then
    return
  end

  root, seen = repo, {}

  local path = store()
  if not path or vim.fn.filereadable(path) == 0 then
    return
  end

  local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  if ok and type(decoded) == "table" then
    seen = decoded
  end
end

function M.save()
  local path = store()
  if not path then
    return
  end

  if not next(seen) then
    vim.fn.delete(path)
    return
  end

  vim.fn.writefile({ vim.json.encode(seen) }, path)
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
  M.save()
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
  M.save()
end

return M
