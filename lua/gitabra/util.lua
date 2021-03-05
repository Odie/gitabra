local job = require('gitabra.job')
local chronos = require('chronos')
local api = vim.api

-- Returns an iterator over each line in `str`
local function lines(str)
  return str:gmatch("[^\r\n]+")
end

local function lines_array(str)
  local result = {}
  for line in lines(str) do
    table.insert(result, line)
  end
  return result
end

-- Execute the given command asynchronously
-- Returns a `results` table.
-- `done` field indicates if the job has finished running
-- `output` table stores the output of the executed command
-- `job` field contains a `gitabra.job` object used to run the command
--
local function system_async(cmd, opt)
  local result = {
    output = {},
    err_output = {},
    done = false
  }
  opt = opt or {}

	local j = job.new({
      cmd = cmd,
      on_stdout = function(_, err, data)
        if err then
          print("ERROR: "..err)
        end
        if data then
          if opt.splitlines then
            for line in lines(data) do
              table.insert(result.output, line)
            end
          else
            table.insert(result.output, data)
          end
        end
      end,
      on_stderr = function(_, err, data)
        if err then
          print("ERROR: "..err)
        end
        if data then
          if opt.splitlines then
            for line in lines(data) do
              table.insert(result.output, line)
            end
          else
            table.insert(result.err_output, data)
          end
        end
      end,
      on_exit = function(_, _, _)
        if opt.merge_output and #result.output > 1 then
          result.output = { table.concat(result.output) }
        end
        result.done = true
        result.stop_time = chronos.nanotime()
        result.elapsed_time = result.stop_time - result.start_time
      end
    })

  result.start_time = chronos.nanotime()
  j:start()

  result.job = j
  return result
end

local function table_lazy_get(table, key, default)
  local v = table[key]
  if not v then
    table[key] = default
    v = default
  end
  return v
end

-- Given the `root` of a tree of tables,
--
-- Returns the node sitting at the `path`, which should be
-- an array of keys.
--
-- Returns nil if the path cannot be fully traversed
local function node_from_path(root, path)
  local cursor = root

  for _, key in ipairs(path) do
    -- Try to traverse further into the path.
    -- This means we *need* something that can traversed.
    -- In lua, the only thing we can traverse is a table.
    -- So if we're not looking at a table, we've failed
    -- traversing the path.
    if type(cursor) ~= "table" then
      return nil
    end

    local candidate = cursor[key]
    cursor = candidate
  end

  return cursor
end

local get_in = node_from_path

-- Alias for better code clarity
local table_push = table.insert
local table_pop = table.remove
local function table_get_last(t)
  return t[#t]
end

local function table_clone(t)
  return {table.unpack(org)}
end


-- Given a `root` and the `target_node` we're looking for,
-- Return the path of the first occurance of the node.
-- Returns nil if the node cannot be found
--
-- Note that only the node/table pointer is being compared here.
local function path_from_node_compare(root, target_node, compare_fn)
  local path = {}

  local depth_first_match
  depth_first_match = function(cur_node)
    if compare_fn(cur_node, target_node) then
      return true
    end

    -- If we can traverse further into the tree...
    if type(cur_node) ~= "table" then
      return false
    end

    -- Check each child...
    for k, v in pairs(cur_node) do
      table_push(path, k)

      -- If we found a match, return immediately without messing up
      -- the path that has been accumulated
      local match = depth_first_match(v)
      if match == true then
        return match
      end
      table_pop(path)
    end
  end

  local result = depth_first_match(root)
  if result then
    return path
  else
    return nil
  end
end


local function path_from_node(root, target_node)
  return path_from_node_compare(root, target_node,
    function(cur_node, target_node)
      if cur_node == target_node then
        return true
      else
        return false
      end
    end)
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


-- Make sure we have at least `lineno` lines in the buffer
-- This helps when we're trying to insert lines at a position beyond the
-- current end of the buffer
local function buf_padlines_to(buf, lineno)
  local count = api.nvim_buf_line_count(buf)
  if (lineno > count) then
    local empty_lines = {}
    for _ = 1, lineno-count do
      table.insert(empty_lines, "")
    end
    api.nvim_buf_set_lines(buf, count, count, true, empty_lines)
  end
end

local function partition(table, tuple_size, step)
  local result = {}

  if not step then
    step = tuple_size
  end

  for i = 1, #table-tuple_size+1, step do
    local tuple = {}
    for j = 0, tuple_size-1 do
      table_push(tuple, table[i+j])
    end
    table_push(result, tuple)
  end
  return result
end

local function partition_iterator(table, tuple_size, step)
  local t_size = #table
  if not step then
    step = tuple_size
  end
  local v = 1-step

  return function()
    v = v+step
    local end_idx = v + tuple_size-1

    -- Can we construct more tuples starting from the requested position?
    if end_idx > t_size then
      return nil
    end

    -- If so, grab all items into a tupe and return it unpacked
    local result = {}
    for i = v, end_idx do
      table_push(result, table[i])
    end
    return unpack(result)
  end
end

-- Returns a new table with that contains all items where the predicate returned true
local function filter(table, pred)
  local result = {}
  for _, v in ipairs(table) do
    if pred(v) then
      table_push(result, v)
    end
  end
  return result
end

-- Applies `func` to each value in the table
-- Note that this alters the values in-place
local function map(table, func)
  for i, v in ipairs(table) do
    table[i] = func(v)
  end
  return table
end

local function remove_trailing_newlines(str)
  return string.gsub(str, "[\r\n]+$", "")
end

return {
  lines = lines,
  lines_array = lines_array,
  system_async = system_async,
  node_from_path = node_from_path,
  get_in = node_from_path,
  path_from_node = path_from_node,
  table_depth_first_visit = table_depth_first_visit,
  table_lazy_get = table_lazy_get,
  table_find_node = table_find_node,
  table_push = table_push,
  table_pop = table_pop,
  table_get_last = table_get_last,
  table_clone = table_clone,
  buf_padlines_to = buf_padlines_to,
  partition = partition,
  partition_iterator = partition_iterator,
  filter = filter,
  map = map,
  remove_trailing_newlines = remove_trailing_newlines,
}
