-- Taken from PIL: http://www.lua.org/pil/11.4.html
List = {}
List.__index = List

function List.new()
  return setmetatable({first = 0, last = -1}, List)
end

function List.push_left(list, value)
  local first = list.first - 1
  list.first = first
  list[first] = value
end

function List.push_right(list, value)
  local last = list.last + 1
  list.last = last
  list[last] = value
end

function List.pop_left(list)
  local first = list.first
  if first > list.last then error("list is empty") end
  local value = list[first]
  list[first] = nil        -- to allow garbage collection
  list.first = first + 1
  return value
end

function List.pop_right(list)
  local last = list.last
  if list.first > last then error("list is empty") end
  local value = list[last]
  list[last] = nil         -- to allow garbage collection
  list.last = last - 1
  return value
end

function List.is_empty(list)
  if list.first - 1 == list.last then
    return true
  else
    return false
  end
end

return List
