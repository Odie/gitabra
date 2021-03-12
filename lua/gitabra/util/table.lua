local uf = require('gitabra.util.functional')

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

local function table_key_diff(t1, t2)
  local added = {}
  local removed = {}
  local common = {}

  -- For every k in t1...
  for k, v in pairs(t1) do
    if v ~= nil then
      -- If that k is also in t2, then tables
      -- have the key in common
      if t2[k] then
        table_push(common, k)
      else
      -- If that k is not in t2, the key has been removed
        table_push(removed, k)
      end
    end
  end

  for k, v in pairs(t2) do
    if v ~= nil then
      if not t1[k] then
        table_push(added, k)
      end
    end
  end

  return {
    added = added,
    removed = removed,
    common = common,
  }
end

local function table_array_to_set(t, id_func)
  if not id_func then
    id_func = uf.ident
  end
  local set = {}
  for _, v in ipairs(t) do
    local k = id_func(v)
    if k then
      set[k] = v
    end
  end
  return set
end

local table_array_items_by_id = table_array_to_set


local function table_array_find_by(t, target_val, val_func)
  if not val_func then
    val_func = uf.ident
  end
  for i, e in ipairs(t) do
    if val_func(e) == target_val then
      return i
    end
  end
end

local function table_is_empty(t)
  if next(t) == nil then
    return true
  else
    return false
  end
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
  table_key_diff = table_key_diff,
  table_array_to_set = table_array_to_set,
  table_array_items_by_id = table_array_items_by_id,
  table_array_find_by = table_array_find_by,
  table_is_empty = table_is_empty,
}
