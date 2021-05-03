-- Meant to work with content returned by libuv.
-- Sometimes, `on_stdout` returns the result of running programs in
-- smaller chunks that do not break at newline boundaries. In particular,
-- this happens when we ask git for a file that is slightly large.

local M = {}
M.__index = M

function M.new(pattern)
  local o = {
    pending = nil,
    result = {},
    pattern = pattern,
  }
  setmetatable(o, M)
  return o
end

local function insert_result(self, str)
  if self.pending then
    table.insert(self.result, self.pending .. str)
    self.pending = nil
  else
    table.insert(self.result, str)
  end
end

local function store_pending(self, str)
  if self.pending then
    self.pending = self.pending .. str
  else
    self.pending = str
  end
end

function M:add(str)
  local last_e = 0
  local s = 0
  local e = 0
  while true do
    s, e = string.find(str, self.pattern, e+1)

    -- No more matches...
    -- Put all contents from the end of the last match up to end of string into tokens
    if s == nil then
      if last_e ~= string.len(str) then
        store_pending(self, string.sub(str, last_e+1, string.len(str)))
      end
      break

    -- If the next match came immediately after the last_e,
    -- we've encountered a case where two deliminator patterns were placed side-by-side.
    -- Place an empty string in the tokens array to indicate an empty field was found
    elseif last_e+1 == s then
      insert_result(self, "")

    -- Otherwise, extract all string contents starting from the last_e up to where this
    -- match was found
    else
      insert_result(self, string.sub(str, last_e+1, s-1))
    end
    last_e = e
  end
end

function M:stop()
  if self.pending then
    table.insert(self.result, self.pending)
    self.pending = nil
  end
end

return M
