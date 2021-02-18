local u = require("gitabra.util")
local chronos = require("chronos")
local job = require("gitabra.job")

local function git_get_branch()
  return u.system_async('git branch --show-current')
end

local function git_branch_commit_msg()
  return u.system_async({"git", "show", "--no-patch", "--format='%h %s'"})
end

local function git_status()
  return u.system_async("git status --porcelain")
end

local function status_letter_name(letter)
  if "M" == letter then return "modified"
  elseif "A" == letter then return "added"
  elseif "D" == letter then return "deleted"
  elseif "R" == letter then return "renamed"
  elseif "C" == letter then return "copied"
  elseif "U" == letter then return "umerged"
  elseif "?" == letter then return "untracked"
  else return ""
  end
end

local function gitabra_status()
  print("ENTERING gitabra_status")

  -- local buf = vim.api.nvim_create_buf(true, false)
  -- vim.api.nvim_set_current_buf(buf)

  local start = chronos.nanotime()
  local branch_j = git_get_branch()
  local branch_msg_j = git_branch_commit_msg()
  local status_j = git_status()
  local jobs = {branch_j, branch_msg_j, status_j}

  job.wait_all(5, jobs)

  local stop = chronos.nanotime()
  print("git commands completed")
  print("Elapsed:", stop-start)

  start = chronos.nanotime()

  local files = {}
  local untracked = {}
  local staged = {}
  local unstaged = {}

  for _, line in ipairs(status_j.output) do
    local fstat = line:sub(1, 2)
    local fname = line:sub(4)
    local entry = {
      index = status_letter_name(fstat:sub(1, 1)),
      working = status_letter_name(fstat:sub(2, 2)),
      name = fname,
    }

    if entry.working == "untracked" then
      table.insert(untracked, entry)
    end

    if entry.index ~= "" and entry.index ~= "untracked" then
      table.insert(staged, entry)
    end

    if entry.working ~= "" and entry.working ~= "untracked" then
      table.insert(unstaged, entry)
    end

    table.insert(files, entry)
  end

  stop = chronos.nanotime()
  print("Info reorg completed")
  print("Elapsed:", stop-start)

  print("EXITING gitabra_status")
  return {
    head = string.format("[%s] %s", branch_j.output[1], branch_msg_j.output[1]:sub(2, -2)),
    files = files,
    untracked = untracked,
    staged = staged,
    unstaged = unstaged,
  }
end

return {
  gitabra_status = gitabra_status,
}

--------------------------
-- Old Snippet
--
-- Setup a job to stream the contents of git-status to a new buffer
-- local buf = vim.api.nvim_create_buf(true, false)
-- local j = job:new({
-- 		cmd = "git status",
--   	on_stdout = function(self, err, data)
--     	if err then
--       	print("ERROR: "..err)
--     	end
--     	if data then
--       	for s in lines(data) do
--         	vim.api.nvim_buf_set_lines(buf, -1, -1, false, {s})
--       	end
--     	end
--   	end,
-- 	})
-- j:start()
