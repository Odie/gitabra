local api = vim.api
local u = require('gitabra.util')
local zipper = require('gitabra.zipper')

local M = {}
M.__index = M

local namespace_id = api.nvim_create_namespace("gitabra.outliner")
local linemark_ns = api.nvim_create_namespace("gitabra.outliner/linemark")
M.namespace_id = namespace_id


local function node_debug_text(node)
  local text = node.id or node.text
  if type(text) == "table" then
    text = vim.inspect(text)
  end
  if #text > 100 then
    text = string.sub(text, 1, 97).."..."
  end
  return text
end

local function print_cs(cs)
  for _, n in ipairs(cs) do
    print(node_debug_text(n))
  end
end

-- Given some `target_node` and its `parent_node`, determine
-- which line the target_node's text should start on
local function determine_node_lineno(self, parent_node, target_node)

  -- The root node has no text
  -- There is no line where it can start
  if target_node == self.root then
    assert(true, "target_node should not be root")
    return 0
  end

  -- print("Scanning all nodes that come before the target node")
  -- Look through the parent node and see if we can find a node that sits just
  -- before the target node, which has a valid linemark
  local last_row = 0
  local matched_node = nil

  -- Look for the last visible item in the tree that appears just before the
  -- target node.
  -- This will visit all sibling nodes and their descendents.
  -- It might be better if we implemented `prev` in the zipper.
  local z = zipper.new(parent_node, "children")
  while not z:at_end() do
    local node = z:node()
    -- print("@", vim.inspect(node))

    -- The document tree is already fully formed...
    -- We want to figure out where content that comes before
    -- the target node has been placed.
    -- If we come across the target_node, we're done
    if node == target_node then
      break
    end

    if node.linemark ~= nil then
      -- print("located a node with linemark")
      local position = api.nvim_buf_get_extmark_by_id(self.buffer, linemark_ns, node.linemark, {})

      if position[1] then
        last_row = math.max(last_row, position[1])
        matched_node = node
        -- print("position for node is:", vim.inspect(position))
        -- print("new last row:", last_row)
      else
        -- print("linemark is invalid")
      end
    end

    z:next()
  end

  if not matched_node then
    -- print("no matched node, returning 0")
    return 0
  end

  local result = last_row + #matched_node.text
  if target_node.padlines_before then
    result = result + target_node.padlines_before
  end
  return result
end

local function lineno_from_linemark(self, linemark)
  local position = api.nvim_buf_get_extmark_by_id(self.buffer, linemark_ns, linemark, {})
  return position[1]
end

function M:lineno_from_node(node)
  if node.linemark then
    return lineno_from_linemark(node.linemark)
  end
end

function M.new(o_in)
  local o = o_in or {}
  o.root = o.root or {}
  o.root.id = "outliner-root"
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

  child_node.depth = parent_node.depth + 1
  table.insert(parent_node.children, child_node)
  -- print("<<< Add Node")
  return child_node
end

function M:delete_all_linemarks()
  -- Cleanup all known linemarks in the outline
  for node in u.table_depth_first_visit(self.root) do
    if node.linemark then
      -- print("deleting linemark:", node.linemark)
      api.nvim_buf_del_extmark(self.buffer, linemark_ns, node.linemark)
      node.linemark = nil
    end
  end

  -- Just in case... clear everything in the namespace, which should
  -- only include linemarks
  api.nvim_buf_clear_namespace(self.buffer, linemark_ns, 0, -1)
end

function M:delete_all_text()
  api.nvim_buf_set_lines(self.buffer, 0, -1, true, {})
end

function M:refresh()
  self:delete_all_linemarks()
  self:delete_all_text()

  -- Start a new zipper and move to the first child of the root node
  local z = zipper.new(self.root, "children")
  z:down()

  -- print("About to start loop")
  while not z:at_end() do
    -- print("loop start")
    local node = z:node()
    local parent = z:parent_node()

    -- print(">>>>>>>>>>>>>>>>>>>>>>> looking to add:", node_debug_text(node))
    -- Determine where we should be placing the text
    local lineno = determine_node_lineno(self, parent, node)
    -- print("**** extmark & content] adding at line:", lineno)

    -- Place the text into the buffer at said location
    u.buf_padlines_to(self.buffer, lineno+#node.text)
 	  api.nvim_buf_set_lines(self.buffer, lineno, lineno+#node.text, true, node.text)

    -- Add extmark at the same location
 	  node.linemark = api.nvim_buf_set_extmark(self.buffer, linemark_ns, lineno, 0, {})
    node.lineno = lineno

    -- If this node has been collapsed, move on to the next sibling branch
    if node.collapsed then
      -- print("moving right")
      if not z:right() then
        -- print("moving right failed, no more siblings")
        z:next_up_right()
      end
    else
      -- Otherwise, continue the depth-first traversal
      -- print("moving next")
      z:next()
    end
  end
end

-- Returns a {start, end} tuple where the content of the node resides
function M:region_occupied(node)
  local position = api.nvim_buf_get_extmark_by_id(self.buffer, linemark_ns, node.linemark, {})
  if position[1] then
    return {position[1], position[1] + #node.text - 1}
  end
end

local function within_region(region, lineno)
  if region[1] <= lineno and lineno <= region[2] then
    return true
  else
    return false
  end
end


function M:node_zipper_at_lineno(lineno)
  local z = zipper.new(self.root, "children")
  local cs = z:children()

  while cs and #cs ~= 0 do
    -- print("loop start")
    -- print("path so far:", vim.inspect(z.path_idxs))
    -- print("cs @")
    -- print_cs(cs)

    -- Filter for children with linemarks
    cs = u.filter(cs, function(c)
      if c.linemark then
        return true
      end
    end)

    -- print("filtered @")
    -- print_cs(cs)

    -- Retrieve/update all starting lineno of children
    u.map(cs, function(c)
      c.lineno = lineno_from_linemark(self, c.linemark)
      return c
    end)

    -- print("mapped @")
    -- print_cs(cs)

    -- From the valid child candidates, pick the node that seems to contain the lineno
    -- we're searching for
    local candidate = nil
    if #cs == 1 then
      -- print("choosing only child")

      if lineno >= cs[1].lineno then
        candidate = cs[1]
      end
    else
      -- print("choosing best match from children")
      -- Using the starting line number for each sibling pair,
      -- try to figure out which node/path we should go down towards
      for c1, c2 in u.partition_iterator(cs, 2, 1) do
        -- print("c1", c1.lineno, node_debug_text(c1))
        -- print("c2", c2.lineno, node_debug_text(c2))

        if c1.lineno <= lineno and lineno < c2.lineno then
          -- print("picking c1")
          candidate = c1
          break
        end
      end

      -- If we found no results after examining all pairs, we'll
      -- assume it's because the last node is the matching node
      if not candidate then
        -- print("Picking last child")
        candidate = cs[#cs]
      end
    end

    -- Can't drill down any further?
    -- Use the path we have so far as the result
    if not candidate then
      -- print("No available candidates this loop")
      break
    end

    -- print("navigating to child @", node_debug_text(candidate))
    z:to_child_node(candidate)
    cs = z:children()
  end

  -- print("No more child nodes")
  -- print("picked node:", node_debug_text(z:node()))

  -- At this point, the zipper should be pointing at a node
  -- that we think contains the target linenumber.
  if within_region(self:region_occupied(z:node()) , lineno) then
    -- print("is in region")
    return z
  else
    -- print("not within region")
    return nil
  end
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
