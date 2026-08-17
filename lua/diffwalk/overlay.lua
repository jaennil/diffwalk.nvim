--- What the file buffers show about viewed hunks: gitsigns paints every hunk
--- the same, so a hunk already looked at is dimmed back down here and given a
--- check mark of its own.
local git = require("diffwalk.git")
local viewed = require("diffwalk.viewed")

local M = {}

local ns = vim.api.nvim_create_namespace("diffwalk-viewed")
local group = vim.api.nvim_create_augroup("diffwalk-overlay", { clear = true })

--- @type {base: string?, files: table<string, table>}
local current = { base = nil, files = {} }

local show_deleted = true

--- Virtual text does not expand tabs, so a tab-indented line would render
--- narrower than the code around it. Expanded here against the buffer's own
--- tabstop, which is what makes the two line up.
--- @param text string
--- @param tabstop integer
--- @return string
local function expand_tabs(text, tabstop)
  local out = {}
  local width = 0

  for char in text:gmatch(".") do
    if char == "\t" then
      local fill = tabstop - (width % tabstop)
      table.insert(out, string.rep(" ", fill))
      width = width + fill
    else
      table.insert(out, char)
      width = width + 1
    end
  end

  return table.concat(out)
end

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
  local file = path and current.files[path]
  if not file then
    return
  end

  local last = vim.api.nvim_buf_line_count(bufnr)

  local tabstop = vim.bo[bufnr].tabstop
  local width = 0

  -- pad the deleted lines out to the window, so they read as a band rather
  -- than as text floating on the normal background
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    width = math.max(width, vim.api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff)
  end

  for _, hunk in ipairs(file.hunks) do
    local seen = viewed.has(viewed.key(current.base, path, hunk.lnum))

    -- what the change removed, above the line that replaced it
    if show_deleted and #hunk.deleted > 0 then
      local hl = seen and "DiffwalkViewed" or "DiffwalkRemoved"
      local virt = {}

      for _, text in ipairs(hunk.deleted) do
        local expanded = expand_tabs(text, tabstop)
        expanded = expanded .. string.rep(" ", math.max(width - vim.fn.strdisplaywidth(expanded), 0))
        table.insert(virt, { { expanded, hl } })
      end

      local anchor = math.min(math.max(hunk.deleted_at or hunk.first, 1), last)
      vim.api.nvim_buf_set_extmark(bufnr, ns, anchor - 1, 0, {
        virt_lines = virt,
        virt_lines_above = true,
        priority = 1000,
      })
    end

    -- a file the base does not have gets no gitsigns highlights at all, so
    -- its added lines are painted here
    if file.absent and not seen then
      for _, line in ipairs(hunk.lines) do
        if line <= last then
          vim.api.nvim_buf_set_extmark(bufnr, ns, line - 1, 0, {
            line_hl_group = "DiffwalkAdded",
            sign_text = line == hunk.lines[1] and "\u{2503} " or nil,
            sign_hl_group = "DiffwalkAddedSign",
            priority = 1000,
          })
        end
      end
    end

    if seen then
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
    current.files[file.path] = {
      hunks = file.hunks,
      absent = not git.exists(base, file.path),
    }
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

--- @return boolean shown
function M.toggle_deleted()
  show_deleted = not show_deleted
  M.refresh_all()
  return show_deleted
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
