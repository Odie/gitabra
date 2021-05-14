local u = require("gitabra.util")

local M = {}

local default_config = {
  disclosure_sign = {
    -- ">": Unicode: U+003E, UTF-8: 3E
    collapsed = ">",

    -- "⋁": Unicode U+22C1, UTF-8: E2 8B 81
    expanded = "⋁"
  }
}

local config = u.table_copy_into_recursive({}, default_config)
M.config = config

function M.setup(opts)
  config = u.table_copy_into_recursive({}, default_config, opts)
  M.config = config;
end

return M
