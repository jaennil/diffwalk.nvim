local config = require("diffwalk.config")

local M = {}

-- the empty tree, so the first commit in a repo diffs against something
M.EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

local state = {
  base = nil,
  branch = nil,
  root = nil,
  active = nil,
}

--- @param args string[]
--- @param silent? boolean
--- @return string? output trimmed stdout, nil when git failed
function M.run(args, silent)
  local result = vim.system(args, { text = true }):wait()

  if result.code ~= 0 then
    if not silent then
      vim.notify(vim.trim(result.stderr), vim.log.levels.ERROR)
    end
    return nil
  end

  return vim.trim(result.stdout)
end

--- repo root, so diff paths resolve no matter the window's cwd
--- @return string?
function M.root()
  state.root = state.root or M.run({ "git", "rev-parse", "--show-toplevel" })
  return state.root
end

--- @return string? name of the remote's default branch
function M.default_branch()
  local opts = config.options
  local head = M.run({ "git", "symbolic-ref", "--quiet", "refs/remotes/" .. opts.remote .. "/HEAD" }, true)
  local branch = head and head:match("[^/]+$")

  if branch then
    return branch
  end

  for _, candidate in ipairs(opts.branches) do
    if M.run({ "git", "rev-parse", "--verify", "--quiet", opts.remote .. "/" .. candidate }, true) then
      return candidate
    end
  end
end

--- merge base with the default branch, so commits landed in it after this
--- branch was cut stay out of the diff
--- @param refresh? boolean re-fetch instead of reusing the cached base
--- @return string? base, string? branch
function M.base(refresh)
  if state.base and not refresh then
    return state.base, state.branch
  end

  local opts = config.options
  local branch = M.default_branch()
  if not branch then
    vim.notify("diffwalk: can't detect the default branch", vim.log.levels.ERROR)
    return nil
  end

  if opts.fetch and not M.run({ "git", "fetch", opts.remote, branch }) then
    return nil
  end

  local base = M.run({ "git", "merge-base", opts.remote .. "/" .. branch, "HEAD" })
  if not base then
    return nil
  end

  state.base, state.branch = base, branch

  return base, branch
end

--- @param rev string
--- @return string parent revision, or the empty tree for a root commit
function M.parent(rev)
  return M.run({ "git", "rev-parse", "--verify", "--quiet", rev .. "^" }, true) or M.EMPTY_TREE
end

--- @param limit integer
--- @return table[]? entries
function M.commits(limit)
  local log = M.run({ "git", "log", "--no-color", "-n", tostring(limit), "--pretty=format:%h\30%ar\30%an\30%s" })
  if not log then
    return nil
  end

  local entries = {}
  for line in vim.gsplit(log, "\n", { plain = true, trimempty = true }) do
    local parts = vim.split(line, "\30", { plain = true })
    table.insert(entries, { rev = parts[1], age = parts[2], author = parts[3], subject = parts[4] })
  end

  return entries
end

--- path of a file relative to the repo root, as git names it
--- @param file string
--- @return string?
function M.relpath(file)
  local root = M.root()
  if not root then
    return nil
  end

  local abs = vim.fn.fnamemodify(file, ":p")
  if abs:sub(1, #root + 1) == root .. "/" then
    return abs:sub(#root + 2)
  end
end

--- contents of a file at a revision
--- @param rev string
--- @param path string
--- @return string[]? lines, nil when the file does not exist there
function M.show(rev, path)
  local out = M.run({ "git", "show", rev .. ":" .. path }, true)
  if not out then
    return nil
  end

  return vim.split(out, "\n", { plain = true })
end

--- @param rev string
--- @param path string
--- @return boolean whether the file exists at that revision
function M.exists(rev, path)
  return M.run({ "git", "cat-file", "-e", rev .. ":" .. path }, true) ~= nil
end

--- revision the file buffers are currently diffed against; the branch review
--- and a commit review set different ones
--- @param base? string
--- @return string?
function M.active(base)
  if base then
    state.active = base
  end
  return state.active
end

function M.forget()
  state.base, state.branch, state.active = nil, nil, nil
end

return M
