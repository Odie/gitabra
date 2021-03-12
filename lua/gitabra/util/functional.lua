local function ident(a)
  return a
end

-- Returns a new table with that contains all items where the predicate returned true
local function filter(t, pred)
  local result = {}
  for _, v in ipairs(t) do
    if pred(v) then
      table.insert(result, v)
    end
  end
  return result
end

-- Applies `func` to each value in the table
-- Note that this alters the values in-place
local function map(t, func)
  for i, v in ipairs(t) do
    t[i] = func(v)
  end
  return t
end

return {
  ident = ident,
  filter = filter,
  map = map,
}
