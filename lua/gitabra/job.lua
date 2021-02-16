-- Adapted from https://github.com/TravonteD/luajob
local M = {}

local function shallow_copy(t)
  local t2 = {}
  for k,v in pairs(t) do
    t2[k] = v
  end
  return t2
end

local function close_safely(handle)
  if not handle:is_closing() then
      handle:close()
  end
end

local function wrap_ctx(ctx, callback)
  return function(err, data)
    callback(ctx, err, data)
  end
end

function M:new(o)
  o = o or {}
  for n,f in pairs(o) do
    self[n] = f
  end
  setmetatable(o, self)
  self.__index = self
  return o
end

function M:send(data)
  M.stdin:write(data)
  M.stdin:shutdown()
end

function M:stop()
  close_safely(self.stdin)
  close_safely(self.stderr)
  close_safely(self.stdout)
  close_safely(self.handle)
end

function M:shutdown(code, signal)
  if self.on_exit then
    self:on_exit(code, signal)
  end
  if self.on_stdout then
      self.stdout:read_stop()
  end
  if self.on_stderr then
      self.stderr:read_stop()
  end
  self:stop()
end

function M:options()
  local options = {}

  self.stdin = vim.loop.new_pipe(false)
  self.stdout = vim.loop.new_pipe(false)
  self.stderr = vim.loop.new_pipe(false)

  local args
  if type(self.cmd) == "string" then
    args = vim.fn.split(self.cmd, ' ')
    print("options got a string as a command")
  else
    args = shallow_copy(self.cmd)
    print("options got something else as a command")
  end
  print("args: ", vim.inspect(args))

  options.command = table.remove(args, 1)
  options.args = args
  print("options: ", vim.inspect(options))

  options.stdio = {
    self.stdin,
    self.stdout,
    self.stderr
  }

  if self.cwd then
    options.cwd = self.cwd
  end

  if self.env then
    options.env = self.env
  end

  if self.detach then
    options.detach = self.detach
  end

  return options
end

function M:start()
  local options = self:options()
  self.handle = vim.loop.spawn(options.command,
    options,
    vim.schedule_wrap(wrap_ctx(self, M.shutdown)))
  if self.on_stdout then
      self.stdout:read_start(vim.schedule_wrap(wrap_ctx(self, M.on_stdout)))
  end
  if self.on_stderr then
      self.stderr:read_start(vim.schedule_wrap(wrap_ctx(self, M.on_stderr)))
  end
end
return M
