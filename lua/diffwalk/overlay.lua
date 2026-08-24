--- What the file buffers show about viewed hunks: gitsigns paints every hunk
--- the same, so a hunk already looked at is dimmed back down here and given a
--- check mark of its own.
local config = require("diffwalk.config")
local diff = require("diffwalk.diff")
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
--- Virtual lines are never wrapped by Neovim: a removed line longer than the
--- window is simply cut off, while the real code beside it wraps. Split by
--- display width so the whole of it stays readable.
--- @param text string
--- @param width integer
--- @return string[]
local function wrap_line(text, width)
  if width <= 0 or vim.fn.strdisplaywidth(text) <= width then
    return { text }
  end

  local pieces, current, taken = {}, {}, 0

  for _, char in ipairs(vim.fn.split(text, "\\zs")) do
    local size = vim.fn.strdisplaywidth(char)

    if taken + size > width then
      table.insert(pieces, table.concat(current))
      current, taken = {}, 0
    end

    table.insert(current, char)
    taken = taken + size
  end

  if #current > 0 then
    table.insert(pieces, table.concat(current))
  end

  return pieces
end

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

--- Width of the gutter, worked out rather than read from getwininfo: with
--- signcolumn=auto the column is still empty when this runs, and it is the
--- marks placed below that widen it. Reading it now would be two columns short
--- and the deleted lines would sit out of line with the code.
--- @param win integer
--- @param lines integer line count of the buffer
--- @return integer
local function gutter_width(win, lines)
  local wo = vim.wo[win]
  local width = 0

  if wo.number or wo.relativenumber then
    width = width + math.max(wo.numberwidth, #tostring(lines) + 1)
  end

  if wo.signcolumn ~= "no" and not wo.signcolumn:find("number") then
    width = width + 2
  end

  width = width + (tonumber(wo.foldcolumn) or 0)

  return width
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
  if not path then
    return
  end

  -- diffed against the base on every refresh, so edits to the buffer are
  -- reflected; the snapshot from when the review started is the fallback for
  -- a file the base does not have at all
  local snapshot = current.files[path]
  local hunks = diff.buffer(bufnr, current.base, path)

  if not hunks then
    if not snapshot then
      return
    end
    hunks = snapshot.hunks
  end

  local file = { hunks = hunks, absent = snapshot and snapshot.absent or false }

  local last = vim.api.nvim_buf_line_count(bufnr)

  local tabstop = vim.bo[bufnr].tabstop
  local width, textoff = 0, 0
  local wrap = false

  -- deleted lines are padded to the window so they read as a band, and their
  -- own gutter is drawn by hand: virtual lines have no sign column
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    local gutter = gutter_width(win, last)
    width = math.max(width, vim.api.nvim_win_get_width(win) - gutter)
    textoff = math.max(textoff, gutter)
    wrap = wrap or vim.wo[win].wrap
  end

  local edges = config.options.edges

  --- the bracket for one line of a hunk, given where it falls in it
  local function bracket(index, total)
    if not edges then
      return "\u{2502}"
    elseif total == 1 then
      return "\u{2500}"
    elseif index == 1 then
      return "\u{250c}"
    elseif index == total then
      return "\u{2514}"
    end

    return "\u{2502}"
  end

  for _, hunk in ipairs(file.hunks) do
    local seen = viewed.has(viewed.key(current.base, path, diff.id(hunk)))
    local sign_hl = seen and "DiffwalkViewedSign" or "DiffwalkAddedSign"

    local runs = {}
    if show_deleted then
      for _, run in ipairs(hunk.deletions) do
        runs[run.at] = run
      end
    end

    local added = {}
    for _, line in ipairs(hunk.lines) do
      added[line] = true
    end

    -- every line of this buffer the hunk touches: its changed lines, plus
    -- where each run of deletions belongs. A hunk that only deletes has no
    -- changed line of its own, and computing a span from those alone left it
    -- empty, which is why its removed lines were never drawn.
    local touched, sorted = {}, {}
    local function touch(line)
      line = math.min(math.max(line, 1), math.max(last, 1))
      if not touched[line] then
        touched[line], sorted[#sorted + 1] = true, line
      end
    end

    for _, line in ipairs(hunk.lines) do
      touch(line)
    end
    for at in pairs(runs) do
      if at <= last then
        touch(at)
      end
    end

    table.sort(sorted)

    -- the bracket runs over the whole span, context lines in between
    -- included, so it reads as one shape instead of breaking up
    local span = {}
    if #sorted > 0 then
      for line = sorted[1], sorted[#sorted] do
        span[#span + 1] = line
      end
    end

    local virt_count = 0
    for _, run in ipairs(hunk.deletions) do
      virt_count = virt_count + #run.lines
    end

    local total = virt_count + #span
    local index = 0

    for _, position in ipairs(span) do
      local run = runs[position]

      -- what the change removed, above the line that took its place
      if run then
        local hl = seen and "DiffwalkViewed" or "DiffwalkRemoved"
        local virt = {}

        for _, text in ipairs(run.lines) do
          index = index + 1

          local gutter = (seen and index == 1) and "\u{2713} " or (bracket(index, total) .. " ")
          gutter = gutter .. string.rep(" ", math.max(textoff - vim.fn.strdisplaywidth(gutter), 0))

          local expanded = expand_tabs(text, tabstop)
          local pieces = wrap and wrap_line(expanded, width) or { expanded }

          for piece_index, piece in ipairs(pieces) do
            piece = piece .. string.rep(" ", math.max(width - vim.fn.strdisplaywidth(piece), 0))

            -- a wrapped remainder continues the line, so its gutter is blank
            local prefix = piece_index == 1 and gutter or string.rep(" ", textoff)
            table.insert(virt, { { prefix, sign_hl }, { piece, hl } })
          end
        end

        vim.api.nvim_buf_set_extmark(bufnr, ns, position - 1, 0, {
          virt_lines = virt,
          virt_lines_above = true,
          virt_lines_leftcol = true,
          priority = 1000,
        })
      end

      index = index + 1

      vim.api.nvim_buf_set_extmark(bufnr, ns, position - 1, 0, {
        -- only the changed lines are painted; the context between them keeps
        -- its own background and just carries the bracket
        line_hl_group = added[position] and (seen and "DiffwalkViewed" or "DiffwalkAdded") or nil,
        sign_text = (seen and index == 1) and "\u{2713} " or (bracket(index, total) .. " "),
        sign_hl_group = sign_hl,
        priority = 1000,
      })
    end

    -- deletions past the end of the buffer have no line to hang above
    for at, run in pairs(runs) do
      if at > last then
        local hl = seen and "DiffwalkViewed" or "DiffwalkRemoved"
        local virt = {}

        for _, text in ipairs(run.lines) do
          local expanded = expand_tabs(text, tabstop)
          local gutter = bracket(total, total) .. " "
          gutter = gutter .. string.rep(" ", math.max(textoff - vim.fn.strdisplaywidth(gutter), 0))
          expanded = expanded .. string.rep(" ", math.max(width - vim.fn.strdisplaywidth(expanded), 0))
          table.insert(virt, { { gutter, sign_hl }, { expanded, hl } })
        end

        vim.api.nvim_buf_set_extmark(bufnr, ns, math.max(last - 1, 0), 0, {
          virt_lines = virt,
          virt_lines_leftcol = true,
          priority = 1000,
        })
      end
    end

    -- a hunk that only deletes and whose runs fell outside the buffer still
    -- deserves a mark where it happened
    if total == 0 then
      local at = math.min(math.max(hunk.deleted_at or hunk.first, 1), last)
      vim.api.nvim_buf_set_extmark(bufnr, ns, at - 1, 0, {
        sign_text = seen and "\u{2713} " or "\u{2500} ",
        sign_hl_group = seen and "DiffwalkViewedSign" or "DiffwalkRemovedSign",
        priority = 1000,
      })
    end
  end
end

local pending = {}

--- redraw after the dust settles, rather than on every keystroke
--- @param bufnr integer
function M.schedule(bufnr)
  if pending[bufnr] then
    return
  end

  pending[bufnr] = true
  vim.defer_fn(function()
    pending[bufnr] = nil
    M.refresh(bufnr)

    local panel = require("diffwalk.panel")
    if panel.active then
      panel.active(true)
    end
  end, 250)
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
    desc = "diffwalk: paint a file opened after the review started",
    callback = function(args)
      M.refresh(args.buf)
    end,
  })

  -- the deleted lines are wrapped and padded to the window, so a resize has
  -- to rebuild them
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = group,
    desc = "diffwalk: rewrap the deleted lines for the new width",
    callback = function()
      M.refresh_all()
    end,
  })

  -- edits move the hunks under the marks: follow gitsigns, which has already
  -- rediffed by the time this settles
  vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufWritePost" }, {
    group = group,
    desc = "diffwalk: follow the buffer as it is edited",
    callback = function(args)
      M.schedule(args.buf)
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
