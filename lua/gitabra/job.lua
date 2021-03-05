-- Adapted from https://github.com/TravonteD/luajob
local M = {}
M.__index = M

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

function M.new(o)
  setmetatable(o, M)
  return o
end

function M:send(data)
  self.stdin:write(data)
  self.stdin:shutdown()
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
  else
    args = shallow_copy(self.cmd)
  end

  options.command = table.remove(args, 1)
  options.args = args

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
    vim.schedule_wrap(wrap_ctx(self, self.shutdown)))
  if self.on_stdout then
      self.stdout:read_start(vim.schedule_wrap(wrap_ctx(self, self.on_stdout)))
  end
  if self.on_stderr then
      self.stderr:read_start(vim.schedule_wrap(wrap_ctx(self, self.on_stderr)))
  end
end

function M.are_jobs_done(jobs)
  -- If any of the jobs are not done yet,
  -- we're not done
  for _, j in pairs(jobs) do
    if j.done == false then
      return false
    end
  end

  -- All of the jobs are done...
  return true
end

-- Wait up to `ms` approximately milliseconds until all the jobs are done
function M.wait_all(ms, jobs)
  return vim.wait(ms,
    function()
      return M.are_jobs_done(jobs)
    end, 5)
end

return M
