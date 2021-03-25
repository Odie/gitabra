-- Hierarchical zipper
-- Mostly mirrors the clojure.zip api
local u = require("gitabra.util")

local M = {}
M.__index = M

local function get_children(self, node)
  if type(self.children_fn) == "function" then
    return self.children_fn(node)
  elseif type(self.children_fn) == "string" then
    return node[self.children_fn]
  else
    error("children_fn is invalid")
  end
end

function M.new(root, children_fn)
  local o = {
    children_fn = children_fn,
    path = {root},
    path_idxs = {0},
    root = root,
  }
  setmetatable(o, M)
  return o
end

function M:clone()
  local o = {
    children_fn = self.children_fn,
    path = u.table_clone(self.path),
    path_idxs = u.table_clone(self.path_idxs),
    root = root,
  }
  setmetatable(o, M)
  return o
end

function M:set_new_root(node)
  path = {node}
  path_idxs = {0}
  root = root
end

function M:set_path(path_to_node)
  local path = {self.root}
  local path_idxs = {0}

  for _, target_idx in ipairs(path_to_node) do
    local curnode = u.table_get_last(path)
    local children = get_children(self, curnode)
    local target_node = children[target_idx]
    u.table_push(path, target_node)
    u.table_push(path_idxs, target_idx)
  end

  self.path = path
  self.path_idxs = path_idxs
end

-- Move to the parent of the current node
function M:up()
  if #self.path > 1 then
    table.remove(self.path)
    table.remove(self.path_idxs)
    return true
  end
  return false
end

-- Move to the first/leftmost child of the current node
-- Returns if the move was performed successfully
function M:down()
  local cs = self:children()

  if cs and #cs >= 1 then
    u.table_push(self.path, cs[1])
    u.table_push(self.path_idxs, 1)
    return true
  end
  return false
end

-- Navigate to the given child `child_node`.
-- This will only work if the child node is actually a child of the current node.
-- Returns true if navigation succeeded
function M:to_child_node(child_node)
  local cs = self:children()
  if child_node == self then
    return false
  end
  for i, c in ipairs(cs) do
    if c == child_node then
      u.table_push(self.path, c)
      u.table_push(self.path_idxs, i)
      return true
    end
  end
  return false
end

-- Moves to the right sibling of the current node
function M:right()
  -- If there is no parent for the current node,
  -- there is nothing to do
  if #self.path == 1 then
    return false
  end
  local parent = self.path[#self.path-1]

  local cur_idx = u.table_get_last(self.path_idxs)
  local target_sibling = cur_idx + 1

  local siblings = get_children(self, parent)
  if #siblings >= target_sibling then
    u.table_pop(self.path)
    u.table_push(self.path, siblings[target_sibling])
    u.table_pop(self.path_idxs)
    u.table_push(self.path_idxs, target_sibling)
    return true
  end

  return false
end

-- Moves to the left sibling of the current node
function M:left()
  if #self.path == 1 then
    return false
  end

  local cur_idx = u.table_get_last(self.path_idxs)
  local target_sibling = cur_idx - 1
  if target_sibling < 1 then
    return false
  end

  local parent = self.path[#self.path-1]
  local siblings = get_children(self, parent)

  u.table_pop(self.path)
  u.table_push(self.path, siblings[target_sibling])
  u.table_pop(self.path_idxs)
  u.table_push(self.path_idxs, target_sibling)
  return true
end

-- Get a list of children of the current node
function M:children()
  local curnode = self:node()
  return get_children(self, curnode)
end

function M:set_children(cs)
  local curnode = self:node()
  assert(type(self.children_fn) == "string")
  curnode[self.children_fn] = cs
end

-- Returns whether the current node has child nodes or not
function M:has_children()
  local cs = self:children()
  return cs and #cs ~= 0
end

-- Get the current node
function M:node()
  return u.table_get_last(self.path)
end

function M:parent_node()
  local target_idx = #self.path-1
  if target_idx < 1 then
    return nil
  else
    return self.path[target_idx]
  end
end

-- Returns if the path is indicating it is at an and of a depth first traversal
function M:at_end()
  if #self.path >= 2 and self.path[2] == "end" and self.path_idxs[2] == -1 then
    return true
  else
    return false
  end
end

-- Removes the end marker in the path if found
function M:remove_end_marker()
  if self:at_end() then
    u.table_pop(self.path)
    u.table_pop(self.path_idxs)
  end
end

-- Moves to the next node in the tree, depth-first.
--
-- If all nodes have been traversed, and end marker will be added
-- to the `path`. `at_end()` will return true.
-- The end marker can be removed with `remove_end_marker()` to
-- restore the zipper to a state where additional navigation
-- can be performed.
function M:next()
  -- Don't do anything if we're at the end of a depth first traversal
  if self:at_end() then
    return false
  end

  -- Try to go down the tree...
  if self:has_children() and self:down() then
    return true
  end

  -- If that wasn't possible, try to go right
  if self:right() then
    return true
  end

  return self:next_up_right()
end

-- Moves to the next valid item by try `up` and `right` continuously
--
-- This is part of the behavior of `next`.
-- It's included here to make it easier to replicate a next-like
-- movement.
--
-- This is useful, for example, when trying to perform a dfs visit,
-- but reject going down certain branches altogether.
function M:next_up_right()
  -- Move up the tree while trying to go right
  -- Here, we either end up finding some ancestor node where
  -- moving right succeeded...
  -- Or, we end up at the root with an "end" marker in the path
  while true do
    if not self:up() then
      u.table_push(self.path, "end")
      u.table_push(self.path_idxs, -1)
      return false
    end

    if self:right() then
      return true
    end

    -- Moving up and right didn't seem to work
    -- Try again...
  end
end

return M
