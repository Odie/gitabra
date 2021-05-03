local u = require("gitabra.util")
local patch_parser = require("gitabra.patch_parser")

-- Node types
local type_section = "section"
local type_file = "file"
local type_hunk_header = "hunk header"
local type_hunk_content = "hunk content"
local type_stash_entry = "stash entry"
local type_recent_commit = "recent commit"

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


local function populate_hunks(outline, file_node, patch, entry)
  for _, hunk in ipairs(entry.hunks) do
    -- Add hunk header as its own node
    -- These look something like "@@ -16,10 +17,14 @@"
    local heading = outline:add_node(file_node, {
        text = hunk.header_text,
        type = type_hunk_header,
      })

    -- Add the content of the hunk
    outline:add_node(heading, {
        text = string.sub(patch.patch_text, hunk.content_start, hunk.content_end),
        type = type_hunk_content,
      })
  end
end

local function populate_hunks_by_filepath(outline, file_node, patch, filepath)
  local diff = patch_parser.find_file(patch.patch_info, filepath)
  if diff then
    return populate_hunks(outline, file_node, patch, diff)
  end
end

-- WARNING: depeds on currently active bufnr
local function outline_toggle_fold_at_current_line(outline)
  if not outline then
    return
  end
  local lineno = vim.fn.line(".") - 1

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


-- Parse reference names, such as "origin/master"
local function parse_ref(ref_str)
  ref_str = u.trim(ref_str)
  local result =  {}

  local name = string.match(ref_str, "^HEAD %-> refs/heads/(.*)$") or
               string.match(ref_str, "^HEAD %-> (.*)$")

  if name then
    result.name = name
    result.current_branch = true
    return result
  end

  name = string.match(ref_str, "^refs/heads/(.*)$")
  if name then
    result.name = name
    result["local"] = true
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

local function parse_refs(refs_str)
  return u.map(u.string_split_by_pattern(refs_str, ","), parse_ref)
end

-- Format data returned from `parse_ref` into format that's usable by an outline
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

local function outline_zipper_at_current_line(outline)
  return outline:node_zipper_at_lineno(u.nvim_line_zero_idx("."))
end

return {
  type_section = type_section,
  type_file = type_file,
  type_hunk_header = type_hunk_header,
  type_hunk_content = type_hunk_content,
  type_stash_entry = type_stash_entry,
  type_recent_commit = type_recent_commit,

  make_file_node = make_file_node,
  populate_hunks_by_filepath = populate_hunks_by_filepath,
  populate_hunks = populate_hunks,
  outline_toggle_fold_at_current_line = outline_toggle_fold_at_current_line,
  outline_zipper_at_current_line = outline_zipper_at_current_line,

  parse_refs = parse_refs,
  parse_ref = parse_ref,
  format_ref = format_ref,
}
