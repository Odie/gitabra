local plugin_name = 'gitabra'

local function unload()
	local dir = plugin_name .. "/"
	local dot = plugin_name .. "."
	for key in pairs(package.loaded) do
  	if (vim.startswith(key, dir) or vim.startswith(key, dot) or key == plugin_name) then
    	package.loaded[key] = nil
  		print("Unloaded: ", key)
  	end
	end
end

local function reload()
	unload()
	require(plugin_name)
end

local M = {
	gitabra_status = require('gitabra.git_status').gitabra_status
}

if vim.g.gitabra_dev == 1 then
	M.reload = reload
  vim.api.nvim_set_keymap('n', ',r', '<cmd>lua require("gitabra").reload()<cr>', {})
  vim.api.nvim_set_keymap('n', ',gs', '<cmd>lua require("gitabra").git_status()<cr>', {})
  vim.api.nvim_set_keymap('n', ',gl', '<cmd>lua print(vim.inspect(package.loaded["gitabra"]))<cr>', {})
end

return M