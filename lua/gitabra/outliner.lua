local api = vim.api
local u = require('gitabra.util')

local M = {}
M.__index = M


local namespace_id = api.nvim_create_namespace("gitabra")


-- Returns the line number where the beginning of a new node should be placed if it were
-- added to the parent_node
local function new_node_lineno(self, parent_node)
  local children = parent_node.children
  local target_node = children[#children] or parent_node

  print("parent:", vim.inspect(parent))
  print("target_node:", vim.inspect(target_node))

  -- The root itself has no content and has no extmark associated.
  -- If the target node is root, this also means there are no children
  -- currently in the root.
  -- The line where the new node should be placed is 0, the beginning
  -- of the document.
  if target_node == self.root then
    print("target node is root")
    return 0
  end

  print("checking existing extmark")

  -- We're trying to add some content "after" the target node.
  -- Find out which line it's on
  local position = vim.api.nvim_buf_get_extmark_by_id(self.buffer, namespace_id, target_node.extmark_id, {details = false})
  print("last node position:")
  print(vim.inspect(position))

  return (position[1] or 0)+1
end


function M.new(o_in)
  local o = o_in or {}
  o.root = o.root or {}
  o.root.children = o.root.children or {}
  o.buffer = o.buffer or vim.api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(o.buffer, 'Gitabra')
  api.nvim_buf_set_option(o.buffer, 'swapfile', false)
  api.nvim_buf_set_option(o.buffer, 'buftype', 'nofile')
  setmetatable(o, M)
  return o
end


-- Add a `child_node` into the `parent_node`
function M:add_node(parent_node, child_node)
  -- Use the root node if a parent node is not specified
  if not parent_node then
    parent_node = self.root
  end

  if not child_node.children then
    child_node.children = {}
  end

  -- Add the child node
  local children = parent_node.children
  local last_child = children[#children]


  -- Put the child node text into the buffer
  local lineno = new_node_lineno(self, parent_node)
  print("adding at line:", lineno)
 	api.nvim_buf_set_lines(self.buffer, lineno, lineno, false, {child_node.heading_text or ""})

  -- Add extmark at the same location
 	child_node.extmark_id = api.nvim_buf_set_extmark(self.buffer, namespace_id, lineno, 0, {})

  table.insert(parent_node.children, child_node)
end


function M:close()
  api.nvim_buf_delete(self.buffer, {})
end


function M:find_node(pred)
  return u.table_find_node(self.root, pred)
end


-- Walk the document/outline and find an item with
-- the given `name` in the `id` field.
function M:node_by_id(name)
  return u.table_find_node(self.root, function(node)
    if node.id == name then
      return true
    end
  end)
end

return M
