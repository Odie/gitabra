local job = require('gitabra.job')
local chronos = require('chronos')

-- Returns an iterator over each line in `str`
local function lines(str)
  return str:gmatch("[^\r\n]+")
end

-- Execute the given command asynchronously
-- Returns a `results` table.
-- `done` field indicates if the job has finished running
-- `output` table stores the output of the executed command
-- `job` field contains a `gitabra.job` object used to run the command
--
local function system_async(cmd)
  local result = {
    output = {},
    done = false
  }

	local j = job.new({
			cmd = cmd,
    	on_stdout = function(_, err, data)
      	if err then
        	print("ERROR: "..err)
      	end
      	if data then
      	  for line in lines(data) do
       	    table.insert(result.output, line)
        	end
      	end
    	end,
    	on_exit = function(_, _, _)
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

-- Alias for better code clarity
local table_push = table.insert
local table_pop = table.remove


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


return {
  system_async = system_async,
  node_from_path = node_from_path,
  path_from_node = path_from_node,
  path_from_node_compare = path_from_node_compare,
}
