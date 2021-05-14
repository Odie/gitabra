local M = {}

local function require_or_nil(req_path)
  local status, result = pcall(require, req_path)
  if not status then
    print(result)
    return nil
  else
    return result
  end
end

local function export(export_table, export_targets)
  for _, item in ipairs(export_targets) do
    local module = require_or_nil(item[1])
    if module then
      export_table[item[2]] = module[item[2]]
    end
  end
end

export(M, {
  {'gitabra.git_status', 'gitabra_status'},
  {'gitabra.config', 'setup'}
})

if vim.g.gitabra_dev == 1 then
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

  M.reload = reload
  vim.api.nvim_set_keymap('n', ',r', '<cmd>lua require("gitabra").reload()<cr>', {})
  vim.api.nvim_set_keymap('n', ',gs', '<cmd>lua require("gitabra").gitabra_status()<cr>', {})
  vim.api.nvim_set_keymap('n', ',gl', '<cmd>lua print(vim.inspect(package.loaded["gitabra"]))<cr>', {})
end

return M
