local M = {}
M.__index = M


local function get_node_path(self, node)
end

local function request_content(self, node)
  if self.on_content_request then

  end
end

function M.new(o)
  o.root = o.root or {}
  o.buffer = o.buffer or vim.api.nvim_create_buf(true, false)
  setmetatable(o, M)
  return o
end

function M:add_node(path, node_entry)

end

return M
