local u = require("gitabra.util")
local chronos = require("chronos")
local job = require("gitabra.job")
local outliner = require("gitabra.outliner")
local api = vim.api
local patch_parser = require("gitabra.patch_parser")

local function git_get_branch()
  return u.system_async('git branch --show-current', {splitlines=true})
end

local function git_branch_commit_msg()
  return u.system_async({"git", "show", "--no-patch", "--format='%h %s'"}, {splitlines=true})
end

local function git_status()
  return u.system_async("git status --porcelain", {splitlines=true})
end

local function git_diff_unstaged()
  return u.system_async("git diff", {merge_output=true})
end

local function git_diff_staged()
  return u.system_async("git diff --cached", {merge_output=true})
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

local function status_info()
  local funcname = debug.getinfo(1, "n").name
  print(">>", funcname)

  local start = chronos.nanotime()
  local branch_j = git_get_branch()
  local branch_msg_j = git_branch_commit_msg()
  local status_j = git_status()
  local jobs = {branch_j, branch_msg_j, status_j}

  local wait_result = job.wait_all(1000, jobs)
  if not wait_result then
    error(string.format("%s: unable to complete git commands withint alotted time", funcname))
  end

  local stop = chronos.nanotime()
  print(string.format("git commands completed [%f]", stop-start))

  --------------------------------------------------------------------
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
  print(string.format("Info reorg completed [%f]", stop-start))

  local commit_msg = branch_msg_j.output[1]
  commit_msg = commit_msg and commit_msg:sub(2, -2) or "No commits yet"

  print("<<", funcname)

  return {
    header = string.format("[%s] %s", branch_j.output[1], commit_msg),
    files = files,
    untracked = untracked,
    staged = staged,
    unstaged = unstaged,
  }
end

local function hunk_infos()
  local funcname = debug.getinfo(1, "n").name
  print(">>", funcname)

  local start = chronos.nanotime()
  local unstaged_j = git_diff_unstaged()
  local staged_j = git_diff_staged()

  local jobs = {unstaged_j, staged_j}
  local wait_result = job.wait_all(1000, jobs)
  if not wait_result then
    error(string.format("%s: unable to complete git commands withint alotted time", funcname))
  end
  local stop = chronos.nanotime()
  print(string.format("git commands completed [%f]", stop-start))

  start = chronos.nanotime()
  local info = {
    unstaged = {
      patch_info = patch_parser.patch_info(unstaged_j.output[1]),
      patch_text = unstaged_j.output[1],
    },
    staged = {
      patch_info = patch_parser.patch_info(staged_j.output[1]),
      patch_text = staged_j.output[1],
    }
  }
  stop = chronos.nanotime()
  print(string.format("Patch parsing completed [%f]", stop-start))

  print("<<", funcname)
  return info
end

local function setup_window()
  api.nvim_command("split")
  local win = api.nvim_get_current_win()
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  return win
end

local function setup_keybinds(bufnr)
  local function set_keymap(...) vim.api.nvim_buf_set_keymap(bufnr, ...) end
  local opts = { noremap=true, silent=true }
  set_keymap('n', '<tab>', '<cmd>lua require("gitabra.git_status").toggle_fold_at_current_line()<cr>', opts)
end

local function setup_buffer()
  local buf = vim.api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(buf, 'GitabraStatus')
  vim.bo[buf].swapfile = false
  vim.bo[buf].buftype = 'nofile'
  -- vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'GitabraStatus'
  setup_keybinds(buf)
  return buf
end

local function setup_window_and_buffer()
  local buf = setup_buffer()
  local win = setup_window()
  api.nvim_set_current_buf(buf)
  return {
    winnr = win,
    bufnr = buf
  }
end

local current_status_screen

local function get_sole_status_screen()
  local sc = current_status_screen or {}

  -- Create a new window if the old one is invalid
  if not (sc.bufnr and api.nvim_buf_is_valid(sc.bufnr)) then
    sc.bufnr = setup_buffer()
  end

  -- Create a new buffer if the old one is invalid
  if not (sc.winnr and api.nvim_win_is_valid(sc.winnr)) then
    sc.winnr = setup_window()
  end

  api.nvim_set_current_win(sc.winnr)
  api.nvim_set_current_buf(sc.bufnr)
  current_status_screen = sc

  return current_status_screen
end

local function toggle_fold_at_current_line()
  local lineno = vim.fn.line(".") - 1
  local outline = get_sole_status_screen().outline
  if outline then
    local z = outline:node_zipper_at_lineno(lineno)
    if z then
      -- print("picked node:", vim.inspect(z:node()))
      local node

      -- Which node do we actually want to collapse?
      -- If the user is targetting a leaf node, like the
      -- contents of a hunk, that node itself cannot be
      -- collapsed. Instead, we're going to collapse it's
      -- parent/header.
      if not z:has_children() then
        -- print("is leaf")
        node = z:parent_node()
      else
        -- print("has children")
        node = z:node()
      end
      node.collapsed = not node.collapsed

      -- print("node altered:", vim.inspect(node))

      -- Rebuild the buffer from scratch
      outline:refresh()

      -- Move the cursor to whatever we've just collapsed
      -- All visible node's lineno should have been updated,
      -- so we can just use the contents of that field directly
      api.nvim_command(tostring(node.lineno+1))
    end
  end
end

local function populate_hunks(outline, parent_node, patch_info, filepath)
  local diff = patch_parser.find_file(patch_info.patch_info, filepath)
  -- print("looking for path:", vim.inspect(filepath))
  -- print("in:", vim.inspect(patch_info))
  -- print("found diff:", vim.inspect(diff))
  if diff then
    for _, hunk in ipairs(diff.hunks) do
      -- Add hunk header as its own node
      -- These look something like "@@ -16,10 +17,14 @@"
      local heading = outline:add_node(parent_node, {
          text = hunk.header_text,
        })

      -- Add the content of the hunk
      outline:add_node(heading, {
          text = string.sub(patch_info.patch_text, hunk.content_start, hunk.content_end)
        })
    end
  end
end

local function gitabra_status()
  local funcname = debug.getinfo(1, "n").name
  print(">>>", funcname)
  local fn_start = chronos.nanotime()

  local st_info = status_info()
  local hk_info = hunk_infos()

  local sc = get_sole_status_screen()

  --------------------------------------------------------------------
  print("Creating outline")
  local start = chronos.nanotime()
  local outline = outliner.new({buffer = sc.bufnr})

  -- We're going to add a bunch nodes/content to the buffer.
  -- For each node, we're going to add some text and an extmark on it.
  -- The extmark will be used for us to:
  -- 1. Figure out where to insert new nodes and text
  -- 2. Figure out the fold level of each line
  --
  -- We're disabling the folding here because of #2. If we don't
  -- disable folding here, nvim is going to immidately call `get_fold_level`
  -- as new lines are inserted. This will be before the extmark is setup,
  -- which means `get_fold_level` will not work properly.
  --
  -- This means that each time we're adding new content to the outline,
  -- we should disable the folding and re-enable it after all the
  -- inserts are done.

  -- print( vim.inspect(info))
  if st_info.header then
    outline:add_node(nil, {text = string.format("Head:    %s", st_info.header)})
  end

  if #st_info.untracked ~= 0 then
    local section = outline:add_node(nil, {
        text = "Untracked",
        id = "untracked",
    })
    for _, file in pairs(st_info.untracked) do
      outline:add_node(section, {text = file.name})
    end
  end

  print("Adding Unstaged entries")
  if #st_info.unstaged ~= 0 then
    -- print( "adding unstaged files:", #st_info.unstaged )
    local section = outline:add_node(nil, {
        text = "Unstaged",
        id = "unstaged",
        padlines_before = 1,
    })
    for _, file in pairs(st_info.unstaged) do
      local filename_node = outline:add_node(section, {text = file.name})
      populate_hunks(outline, filename_node, hk_info.unstaged, file.name)
    end
  end

  print("Adding Staged entries")
  if #st_info.staged ~= 0 then
    local section = outline:add_node(nil, {
        text = "Staged",
        id = "staged",
        padlines_before = 1,
    })
    for _, file in pairs(st_info.staged) do
      local filename_node = outline:add_node(section, {text = file.name})
      populate_hunks(outline, filename_node, hk_info.staged, file.name)
    end
  end

  local stop = chronos.nanotime()
  print(string.format("Outline completed: [%f]", stop-start))

  -- Place the new outline into the global sc before any nodes & content are added.
  -- `get_fold_level` will be called by nvim as nodes are added to the outline.
  -- The global sc is the only way that function can find the currently active outline.
  sc.outline = outline
  --------------------------------------------------------------------

  start = chronos.nanotime()
  outline:refresh()
  stop = chronos.nanotime()
  print(string.format("Outline refresh completed: [%f]", stop-start))

  local fn_stop = chronos.nanotime()
  print(string.format("<<< %s [%f]", funcname, fn_stop-fn_start))
end

return {
  status_info = status_info,
  hunk_infos = hunk_infos,
  gitabra_status = gitabra_status,
  get_fold_level = get_fold_level,
  get_fold_text = get_fold_text,
  setup_window_and_buffer = setup_window_and_buffer,
  get_sole_status_screen = get_sole_status_screen,
  toggle_fold_at_current_line = toggle_fold_at_current_line,
}
