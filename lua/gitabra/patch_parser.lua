local lpeg = require("lpeg")
local u = require("gitabra.util")
local bit = require("bit")

local function diff_iter(text, index)
  local s, e
  if index == 0 then
    s, e =  text:find("^diff %-%-git a/.- b/.-\n", index+1)
  else
    s, e =  text:find("\ndiff %-%-git a/.- b/.-\n", index+1)
    if s then
      s = s + 1
    end
  end
  return e, s, e
end

local function diff_indices(text_in)
  return diff_iter, text_in, 0
end

local function hunk_iter(text, index)
  local s, e = text:find("\n@@ [+-]?%d+,[+-]?%d+ [+-]?%d+,[+-]?%d+ @@", index+1)
  if s == nil then
    return e, s, e
  else
    return e, s+1, e
  end
end

local function hunk_indices(text_in)
  return hunk_iter , text_in, 0
end

-- Locates where file diffs and hunks and their starting positions
local function patch_locate_headers(patch_text)
  local result = {}

  local text = patch_text
  local diff_fn = diff_indices(text)
  local hunk_fn = hunk_indices(text)

  local cur_diff
  local d_cursor = 0
  local d_start, d_end, d_next_start
  local h_cursor = 0
  local h_start, h_end

  local next_hunk = 1
  local next_diff = 2

  local process_entries
  process_entries = function (actions)

    -- Retrieve the next file diff if asked
    if bit.band(actions, next_diff) ~= 0 then

      d_cursor, d_start, d_end = diff_fn(text, d_cursor)
      if not d_cursor then
        result.error = "expected more diffs, but found none"
        return result
      end

      -- Accumulate into result, the newly found file diff
      cur_diff = {
        match_start = d_start,
        match_stop = d_end,
        hunks = {}
      }
      table.insert(result, cur_diff)

      -- Figure out where the next file diff starts
      d_cursor, d_next_start, _ = diff_fn(text, d_cursor)
    end

    -- Retrieve the next hunk if asked
    if bit.band(actions, next_hunk) ~= 0 then
      h_cursor, h_start, h_end = hunk_fn(text, h_cursor)
      if not h_start then
        return result
      end

      -- If the hunk seems to belong to the next file diff...
      -- Move on to the next file diff
      if d_next_start and h_start >= d_next_start then
        d_cursor = d_next_start -100
        return process_entries(next_diff)
      end
    end

    -- We've located a hunk that belongs to the current diff
    -- Attach the hunk
    local cur_hunk = {
      match_start = h_start,
      match_stop = h_end,
      text = string.sub(text, h_start, h_end)
    }
    table.insert(cur_diff.hunks, cur_hunk)

    -- Move on to the next hunk
    return process_entries(next_hunk)
  end

  return process_entries(next_diff + next_hunk)
end

-- Given the patch as text, return a collection that describes
-- the contained file diffs and hunks.
local function patch_info(patch_text)
  local text = patch_text
  if text == nil then
    return {}
  end

  local headers = patch_locate_headers(patch_text)
  local result = {}
  for i, diff_header in ipairs(headers) do
    local diff = {
      header_start = diff_header.match_start,
      content_start = diff_header.match_stop,
      hunks = {}
    }
    diff.a_file, diff.b_file = string.match(text, "diff %-%-git a/(.-) b/(.-)\n", diff_header.match_start)
    table.insert(result, diff)

    if i ~= #headers then
      diff.content_end = headers[i+1].match_start-1
    else
      diff.content_end = #patch_text
    end

    for j, hunk_header in ipairs(diff_header.hunks) do
      local hunk = {
        header_text = hunk_header.text,
        header_start = hunk_header.match_start,
        content_start = hunk_header.match_stop+2,
      }
      if j ~= #diff_header.hunks then
        hunk.content_end = diff_header.hunks[j+1].match_start-2
      else
        hunk.content_end = diff.content_end
      end
      table.insert(diff.hunks, hunk)
      -- hunk.text = string.sub(text, hunk.content_start, hunk.content_end)
    end
  end

  return result
end

-- Given the an output from `patch_info`,
-- return a file diff entry that matches given `filepath`
local function find_file(infos, filepath)
  for _, hunk in ipairs(infos) do
    if hunk.b_file == filepath then
      return hunk
    end
  end
end

return {
  hunk_indices = hunk_indices,
  diff_indices = diff_indices,
  patch_info = patch_info,
  find_file = find_file,
}
