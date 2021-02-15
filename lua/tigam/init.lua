local function hello()
		print("hello world")
end

local function reload()
	local plugin_name = 'tigam'
	local dir = plugin_name .. "/"
	local dot = plugin_name .. "."
	for key in pairs(package.loaded) do
  	if (vim.startswith(key, dir) or vim.startswith(key, dot) or key == plugin_name) then
    	package.loaded[key] = nil
  		print("Unloaded: ", key)
  	end
	end
end

local M = {
	hello = hello
}

if vim.g.tigma_dev == 1 then
	M.reload = reload
  vim.api.nvim_set_keymap('n', ',r', '<cmd>lua require("tigam").reload()<cr>', {})
  vim.api.nvim_set_keymap('n', ',t', '<cmd>lua require("tigam").hello()<cr>', {})
end

return M
