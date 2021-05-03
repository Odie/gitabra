-- A promise is a point of coordination for a computation result that will be
-- delivered some time in the future.  We're not saying anything about how the
-- computation is performed.  This is closer to clojure's idea of a `promise`.
--
-- In gitabra, this is used to help flatten out computation that may return
-- some value at a future time. This can be used to help to wait on calls to
-- `util.system` and other async computations in the same way.
--
-- The idea is that after setting up any long running computation, we'd wait on
-- one or more of them to be completed before proceeding with the rest of the
-- program in a linear fashion.
--

local Promise = {}
Promise.__index = Promise

function Promise.new(o)
  return setmetatable(o, Promise)
end

function Promise:deliver(v)
  if not self.realized then
    self.value = v
    self.realized = true
  end
end

function Promise:is_realized()
  return self.realized
end

function Promise:wait_for(ms, predicate)
  return vim.wait(ms,
    function()
      return predicate(self)
    end
    , 5)
end

-- Wait for a promise to be delivered
function Promise:wait(ms)
  return vim.wait(ms,
    function()
      return self.realized
    end, 5)
end

-- Wait for multiple promises to be delivered
function Promise.wait_all(promises, ms)
  return vim.wait(ms,
    function()
      for _, j in pairs(promises) do
        if not j.realized then
          return false
        end
      end
      return true
    end, 5)
end

return Promise
