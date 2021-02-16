local job = require("gitabra.job")


-- Execute the given command asynchronously
--
local function system_async(cmd)
  local result = {
    output = {},
    done = false
  }

	local j = job:new({
			cmd = cmd,
    	on_stdout = function(self, err, data)
      	if err then
        	print("ERROR: "..err)
      	end
      	if data then
      	  print("got data: ", data)
      	  table.insert(result.output, data)
      	end
    	end,
    	on_exit = function(self, err, data)
    	  result.done = true
    	end
  	})
	j:start()

	result.job = j
	return result
end



local function git_status()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)

  local r = system_async('git show --no-patch --format="%h %s"')

  vim.wait(100, function()
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, r.output)
  end)
end

return {git_status = git_status}

--------------------------
--Example code
  -- Setup a job to stream the contents of git-status to a new buffer
  -- local buf = vim.api.nvim_create_buf(true, false)
	-- local j = job:new({
	-- 		cmd = "git status",
  --   	on_stdout = function(self, err, data)
  --     	if err then
  --       	print("ERROR: "..err)
  --     	end
  --     	if data then
  --       	for s in lines(data) do
  --         	vim.api.nvim_buf_set_lines(buf, -1, -1, false, {s})
  --       	end
  --     	end
  --   	end,
  -- 	})
	-- j:start()
