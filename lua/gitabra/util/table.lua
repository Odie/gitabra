
-- Performs a shallow copy of a list of hashtables into the `target`
local function table_copy_into(target, ...)
  local tables = {...}
  for _, t in ipairs(tables) do
    if type(t) == "table" then
      for k,v in pairs(t) do
        target[k] = v
      end
    end
  end
  return target
end

-- Alias for better code clarity
local table_push = table.insert
local table_pop = table.remove
local function table_get_last(t)
  return t[#t]
end

local function table_clone(t)
  return {table.unpack(t)}
end

local function table_lazy_get(table, key, default)
  local v = table[key]
  if not v then
    table[key] = default
    v = default
  end
  return v
end

local function table_depth_first_visit(root_table, children_fieldname)
  local stack = {}

  table_push(stack, {
      node = root_table,
      visited = false
  })

  local depth_first_visit
  depth_first_visit = function()
    local node = table_get_last(stack)

    -- If there are no more nodes to visit,
    -- we're done!
    if node == nil then
      return nil
    end

    -- Visit the node itself
    if not node.visited then
      node.visited = true
      return node.node
    end

    -- Grab the iterator for the current node
    local iter = node.iter
    if not node.iter then
      local children
      if children_fieldname then
        children = node.node[children_fieldname]
      else
        children = node.node
      end

      node.iter = {pairs(children)}
      -- We should get back a function `f`, an invariant `s`, and a control variable `v`

      iter = node.iter
    end

    -- Grab a child node
    while true do
      local k, next_node = iter[1](iter[2], iter[3]) -- f(s, v)
      iter[3] = k -- update the control var to prep for next iteration

      -- Do we have more child nodes to visit?
      if k == nil then
        -- If not, continue visits at the parent
        table_pop(stack)
        return depth_first_visit()
      end

      -- Visit child nodes
      if type(next_node) == "table" then
        table_push(stack, {
            node = next_node,
            visted = false
        })
        return depth_first_visit()
      end
    end
  end

  return depth_first_visit
end


local function table_find_node(t, pred)
  for node in table_depth_first_visit(t) do
    if pred(node) then
      return node
    end
  end
  return nil
end

return {
  table_copy_into = table_copy_into,
  table_depth_first_visit = table_depth_first_visit,
  table_lazy_get = table_lazy_get,
  table_find_node = table_find_node,
  table_push = table_push,
  table_pop = table_pop,
  table_get_last = table_get_last,
  table_clone = table_clone,
}
