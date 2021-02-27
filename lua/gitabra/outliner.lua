local api = vim.api
local u = require('gitabra.util')

local M = {}
M.__index = M

local namespace_id = api.nvim_create_namespace("gitabra.outliner")
M.namespace_id = namespace_id


-- Returns the line number where the beginning of a new node should be placed if it were
-- added to the parent_node
local function new_node_lineno(self, parent_node)
  -- print(">>> new_node_lineno")
  local children = parent_node.children
  local target_node = children[#children] or parent_node

  -- print("parent:", vim.inspect(parent))
  -- print("target_node:", vim.inspect(target_node))

  -- The root itself has no content and has no extmark associated.
  -- If the target node is root, this also means there are no children
  -- currently in the root.
  -- The line where the new node should be placed is 0, the beginning
  -- of the document.
  if target_node == self.root then
    -- print("target node is root")
    -- print("returning default insert location for empty outline")
    -- print("<<< new_node_lineno")
    return 0
  end

  -- print("checking existing extmarks")

  -- We're trying to add some content "after" the target node.
  -- Find out which line it's on
  local last_row = 0
  local matched_node
  for node in u.table_depth_first_visit(parent_node) do
    if node.extmark_id ~= nil then
      -- print("visiting node:", vim.inspect(node))
      local position = api.nvim_buf_get_extmark_by_id(self.buffer, namespace_id, node.extmark_id, {})

      -- print("position for node is:", vim.inspect(position))
      last_row = math.max(last_row, position[1])
      matched_node = node
      -- print("new last row:", last_row)
    end
  end

  print("matched node:", vim.inspect(matched_node))
  print("last row:", last_row, last_row+#matched_node.text)

  local padlines = 0
  if(parent_node.depth == 0) then
    padlines = 1
  end

  local result = last_row + #matched_node.text + padlines
  -- print("New node lineno result:", result)
  -- print("<<< new_node_lineno")
  return result
end

function M.new(o_in)
  local o = o_in or {}
  o.root = o.root or {}
  if o.root.depth == nil then
    o.root.depth = 0
  end
  o.root.children = o.root.children or {}
  setmetatable(o, M)
  return o
end


-- Add a `child_node` into the `parent_node`
-- Return the added child node
function M:add_node(parent_node, child_node)
  -- print(">>> Add Node")
  -- Use the root node if a parent node is not specified
  if not parent_node then
    parent_node = self.root
  end

  if not child_node.children then
    child_node.children = {}
  end

  -- Add the child node
  if type(child_node.text) == "string" then
    child_node.text = u.lines_array(child_node.text)
  end
  -- local lines = child_node.lines or u.lines_array(child_node.text)
  -- child_node.lines = lines

  print(">>>>>>>>>>>>>>>>>>>>>>> looking to add:", child_node.text)
  -- Put the child node text into the buffer
  local lineno = new_node_lineno(self, parent_node)
  print("****** [extmark & content] adding at line:", lineno)

  u.buf_padlines_to(self.buffer, lineno+#child_node.text)
 	api.nvim_buf_set_lines(self.buffer, lineno, lineno+#child_node.text, true, child_node.text)

  -- Add extmark at the same location
 	child_node.extmark_id = api.nvim_buf_set_extmark(self.buffer, namespace_id, lineno, 0, {})

  child_node.depth = parent_node.depth + 1
  child_node.lineno = lineno
  table.insert(parent_node.children, child_node)
  -- print("<<< Add Node")
  return child_node
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
