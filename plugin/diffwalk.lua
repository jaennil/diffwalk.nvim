if vim.g.loaded_diffwalk then
  return
end
vim.g.loaded_diffwalk = true

local function command(name, fn, opts)
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

command("DiffwalkBranch", function()
  require("diffwalk").branch()
end, { desc = "Walk the hunks of the current branch" })

command("DiffwalkFiles", function()
  require("diffwalk").files()
end, { desc = "Changed files of the current branch in the quickfix list" })

command("DiffwalkCommits", function(args)
  require("diffwalk").commits(tonumber(args.args))
end, { nargs = "?", desc = "Pick a commit and walk its diff" })

command("DiffwalkCommit", function(args)
  require("diffwalk").commit(args.args)
end, { nargs = 1, desc = "Walk the diff of a commit" })

command("DiffwalkOld", function()
  require("diffwalk").old()
end, { desc = "Open the base version of the file side by side" })

command("DiffwalkToggleDeleted", function()
  require("diffwalk").toggle_deleted()
end, { desc = "Show or hide removed lines in the file" })

command("DiffwalkReset", function()
  require("diffwalk").reset()
end, { desc = "Drop the diff base and its highlights" })
