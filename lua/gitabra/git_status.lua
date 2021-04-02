local u = require("gitabra.util")
local job = require("gitabra.job")
local outliner = require("gitabra.outliner")
local api = vim.api
local patch_parser = require("gitabra.patch_parser")
local md5 = require("gitabra.md5")

-- Node types
local type_section = "section"
local type_file = "file"
local type_hunk_header = "hunk header"
local type_hunk_content = "hunk content"
local type_stash_entry = "stash entry"
local type_recent_commit = "recent commit"

local function git_get_branch()
  return u.system_async('git branch --show-current', {split_lines=true})
end

local function git_branch_commit_msg()
  return u.system_async({"git", "show", "--no-patch", "--format='%h %s'"}, {split_lines=true})
end

local function git_status()
  return u.system_async("git status --porcelain", {split_lines=true})
end

local function git_diff_unstaged()
  return u.system_async("git diff", {merge_output=true})
end

local function git_diff_staged()
  return u.system_async("git diff --cached", {merge_output=true})
end

local function git_apply_patch(direction, patch_text)
  local cmd = {"git", "apply", "--cached", "--whitespace=nowarn"}
  if direction == "unstage" then
    table.insert(cmd, "--reverse")
  end
  table.insert(cmd, "-")

  local j = u.system_async(cmd)
  j.job:send(patch_text)
  return j
end

local function git_discard_hunk(include_staged, patch_text)
  local cmd = {"git", "apply", "--reverse", "--whitespace=nowarn"}
  if include_staged then
    table.insert(cmd, "--index")
  end
  table.insert(cmd, "-")

  local j = u.system_async(cmd)
  j.job:send(patch_text)
  return j
end

local function git_add(rel_filepath)
  return u.system_async({"git", "add", rel_filepath})
end

local function git_reset_file(rel_filepath)
  return u.system_async({"git", "reset", rel_filepath})
end

local function git_log_recents()
  return u.system_async("git log --oneline -n 10 --decorate=short", {split_lines=true})
end

local function git_stash_list()
  return u.system_async("git stash list", {split_lines=true})
end

local function parse_ref(ref_str)
  ref_str = u.trim(ref_str)
  local result =  {}
  local name = string.match(ref_str, "^HEAD %-> (.*)$")
  if name then
    result.name = name
    result.current_branch = true
    return result
  end

  local remote
  remote, name = string.match(ref_str, "^(.-)/(.*)$")
  if remote and name then
    result.name = name
    result.remote = remote
    return result
  end

  result.name = ref_str
  return result
end

local function parse_log_recent_entry(log_entry_str)
  -- A recent commit line will look like either:
  -- "abcdefg (ref1, ref2, ...) some commit message here"
  -- or
  -- "abcdefg some commit message here"
  local rev, refs, msg

  rev, refs, msg = string.match(log_entry_str, "^(%w+) %((.-)%) (.*)$")
  if not rev then
    rev, msg = string.match(log_entry_str, "^(%w+) (.*)$")
  end
  assert(rev and msg, "Unable to parse log lines")

  local item = {
      rev = rev,
      msg = msg
  }
  if refs then
      item.refs = u.map(u.string_split_by_pattern(refs, ","), parse_ref)
  end
  return item
end

local function format_ref(ref)
  local result = u.markup({ text = ref.name })
  if ref.current_branch then
    result.group = "GitabraCurrentBranch"
  elseif ref.remote then
    result.group = "GitabraRemoteRef"
    result.text = string.format("%s/%s", ref.remote, ref.name)
  else
    result.group = "GitabraBranch"
  end
  return result
end

local function format_log_recent_entry(log_entry)
    local entry = u.markup({{
        text = log_entry.rev,
        group = "GitabraRev",
    }})

    if log_entry.refs then
      u.table_concat(entry, u.map(log_entry.refs, format_ref))
    end

    table.insert(entry, log_entry.msg)
    return entry
end

local function parse_stash_entry(str)
  local rev, msg = string.match(str, "^(stash@{%d+}):(.*)$")
  return {
    stash_rev = rev,
    msg = u.trim(msg),
  }
end

local function format_stash_entry(entry)
  return u.markup({
    {
      group = "GitabraStashRev",
      text = entry.stash_rev,
    },
    entry.msg,
  })
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

local module_initialized = false
local function module_initialize()
  if module_initialized then
    return
  end

  vim.cmd("highlight link GitabraBranch Blue")
  vim.cmd("highlight link GitabraRemoteRef Green")
  vim.cmd("highlight link GitabraRev Blue")
  vim.cmd("highlight link GitabraStashRev Blue")

  local attrs = u.hl_group_attrs("Green")
  attrs.gui = "underline"
  vim.cmd(string.format("highlight GitabraCurrentBranch %s", u.hl_group_attrs_to_str(attrs)))

  attrs = u.hl_group_attrs("Yellow")
  attrs.gui = "bold"
  attrs.cterm  = "bold"
  vim.cmd(string.format("highlight GitabraStatusSection %s", u.hl_group_attrs_to_str(attrs)))

  attrs = u.hl_group_attrs("White")
  attrs.gui = "bold"
  attrs.cterm = "bold"
  vim.cmd(string.format("highlight GitabraStatusFile %s", u.hl_group_attrs_to_str(attrs)))

  -- Set the node content highlight
  -- Disable the highlight if we can't retrieve the guibg color
  attrs = u.hl_group_attrs("Normal")
  if not attrs.guibg then
    vim.cmd("highlight link GitabraNodeActiveHeader Normal")
  else
    -- Otherwise, make it slightly brighter than the normal background
    local h, s, l = u.Hex_to_HSL(attrs.guibg)
    vim.cmd(string.format("highlight GitabraNodeActiveHeader %s", u.hl_group_attrs_to_str({guibg = u.HSL_to_Hex(h, s+5.2, l+10.0)})))
  end
  vim.fn.sign_define("GitabraNodeActiveHeader", {linehl = "GitabraNodeActiveHeader"})

  module_initialized = true
end


local function status_info()
  local root_dir_j = u.git_root_dir_j()
  local branch_j = git_get_branch()
  local branch_msg_j = git_branch_commit_msg()
  local status_j = git_status()
  local recents_j = git_log_recents()
  local stash_list_j = git_stash_list()

  local jobs = {root_dir_j, branch_j, branch_msg_j, status_j, recents_j, stash_list_j}

  local wait_result = job.wait_all(jobs, 2000)
  if not wait_result then
    local funcname = debug.getinfo(1, "n").name
    error(string.format("%s: unable to complete git commands within the alotted time", funcname))
  end


  --------------------------------------------------------------------

  local files = {}
  local untracked = {}
  local staged = {}
  local unstaged = {}

  for _, line in ipairs(status_j.output) do
    local fstat = line:sub(1, 2)
    local fname = line:sub(4)
    fname = fname:match("\"(.-)\"") or fname

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

  local commit_msg = branch_msg_j.output[1]
  commit_msg = commit_msg and commit_msg:sub(2, -2) or "No commits yet"

  return {
    git_root = root_dir_j.output[1],
    branch = branch_j.output[1],
    last_commit_msg = commit_msg,
    files = files,
    untracked = untracked,
    staged = staged,
    unstaged = unstaged,
    recents = recents_j.output,
    stash_list = stash_list_j.output,
  }
end

local function patch_infos()
  local unstaged_j = git_diff_unstaged()
  local staged_j = git_diff_staged()

  local jobs = {unstaged_j, staged_j}
  local wait_result = job.wait_all(jobs, 2000)
  if not wait_result then
    local funcname = debug.getinfo(1, "n").name
    error(string.format("%s: unable to complete git commands within the alotted time", funcname))
  end

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

  return info
end

local function setup_window()
  vim.cmd(":topleft vsplit")
  local win = api.nvim_get_current_win()
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  return win
end

local function setup_keybinds(bufnr)
  local function set_keymap(...) vim.api.nvim_buf_set_keymap(bufnr, ...) end
  local opts = { noremap=true, silent=true }
  set_keymap('n', '<tab>', '<cmd>lua require("gitabra.git_status").toggle_fold_at_current_line()<cr>', opts)

  set_keymap('n', 's', '<cmd>lua require("gitabra.git_status").stage()<cr>', opts)
  set_keymap('v', 's', '<cmd>lua require("gitabra.git_status").stage()<cr>', opts)
  set_keymap('n', 'S', '<cmd>lua require("gitabra.git_status").stage_all()<cr>', opts)

  set_keymap('n', 'u', '<cmd>lua require("gitabra.git_status").unstage()<cr>', opts)
  set_keymap('v', 'u', '<cmd>lua require("gitabra.git_status").unstage()<cr>', opts)
  set_keymap('n', 'U', '<cmd>lua require("gitabra.git_status").unstage_all()<cr>', opts)

  set_keymap('n', '<enter>', '<cmd>lua require("gitabra.git_status").jump_to_location()<cr>', opts)
  set_keymap('n', 'x', '<cmd>lua require("gitabra.git_status").discard_hunk()<cr>', opts)
  set_keymap('v', 'x', '<cmd>lua require("gitabra.git_status").discard_hunk()<cr>', opts)
  set_keymap('n', 'q', '<cmd>close<cr>', opts)
  set_keymap('n', 'cc', '<cmd>lua require("gitabra.git_commit").gitabra_commit()<cr>', opts)
  set_keymap('n', 'ca', '<cmd>lua require("gitabra.git_commit").gitabra_commit("amend")<cr>', opts)
  set_keymap('n', 'j', '<cmd>lua require("gitabra.git_status").next_line()<cr>', opts)
  set_keymap('n', 'k', '<cmd>lua require("gitabra.git_status").prev_line()<cr>', opts)
end

local status_buf_name = "gitabra:////gitabra_status"

-- Looks through all available buffers and returns the gitabra status buffer if found
-- This helps us recover the bufnr if it becomes lost. This usually happens when the
-- module is reloaded and the `current_status_screen` gets lost.
local function find_existing_status_buffer()
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_get_name(bufnr) == status_buf_name then
      return bufnr
    end
  end
end

local function find_window_for_buffer(bufnr)
  for _, winnr in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(winnr) == bufnr then
      return winnr
    end
  end
end

local function setup_buffer()
  local buf = vim.api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(buf, status_buf_name)
  vim.bo[buf].swapfile = false
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'GitabraStatus'
  vim.bo[buf].syntax = 'diff'
  vim.bo[buf].modifiable = false
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

local function setup_status_screen(sc)
  -- Create a new window if the old one is invalid
  if not (sc.bufnr and api.nvim_buf_is_valid(sc.bufnr)) then
    local bufnr = find_existing_status_buffer()
    if bufnr then
      sc.bufnr = bufnr
    else
      sc.bufnr = setup_buffer()
    end
  end

  -- Create a new buffer if the old one is invalid
  if not (sc.winnr and api.nvim_win_is_valid(sc.winnr)) then
    local winnr = find_window_for_buffer(sc.bufnr)
    if winnr then
      sc.winnr = winnr
    else
      sc.winnr = setup_window()
    end
  end

  api.nvim_set_current_win(sc.winnr)
  api.nvim_set_current_buf(sc.bufnr)
  return sc
end

local function get_sole_status_screen()
  local sc = current_status_screen or {}
  current_status_screen = setup_status_screen(sc)
  return current_status_screen
end

local function toggle_fold_at_current_line()
  local lineno = vim.fn.line(".") - 1
  local outline = get_sole_status_screen().outline
  if not outline then
    return
  end

  local z = outline:node_zipper_at_lineno(lineno)
  if not z then
    return
  end

  local node

  -- Which node do we actually want to collapse?
  -- If the user is targetting a leaf node, like the
  -- contents of a hunk, that node itself cannot be
  -- collapsed. Instead, we're going to collapse it's
  -- parent/header.
  if not z:has_children() then
    node = z:parent_node()
    if node == outline.root then
      return
    end
  else
    node = z:node()
  end
  node.collapsed = not node.collapsed

  -- Refresh the buffer
  outline:refresh()

  -- Move the cursor to whatever we've just collapsed
  -- All visible node's lineno should have been updated,
  -- so we can just use the contents of that field directly
  vim.cmd(tostring(node.lineno+1))
end


-- Return the type of hunk line we are looking at.
-- Returns either "+", "-", or "common"
local function hunk_line_type(line)
  local char = line:sub(1,1)
  if char == "+" then
    return "+"
  elseif char == "-" then
    return "-"
  else
    return "common"
  end
end

-- Given some hunk lines, count (up to line_limit) the number of
-- lines relavant to a specific type
local function hunk_lines_count_type(lines, line_type, line_limit)
  local count = 0
  if not line_limit then
    line_limit = #lines
  else
    line_limit = u.math_clamp(line_limit, 1, #lines)
  end

  for i=1, line_limit do
    local line = lines[i]
    local t = hunk_line_type(line)
    if (line_type == "+" or line_type == "common") and (t == "+" or t == "common") then
      count = count + 1
    elseif line_type == "-" and (t == "-" or t == "common") then
      count = count + 1
    end
  end

  return count
end

-- Assuming we have a zipper that's targetting a hunk,
-- build a description to make it easier ask useful question with
local function hunk_context(z)
  local hc = {}
  local node

  node = z:node()
  if node.type == type_hunk_content then
    hc[type_hunk_content] = node
    z:up()
    node = z:node()
  end

  if node.type == type_hunk_header then
    hc[type_hunk_header] = node
    z:up()
    node = z:node()
  end

  if node.type == type_file then
    hc[type_file] = node
    z:up()
    node = z:node()
  end

  if node.type == type_section then
    hc[type_section] = node
  end

  -- The zipper may have pointed to a hunk header
  -- Since a hunk header should only have a single hunk content node attached,
  -- it's straightforward to fill that in now.
  -- The rest of the code will not have to deal with these cases.
  if hc[type_hunk_content] == nil and hc[type_hunk_header] then
    hc[type_hunk_content] = hc[type_hunk_header].children[1]
  end

  return hc
end

local function hc_target_full_filepath(hc)
  local file = hc[type_file]
  if file then
    return string.format("%s/%s", u.git_root_dir(), file.filename)
  end
end

local function hc_target_rel_filepath(hc)
  local file = hc[type_file]
  if file then
    return file.filename
  end
end

local function outline_zipper_at_current_line()
  local lineno = vim.fn.line(".") - 1
  local outline = get_sole_status_screen().outline
  if not outline then
    return
  end

  return outline:node_zipper_at_lineno(lineno)
end

-- Jumps to the file and line of the hunk line under the cursor
local function jump_to_location()
  local lineno = vim.fn.line(".") - 1
  local outline = get_sole_status_screen().outline
  if not outline then
    return
  end

  local z = outline:node_zipper_at_lineno(lineno)
  if not z then
    return
  end

  local hc = hunk_context(z)

  -- Is the user targetting a specific line of a hunk?
  if hc[type_hunk_content] then
    local hunk_start = patch_parser.parse_hunk_header(hc[type_hunk_header].text[1])[2].start
    local rellineno = lineno - hc[type_hunk_content].lineno + 1
    local line_type = hunk_line_type(hc[type_hunk_content].text[rellineno])
    if line_type == "-" then
      line_type = "common"
    end
    local count = hunk_lines_count_type(hc[type_hunk_content].text, line_type, rellineno)
    vim.cmd(string.format("e +%i %s", hunk_start+count-1, hc_target_full_filepath(hc)))
  elseif hc[type_hunk_header] then
    local hunk_start = patch_parser.parse_hunk_header(hc[type_hunk_header].text[1])[2].start
    vim.cmd(string.format("e +%i %s", hunk_start, hc_target_full_filepath(hc)))
  elseif hc[type_file] then
    vim.cmd(string.format("e %s", hc_target_full_filepath(hc)))
  end
end


local function populate_hunks(outline, file_node, patch_info, filepath)
  local diff = patch_parser.find_file(patch_info.patch_info, filepath)
  if diff then
    for _, hunk in ipairs(diff.hunks) do
      -- Add hunk header as its own node
      -- These look something like "@@ -16,10 +17,14 @@"
      local heading = outline:add_node(file_node, {
          text = hunk.header_text,
          type = type_hunk_header,
        })

      -- Add the content of the hunk
      outline:add_node(heading, {
          text = string.sub(patch_info.patch_text, hunk.content_start, hunk.content_end),
          type = type_hunk_content,
        })
    end
  end
end

local function make_file_node(filename, mod_type)
  local heading
  if mod_type then
    heading = string.format("%s   %s", mod_type, filename)
  else
    heading = filename
  end
  return {
    text = u.markup({{
          group = "GitabraStatusFile",
          text = heading
    }}),
    filename = filename,
    type = type_file,
  }
end

local function make_recent_commit_node(log_entry)
  return {
    text = {format_log_recent_entry(log_entry)},
    type = type_recent_commit,
  }
end

local function node_id(node)
  if node.id then
    return node.id
  elseif node.md5 then
    return node.md5
  else
    node.md5 = md5.sumhexa(table.concat(node.text, "\n"))
    return node.md5
  end
end

local function reconcile_outline(old_outline, new_outline)
  local q = require('gitabra.list').new()

  -- We're going to start a breadth first traversal that walks
  -- through the two trees at the same time.
  q:push_right({old_outline.root, new_outline.root})

  while not q:is_empty() do
    -- print("iteration starts")
    local node_o, node_n = unpack(q:pop_left())
    -- print("working on:", node_o, node_n)
    -- print("working on:", node_id(node_o), node_id(node_n))

    if node_o.children or node_n.children then
      local cs_o = node_o.children or {}
      local cs_n = node_n.children or {}

      local diff = u.table_key_diff(
        u.table_array_items_by_id(cs_o, node_id),
        u.table_array_items_by_id(cs_n, node_id))


      -- Since we have cs_n(children of this node in new tree),
      -- we know the exact order the nodes should be in.
      -- All we have to do is to build an array that appear to have the
      -- same order, but using existing old nodes whenever possible.
      -- This allows us to carry old states over.
      local cs_o_by_id = u.table_array_items_by_id(cs_o, node_id)
      local cs_n_by_id = u.table_array_items_by_id(cs_n, node_id)

      local children = {}
      for _, node in ipairs(cs_n) do
        table.insert(children, cs_o_by_id[node_id(node)] or node)
      end
      node_o.children = children

      -- Continue our breadth first traversal.
      -- Usually, we do this by adding all current children of this node
      -- into the queue of nodes to be visited.
      --
      -- However, we do not need to visit newly added nodes, since they are
      -- nodes from the new tree that have been linked in directly. All child
      -- nodes stemming from there will be identical to content in the new tree.
      -- We also do not need to visit the removed nodes, since they are no longer
      -- part of the tree.
      --
      -- So, to continue our bread first traversal, and reconcile the rest of the
      -- tree, we only need to visit the nodes appears to have not changed.

      for _, id in ipairs(diff.common) do
        -- print("adding to q:", id)
        -- print("adding nodes:", cs_o_by_id[id], cs_n_by_id[id])
        q:push_right({cs_o_by_id[id], cs_n_by_id[id]})
      end
      -- print("before:", vim.inspect(cs_o))
      -- print("after:", vim.inspect(children))
    end

  end

  return old_outline
end

local update_hunk_hint_hl

local function gitabra_status()
  module_initialize()

  local st_info = status_info()
  local patches = patch_infos()

  local sc_o = get_sole_status_screen()
  local sc_n = {
    bufnr = sc_o.bufnr,
    winnr = sc_o.winnr
  }

  --------------------------------------------------------------------
  local outline = outliner.new({buffer = sc_n.bufnr})

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

  if st_info.branch and st_info.last_commit_msg then
    local header = u.markup({
        "Head:   ",
        {group = "GitabraBranch",
        text = st_info.branch},
        st_info.last_commit_msg,
    })

    outline:add_node(nil, {text = {header}})
  end

  if not u.table_is_empty(st_info.untracked) then
    local section = outline:add_node(nil, {
        text = u.markup({{
            group = "GitabraStatusSection",
            text = "Untracked"
        }}),
        type = type_section,
        id = "untracked",
        padlines_before = 1,
        show_child_count = true,
    })
    for _, file in pairs(st_info.untracked) do
      outline:add_node(section, make_file_node(file.name))
    end
  end

  if not u.table_is_empty(st_info.unstaged) then
    local section = outline:add_node(nil, {
        text = u.markup({{
            group = "GitabraStatusSection",
            text = "Unstaged"
        }}),
        type = type_section,
        id = "unstaged",
        padlines_before = 1,
        show_child_count = true,
    })
    for _, file in pairs(st_info.unstaged) do
      local file_node = outline:add_node(section, make_file_node(file.name, file.working))
      populate_hunks(outline, file_node, patches.unstaged, file.name)
      file_node.collapsed = true
    end
  end

  if not u.table_is_empty(st_info.staged) then
    local section = outline:add_node(nil, {
        text = u.markup({{
          group = "GitabraStatusSection",
          text = "Staged"
        }}),
        type = type_section,
        id = "staged",
        padlines_before = 1,
        show_child_count = true,
    })
    for _, file in pairs(st_info.staged) do
      local file_node = outline:add_node(section, make_file_node(file.name, file.index))
      populate_hunks(outline, file_node, patches.staged, file.name)
      file_node.collapsed = true
    end
  end

  if not u.table_is_empty(st_info.stash_list) then
    local section = outline:add_node(nil, {
        text = u.markup({{
          group = "GitabraStatusSection",
          text = "Stashes"
        }}),
        type = type_section,
        id = "stashes",
        padlines_before = 1,
        collapsed = true,
        show_child_count = true,
    })

    for _, stash_entry_str in ipairs(st_info.stash_list) do
      outline:add_node(section, {
        text = format_stash_entry(parse_stash_entry(stash_entry_str)),
        type = type_stash_entry,
      })
    end
  end

  if not u.table_is_empty(st_info.recents) then
    local section = outline:add_node(nil, {
        text = u.markup({{
          group = "GitabraStatusSection",
          text = "Recent commits"
        }}),
        type = type_section,
        id = "recents",
        padlines_before = 1,
        collapsed = true,
    })

    for _, log_entry_str in ipairs(st_info.recents) do
      outline:add_node(section, make_recent_commit_node(parse_log_recent_entry(log_entry_str)))
    end
  end

  -- Place the new outline into the global sc before any nodes & content are added.
  -- `get_fold_level` will be called by nvim as nodes are added to the outline.
  -- The global sc is the only way that function can find the currently active outline.
  sc_n.outline = outline
  sc_n.patches = patches
  --------------------------------------------------------------------

  -- Looking at different git repo than last time? Use the new state
  local is_same_git_root = sc_o.git_root == sc_n.git_root
  if not is_same_git_root then
    current_status_screen = sc_n

  -- Is it the first time we're starting gitabra_status?
  -- The old state would have no outline it was displaying.
  elseif not sc_o.outline then
    current_status_screen = sc_n

  -- The user have presumably slightly updated the outline tree.
  -- Figure out what changed.
  else
    current_status_screen.outline = reconcile_outline(sc_o.outline, sc_n.outline)
    current_status_screen.patches = sc_n.patches
  end

  -- Retain the current lineno or move to the beginning of the buffer
  -- depending on if we're refreshing the outline or building a completely new one
  local lineno
  if is_same_git_root then
    lineno = vim.fn.line(".")
  else
    lineno = 0
  end

  current_status_screen.outline:refresh()

  vim.cmd(tostring(lineno))

  update_hunk_hint_hl()
end

-- Given the contents of a hunk and the region that was selected (0 indexed),
-- return relevant lines and line count info that can be used to build
-- the hunk header and the hunk content
local function partial_hunk(hunk_content, region, for_discard)
  local unmarked_lines = 0
  local removed_lines = 0
  local added_lines = 0
  local content = {}

  for i, line in ipairs(hunk_content) do
    i = i - 1
    local type = hunk_line_type(line)

    if u.within_region(region, i) then
      if type == "+" then
        added_lines = added_lines + 1
        table.insert(content, line)
      elseif type == "-" then
        removed_lines = removed_lines + 1
        table.insert(content, line)
      end
    else
      -- If we're trying to unstage or discard something, any lines
      -- that have been added will already be in the index or working tree.
      -- If those lines have not been selected for unstaging or discarding,
      -- then they need to become the context lines. Otherwise, applying
      -- a reverse patch would fail becaue the context lines seem incorrect.
      if for_discard and type == "+" then
        unmarked_lines = unmarked_lines + 1
        table.insert(content, " "..line:sub(2))
      end
    end

    if type == "common" then
      unmarked_lines = unmarked_lines + 1
      table.insert(content, line)
    end
  end

  return {
    added = added_lines,
    removed = removed_lines,
    unmarked = unmarked_lines,
    content = content,
  }
end

local function in_visual_mode()
  if vim.fn.mode() == "V" then
    return true
  end
end

-- Using the given hunk_context and the currently selected lines,
-- prepare a patch that can be used with git-apply.
--
-- Patch generation will behave slightly different depending on
-- the "direction". If we're trying to discard or unstage something
-- AND have selected only part of the hunk, a little bit more work
-- is required to get the correct context lines so the patch can
-- be applied cleanly. See `partial_hunk` for details.
--
local function patch_from_selected_hunk(hc, for_discard)
  local patches = get_sole_status_screen().patches
  local patch = patches[hc[type_section].id]

  -- Generate a patch for the selected hunk
  -- To do that, we need a file diff header, the hunk header, and the hunk contents
  --
  -- To get the file diff header, we're going to extract whatever was returned from the `git diff`
  -- result for this particular file.
  --
  -- To get the hunk header and hunk content, we're going to grab both from the outline directly.

  local file_diff = patch_parser.find_file(patch.patch_info, hc_target_rel_filepath(hc))
  local diff_header = patch_parser.file_diff_get_header_contents(file_diff, patch.patch_text)
  diff_header = u.remove_trailing_newlines(diff_header)

  local hunk_header = hc[type_hunk_header].text[1]
  local hunk_content = hc[type_hunk_content].text

  -- If the user has selected just part of the hunk, we need to
  -- make some adjustments to the header and the content
  if in_visual_mode() then
    local region = u.selected_region()
    local offset = hc[type_hunk_content].lineno
    local result = partial_hunk(hc[type_hunk_content].text, {region[1]-offset, region[2]-offset}, for_discard)
    local hh = patch_parser.parse_hunk_header(hc[type_hunk_header].text[1])
    hh[1].count = result.unmarked + result.removed
    hh[2].count = result.unmarked + result.added

    hunk_header = patch_parser.make_hunk_header(hh)
    hunk_content = result.content

    -- Exit visual mode for the user
    -- TODO: Move this somewhere else. This shouldn't be done in the middle of generating a patch
    local mode = vim.fn.mode()
    if mode == "v" or mode == "V" then
      api.nvim_input("<ESC>")
    end
  end

  local lines = {diff_header, hunk_header}
  for _,v in ipairs(hunk_content) do
    table.insert(lines, v)
  end
  table.insert(lines, "")
  return table.concat(lines, "\n")
end

local function print_job_error(j)
  print(table.concat(j.err_output))
end

local function stage_hunk(hc)
  local direction
  if hc[type_section].id == "unstaged" then
    direction = "stage"
  else
    direction = "unstage"
  end

  local patch = patch_from_selected_hunk(hc, direction=="unstage")


  local j = git_apply_patch(direction, patch)
  job.wait(j, 100)

  if not u.table_is_empty(j.err_output) then
    print_job_error(j)
    print(string.format("%s failed", direction))
  else
    -- The state of the hunks have changed
    -- Simply refreshing the outline will not reflect the new state
    -- We need to run `git diff` again and rebuild everything
    gitabra_status()
  end
end

local function stage_file(hc)
  local j = git_add(hc_target_rel_filepath(hc))
  job.wait(j, 500)
  if not u.table_is_empty(j.err_output) then
    print_job_error(j)
  else
    gitabra_status()
  end
end

local function unstage_file(hc)
  local j = git_reset_file(hc_target_rel_filepath(hc))
  job.wait(j, 500)
  if not u.table_is_empty(j.err_output) then
    print_job_error(j)
  else
    gitabra_status()
  end
end

-- Try to stage the item under the cursor
local function stage()
  local z = outline_zipper_at_current_line()
  local node = z:node()
  local hc = hunk_context(z)

  -- Are we pointing at a hunk in the unstaged section?
  if (node.type == type_hunk_content or node.type == type_hunk_header) and hc[type_section].id == "unstaged" then
    stage_hunk(hc)

  -- Are we pointing at a file in the untracked or unstaged section?
  elseif node.type == type_file and (hc[type_section].id == "untracked" or hc[type_section].id == "unstaged") then
    stage_file(hc)
  end
end

local function unstage()
  local z = outline_zipper_at_current_line()
  local node = z:node()
  local hc = hunk_context(z)

  -- We're only going to deal with items in the staged section
  if hc[type_section].id ~= "staged" then
    return
  end

  if node.type == type_hunk_content or node.type == type_hunk_header then
    stage_hunk(hc)
  elseif node.type == type_file then
    unstage_file(hc)
  end
end

local function stage_all()
  local j =  u.system_async('git add -A', {split_lines=true})
  job.wait(j, 1000)
  if not u.table_is_empty(j.err_output) then
    print_job_error(j)
  else
    gitabra_status()
  end
end

local function unstage_all()
  local choice = vim.fn.confirm("Unstage all changes?", "y\nN", 2)
  if choice ~= 1 then
    return
  end

  local j =  u.system_async('git reset', {split_lines=true})
  job.wait(j, 1000)
  if not u.table_is_empty(j.err_output) then
    print_job_error(j)
  else
    gitabra_status()
  end
end

local function discard_hunk()
  local z = outline_zipper_at_current_line()
  local node = z:node()
  if not (node.type == type_hunk_content or node.type == type_hunk_header) then
    print("Oops... Don't know how to discard this yet...")
    return
  end

  local choice
  if in_visual_mode() then
    local region = u.selected_region()
    local count = region[2] - region[1] + 1
    choice = vim.fn.confirm(string.format("Really discard selected lines (%i)?", count), "y\nN", 2)
  else
    choice = vim.fn.confirm("Really discard this hunk?", "y\nN", 2)
  end
  if choice ~= 1 then
    return
  end

  local hc = hunk_context(z)
  local patch = patch_from_selected_hunk(hc, true)
  local include_staged = hc[type_section].id == "staged"

  local j = git_discard_hunk(include_staged, patch)
  job.wait(j, 1000)
  if not u.table_is_empty(j.err_output) then
    vim.cmd("redraw | echom 'Discard failed'")
  else
    gitabra_status()
  end
end

local hunk_hint = {
  last_buf_changetick = nil,
  node_ids = {},
  lines = {},
  signs = {},
}

local hunk_hint_sign_group = "Hunk Hint"

local function unplace_hunk_hints()
  if hunk_hint.signs[1] or hunk_hint.signs[2] then
    vim.fn.sign_unplace(hunk_hint_sign_group)
    hunk_hint.signs[1] = nil
    hunk_hint.signs[2] = nil
    hunk_hint.lines[1] = nil
    hunk_hint.lines[2] = nil
  end
end

local function update_hunk_hint_internal()
  local sc = get_sole_status_screen()
  -- If the buffer was not changed since the last time we updated the hunk hints,
  -- then we can just check if the current line is within the known
  if hunk_hint.last_buf_changetick == api.nvim_buf_get_changedtick(sc.bufnr) then
    local lineno = u.nvim_line_zero_idx(".")
    if hunk_hint.lines[1] and hunk_hint.lines[2] and
      hunk_hint.lines[1] <= lineno and lineno < hunk_hint.lines[2] then
      return
    end
  end
  local z = outline_zipper_at_current_line()
  if not z then
    return "unplace"
  end

  local hc = hunk_context(z:clone())
  if not hc[type_section] then
    return "unplace"
  end
  if hc[type_section].id ~= "unstaged" and hc[type_section].id ~= "staged" then
    return "unplace"
  end

  local n1 = hc[type_hunk_header]
  if not n1 then
    return "unplace"
  end
  if n1.collapsed then
    return "unplace"
  end

  local n2
  while z:node() ~= n1 and z:node() ~= z.root do
    z:up()
  end

  if z:right() then
    n2 = z:node()
  elseif z:next_up_right() then
    n2 = z:node()
  end

  if n1 and n2 then
    if node_id(n1) ~= hunk_hint.node_ids[1] or node_id(n2) ~= hunk_hint.node_ids[2] then
      unplace_hunk_hints()
      local lineno1 = n1.lineno+1
      local lineno2 = n2.lineno+1
      if n2.type == type_section then
        lineno2 = lineno2 - n2.padlines_before
      end
      local sc = get_sole_status_screen()
      hunk_hint.node_ids[1] = n1.id
      hunk_hint.node_ids[2] = n2.id
      hunk_hint.signs[1] = vim.fn.sign_place(0, hunk_hint_sign_group, "GitabraNodeActiveHeader", sc.bufnr, {lnum = lineno1})
      hunk_hint.signs[2] = vim.fn.sign_place(0, hunk_hint_sign_group, "GitabraNodeActiveHeader", sc.bufnr, {lnum = lineno2})
      hunk_hint.lines[1] = n1.lineno
      hunk_hint.lines[2] = n2.lineno
      hunk_hint.last_buf_changetick = api.nvim_buf_get_changedtick(sc.bufnr)
    end
  else
    if node_id(n1) ~= hunk_hint.node_ids[1] then
      vim.fn.sign_unplace(hunk_hint_sign_group)
      local lineno1 = n1.lineno+1
      local sc = get_sole_status_screen()
      hunk_hint.node_ids[1] = n1.id
      hunk_hint.signs[1] = vim.fn.sign_place(0, hunk_hint_sign_group, "GitabraNodeActiveHeader", sc.bufnr, {lnum = lineno1})
      hunk_hint.lines[1] = n1.lineno
      hunk_hint.last_buf_changetick = api.nvim_buf_get_changedtick(sc.bufnr)
    end
  end
end

update_hunk_hint_hl = function()
  local result = update_hunk_hint_internal()
  if result == "unplace" then
    unplace_hunk_hints()
  end
end

local function next_line()
  -- Move to the next line
  local lineno = u.nvim_line_zero_idx(".")+1
  if lineno >= api.nvim_buf_line_count(get_sole_status_screen().bufnr) then
    return
  end
  vim.cmd(tostring(lineno+1))
  update_hunk_hint_hl()
end

local function prev_line()
  -- Move to the prev line
  local lineno = u.nvim_line_zero_idx(".")-1
  if lineno < 0 then
    return
  end
  vim.cmd(tostring(lineno+1))
  update_hunk_hint_hl()
end

return {
  status_info = status_info,
  patch_infos = patch_infos,
  gitabra_status = gitabra_status,
  setup_window_and_buffer = setup_window_and_buffer,
  get_sole_status_screen = get_sole_status_screen,
  toggle_fold_at_current_line = toggle_fold_at_current_line,
  stage = stage,
  unstage = unstage,
  stage_all = stage_all,
  unstage_all = unstage_all,
  jump_to_location = jump_to_location,
  discard_hunk = discard_hunk,
  next_line = next_line,
  prev_line = prev_line,
}
