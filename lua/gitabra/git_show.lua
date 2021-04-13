local u = require("gitabra.util")
local a = require("gitabra.async")
local outliner = require("gitabra.outliner")
local ou = require("gitabra.outliner_util")
local patch_parser = require("gitabra.patch_parser")
local promise = require("gitabra.promise")
local api = vim.api

-- List of all file revisions being viewed.
-- filepath => revision_context
local active_revisions = {}
local active_revision = {}

local revision_header_format = [[
Author:     %aN <%aE>
AuthorDate: %ad
Commit:     %cN <%cE>
CommitDate: %cd
]]

local module_initialized = false
local function module_initialize()
  if module_initialized then
    return
  end

  local attrs = u.hl_group_attrs("Yellow")
  attrs.gui = "bold"
  attrs.cterm  = "bold"
  vim.cmd(string.format("highlight GitabraRevBufID %s", u.hl_group_attrs_to_str(attrs)))

  module_initialized = true
end

-- The only reason why we're running these jobs with the async library is to
-- try to pull the locations where the data is requested closer to the place where
-- data is parsed.
--
-- The revision buffer seems to make a lot of calls to git to assemble all the information
-- it wants to display. In the case of `git_commit_parent` it'll literally ask git for two strings.
-- When the data is is returned, we're supposed to take the output via stdout, split by whitespace to
-- retrieve the two values.
--
-- It makes the code much more readable if the code for fetching and parsing were placed side-by-side.
--

local function commit_summary(commit_summary_lines)
  local header = u.table_slice(commit_summary_lines, 1, 5)

  local stat_summary = u.trim(u.table_get_last(commit_summary_lines))
  local stat_entry_count = string.match(stat_summary, "(%d+) files")
  local stat_start = stat_entry_count * -1 - 1
  local stat_details = u.map(u.table_slice(commit_summary_lines, stat_start, -2), u.trim)

  return {
    commit_id = u.string_split_by_pattern(u.table_first(header), " ")[2],
    header = u.table_rest(header),
    stat_summary = stat_summary,
    stat_details = stat_details,
  }
end

local function task_git_commit_summary(rev)
  return a.sync(function ()
    local j = a.wait(u.system_async({"git", "show", "--pretty=fuller", "--stat", rev}, {split_lines=true}))
    return commit_summary(j.output)
  end)
end

local function git_commit_patch(rev)
  return u.system_as_promise({"git", "show", "--format=", rev}, {merge_output=true})
end

-- local function task_git_commit_msg(rev)
--   return a.sync(function ()
--     local j = a.wait(u.system_async({"git", "show", "--", "--stat", "--no-patch", rev}, {split_lines=true}))
--     return j.output
--   end)
-- end

local function task_git_commit_parent(rev)
  return a.sync(function ()
    local j = a.wait(u.system_async({"git", "rev-list", "-1", "--parents", rev}, {split_lines=true}))
    return u.string_split_by_pattern(j.output[1], " ")[2]
  end)
end

local function git_show_with_format(format, rev)
  return u.system_as_promise({"git", "show", string.format("--format=%s", format), "--no-patch", "--decorate=full", rev}, {split_lines=true})
end

local function git_commit_msg(rev)
  return git_show_with_format("%B", rev)
end

local function git_ref_labels(rev)
  return git_show_with_format("%D", rev)
end

local function git_rev_header(rev)
  return git_show_with_format(revision_header_format, rev)
end

local function toggle_fold_at_current_line()
  ou.outline_toggle_fold_at_current_line(active_revision.outline)
end

local function restore_old_buffer()
  if active_revision.old_bufnr then
    api.nvim_set_current_buf(active_revision.old_bufnr)
  end
end

local function setup_keybinds(bufnr)
  local function set_keymap(...) vim.api.nvim_buf_set_keymap(bufnr, ...) end
  local opts = { noremap=true, silent=true }
  set_keymap('n', '<tab>', '<cmd>lua require("gitabra.git_show").toggle_fold_at_current_line()<cr>', opts)
  set_keymap('n', '<enter>', '<cmd>lua require("gitabra.git_show").jump_to_location()<cr>', opts)
  set_keymap('n', 'q', '<cmd>lua require("gitabra.git_show").restore_old_buffer()<cr>', opts)
end

local function setup_buffer()
  local buf = vim.api.nvim_create_buf(true, false)
  -- api.nvim_buf_set_name(buf, status_buf_name)
  vim.bo[buf].filetype = 'GitabraRevision'
  vim.bo[buf].swapfile = false
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].syntax = 'diff'
  vim.bo[buf].modifiable = false
  setup_keybinds(buf)
  return buf
end

local function gather_info(rev)
  local commit_summary_p = a.as_promise(task_git_commit_summary(rev))
  local commit_patch_p = git_commit_patch(rev)
  local ref_labels_p = git_ref_labels(rev)
  local msg_p = git_commit_msg(rev)
  local ps = {commit_summary_p, commit_patch_p, ref_labels_p, msg_p}

  local wait_result = promise.wait_all(ps, 2000)
  if not wait_result then
    local funcname = debug.getinfo(1, "n").name
    print(vim.inspect(ps))
    error(string.format("%s: unable to complete git commands within the alotted time", funcname))
  end

  return {
    summary = commit_summary_p.value,
    patch = commit_patch_p.value[1],
    ref_labels = ref_labels_p.value[1],
    msg = msg_p.value,
  }
end

local function setup_window()
  vim.cmd(":botright vsplit")
  return api.nvim_get_current_win()
end

local function git_show(opts)
  module_initialize()
  local rev_buf = u.table_clone(opts)

  if not rev_buf.winnr then
    rev_buf.winnr = setup_window()
  end

  if not rev_buf.bufnr then
    rev_buf.bufnr = setup_buffer()
  end

  local rev_info = gather_info(opts.rev)
  local patch = patch_parser.parse(rev_info.patch)

  local outline = outliner.new({buffer = rev_buf.bufnr})
  outline.type = "RevBuffer"
  rev_buf.outline = outline

  ----------------------------------------------------------------
  -- Commit ID
  outline:add_node(nil, {
      text = u.markup({{
            group = "GitabraRevBufID",
            text = string.format("commit %s", u.git_shorten_sha(rev_info.summary.commit_id)),
        }}),
        type = ou.type_section,
        id = "RevBufID",
    }
  )

  ----------------------------------------------------------------
  -- Author info
  local refs = u.markup(u.map(ou.parse_refs(rev_info.ref_labels), ou.format_ref))
  table.insert(refs, {
    group = "GitabraRev",
    text = rev_info.summary.commit_id,
  })
  local commit_header_node = outline:add_node(nil, {
      text = refs,
      type = ou.type_section,
      id = "CommitHeader",
    }
  )
  outline:add_node(commit_header_node, {
    text = u.table_copy_into({},
      rev_info.summary.header
    )
  })

  ----------------------------------------------------------------
  -- Commit message
  local msg_subject = u.table_first(rev_info.msg)
  local msg_body = u.table_rest(rev_info.msg)

  if msg_subject then
    local msg_node = outline:add_node(nil, {
      text = msg_subject,
      type = "CommitMessage",
      padlines_before = 1,
    })

    if not u.table_is_empty(msg_body) then
      outline:add_node(msg_node, {
        text = msg_body
      })
    end
  end

  ----------------------------------------------------------------
  -- Commit stats
  local stat_node = outline:add_node(nil, {
    text = rev_info.summary.stat_summary,
    type = "CommitStat",
    padlines_before = 1,
  })

  if not u.table_is_empty(rev_info.summary.stat_details) then
    outline:add_node(stat_node, {
      text = rev_info.summary.stat_details,
    })
  end

  ----------------------------------------------------------------
  -- Commit diff

  if not u.table_is_empty(patch.patch_info) then
    for _, entry in pairs(patch.patch_info) do
      local file_node = outline:add_node(nil, ou.make_file_node(entry.b_file))
      file_node.padlines_before = 1
      ou.populate_hunks(outline, file_node, patch, entry)
    end
  end

  api.nvim_set_current_win(rev_buf.winnr)
  rev_buf.old_bufnr = api.nvim_get_current_buf()
  api.nvim_set_current_buf(rev_buf.bufnr)
  outline:refresh()
  active_revision = rev_buf
end

return {
  git_show = git_show,
  toggle_fold_at_current_line = toggle_fold_at_current_line,
  restore_old_buffer = restore_old_buffer,
  task_git_commit_summary = task_git_commit_summary,
}
