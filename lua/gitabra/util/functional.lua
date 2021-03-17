local function ident(a)
  return a
end

local function filter_iter(t, iter, pred)
  local result = {}
  for _, v in iter(t) do
    if pred(v) then
      table.insert(result, v)
    end
  end
  return result
end

-- Returns a new table with that contains all items where the predicate returned true
local function filter(t, pred)
  return filter_iter(t, ipairs, pred)
end

local function filter_kv(t, pred)
  return filter_iter(t, pairs, pred)
end

-- Applies `func` to each value in the table
-- Note that this alters the values in-place
local function map(t, func, ...)
  for i, v in ipairs(t) do
    t[i] = func(v, ...)
  end
  return t
end

local function reduce(t, func, accum)
  if accum then
    for _, v in ipairs(t) do
      accum = func(accum, v)
    end
  else
    -- In the case where has not been provided, try to use the first item
    -- as the initial accum value, then resume the rest of the for-loop.
    --
    -- We're using a slightly altered version of lua's "generic for" here.
    local _f, _s, _var = ipairs(t)
    local i, v = _f(_s, _var)
    _var = i
    accum = v
    if _var ~= nil then
      while true do
        i, v = _f(_s, _var)
        _var = i
        if _var == nil then break end
        accum = func(accum, v)
      end
    end
  end
  return accum
end

local function reduce_kv(t, func, accum)
  for k, v in ipairs(t) do
    accum = func(accum, k, v)
  end

  return accum
end

return {
  ident = ident,
  filter_iter = filter_iter,
  filter = filter,
  filter_kv = filter_kv,
  map = map,
  reduce = reduce,
  reduce_kv = reduce_kv,
}
