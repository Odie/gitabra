-- Adapted from https://github.com/ms-jpq/neovim-async-tutorial
local co = coroutine
local uv = vim.loop

-- In libuv async style programming, a function signature usually looks like:
--   function(param1, param2..., callback)
-- The idea when the function is called is that an operation will be kicked
-- off with an unknown completion time. *When* it is completed, the supplied
-- callback function will be fired.
--
-- To flatten out the callbacks, we use Lua's coroutine and define a `step`
-- function that does the following:
--   - resume coroutine/thread
--   - get back the next thunk to be executed (and waited on libuv style)
--   - execute it and supply it with the `step` function as a callback
--
-- This way, we're either immediately executing some lua code, or returning
-- a thunk to be executed and waited upon using the step function.
--

-- use with wrap
local function pong(func, callback)
  assert(type(func) == "function", "type error :: expected func")
  local thread = co.create(func)

  local step = nil

  -- This step function will be passed around an used as the
  -- function to call when
  step = function(...)
    -- We are going to be locked in a sort of co-recursive loop here.
    -- Here, we're going to repeated resume the coroutine...
    local stat, ret = co.resume(thread, ...)
    assert(stat, ret)

    -- If the thread is done...
    if co.status(thread) == "dead" then
      -- Call the supplied `callback`
      (callback or function () end)(ret)
    else
      -- If the thread is not done yet...
      -- Someone should have passed back another thunk to us, sent via
      -- an `await` call.
      assert(type(ret) == "function", "type error :: expected func")

      -- Execute the given thunk.
      -- Note that we're giving it the step function here.
      ret(step)
    end
  end

  -- Start step function chain
  -- We will not return from this function call until the coroutine
  -- is says it has finished running.
  step()
end


-- Wrap any function that accepts a callback into a thunk
-- Returns a function of the same signature, sans the callback.
--
-- When the returned function is called, we're basically performing a
-- partial function application of all params except the last,
-- which would be a callback function.
--
-- This "thunk" is then waited/yielded on, it is received by the
-- step function, which will then bind the last param and execute the
-- thunk.
local function wrap(func)
  assert(type(func) == "function", "type error :: expected func")
  return function (...)
    local params = {...}

    -- The thunk will be called/resumed
    local thunk = function (step)
      table.insert(params, step)
      return func(unpack(params))
    end
    return thunk
  end
end


-- many thunks -> single thunk
local function join(thunks)
  local len = table.getn(thunks)
  local done = 0
  local acc = {}

  local thunk = function (step)
    if len == 0 then
      return step()
    end
    for i, tk in ipairs(thunks) do
      assert(type(tk) == "function", "thunk must be function")
      local callback = function (...)
        acc[i] = {...}
        done = done + 1
        if done == len then
          step(unpack(acc))
        end
      end
      tk(callback)
    end
  end
  return thunk
end


-- sugar over coroutine
local function await(defer)
  assert(type(defer) == "function", "type error :: expected func")
  return co.yield(defer)
end


local function await_all(defer)
  assert(type(defer) == "table", "type error :: expected table")
  return co.yield(join(defer))
end

local sleep_ms = function(ms, callback)
  local timer = uv.new_timer()
  uv.timer_start(timer, ms, 0, function ()
    uv.timer_stop(timer)
    uv.close(timer)
    callback()
  end)
end

local function main_loop(f)
  vim.schedule(f)
end

return {
  sync = wrap(pong),
  wait = await,
  wait_all = await_all,
  wrap = wrap,
  sleep_ms = wrap(sleep_ms),
  main_loop = main_loop,
}
