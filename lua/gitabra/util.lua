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

return {system_async = system_async}
