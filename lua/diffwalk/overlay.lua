--- What the file buffers show about viewed hunks: gitsigns paints every hunk
--- the same, so a hunk already looked at is dimmed back down here and given a
--- check mark of its own.
local git = require("diffwalk.git")
local viewed = require("diffwalk.viewed")

local M = {}

local ns = vim.api.nvim_create_namespace("diffwalk-viewed")
local group = vim.api.nvim_create_augroup("diffwalk-overlay", { clear = true })

--- @type {base: string?, files: table<string, table[]>}
local current = { base = nil, files = {} }

--- @param bufnr integer
--- @return string? path relative to the repo root
local function relpath(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return nil
  end

  return git.relpath(name)
end

--- @param bufnr integer
function M.refresh(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.bo[bufnr].buflisted then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local path = current.base and relpath(bufnr)
  local hunks = path and current.files[path]
  if not hunks then
    return
  end

  local last = vim.api.nvim_buf_line_count(bufnr)

  for _, hunk in ipairs(hunks) do
    if viewed.has(viewed.key(current.base, path, hunk.lnum)) then
      for _, line in ipairs(hunk.lines) do
        if line <= last then
          vim.api.nvim_buf_set_extmark(bufnr, ns, line - 1, 0, {
            line_hl_group = "DiffwalkViewed",
            priority = 1000,
          })
        end
      end

      -- a hunk that only deletes covers no line here, so the check mark goes
      -- where the deletion happened
      local sign_at = math.min(math.max(hunk.lines[1] or hunk.first, 1), last)
      vim.api.nvim_buf_set_extmark(bufnr, ns, sign_at - 1, 0, {
        sign_text = "✓ ",
        sign_hl_group = "DiffwalkViewedSign",
        priority = 1000,
      })
    end
  end
end

function M.refresh_all()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    M.refresh(bufnr)
  end
end

--- @param base string
--- @param files table[] as returned by diff.parse
function M.set(base, files)
  current = { base = base, files = {} }

  for _, file in ipairs(files) do
    current.files[file.path] = file.hunks
  end

  vim.api.nvim_clear_autocmds({ group = group })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufReadPost" }, {
    group = group,
    desc = "diffwalk: mark viewed hunks in a file opened later",
    callback = function(args)
      M.refresh(args.buf)
    end,
  })

  M.refresh_all()
end

function M.clear()
  current = { base = nil, files = {} }
  vim.api.nvim_clear_autocmds({ group = group })

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end
  end
end

return M
