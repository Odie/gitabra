local job = require('gitabra.job')
local api = vim.api
local ut = require('gitabra.util.table')
local a = require('gitabra.async')
local promise = require('gitabra.promise')
local uf = require('gitabra.util.functional')
local splitter = require('gitabra.util.string_splitter')

-- Returns an iterator over each line in `str`
-- Note that this will eat empty lines
-- TODO: Modify this to process empty lines correctly
local function lines(str)
  return str:gmatch("[^\r\n]+")
end

local function lines_array(str)
  local result = {}
  for line in lines(str) do
    table.insert(result, line)
  end
  return result
end

local function interp(s, params)
  return (s:gsub('($%b{})', function(w) return params[w:sub(3, -2)] or w end))
end

local function string_split_by_pattern(str, pattern)
  local tokens = {}
  local last_e = 0
  local s = 0
  local e = 0
  while true do
    s, e = string.find(str, pattern, e+1)

    -- No more matches...
    -- Put all contents from the end of the last match up to end of string into tokens
    if s == nil then
      if last_e ~= string.len(str) then
        table.insert(tokens, string.sub(str, last_e+1, string.len(str)))
      end
      break

    -- If the next match came immediately after the last_e,
    -- we've encountered a case where two deliminator patterns were placed side-by-side.
    -- Place an empty string in the tokens array to indicate an empty field was found
    elseif last_e+1 == s then
      table.insert(tokens, "")

    -- Otherwise, extract all string contents starting from the last_e up to where this
    -- match was found
    else
      table.insert(tokens, string.sub(str, last_e+1, s-1))
    end
    last_e = e
  end

  return tokens
end

local function nanotime()
  return vim.loop.hrtime() / 1000000000
end

-------------------------------------------------------------------------------
-- Running programs in a separate process
--
-- This works a bit like neovim's job controls system, but built
-- directly over vim.loop in lua.

-- Execute the given command asynchronously
-- Returns a `results` table.
-- `done` field indicates if the job has finished running
-- `output` table stores the output of the executed command
-- `job` field contains a `gitabra.job` object used to run the command
--
local function system(cmd, opt, callback)
  local result = {
    output = {},
    err_output = {},
    done = false
  }
  opt = opt or {}
  if opt.split_lines then
    result.stdout_splitter = splitter.new("\n")
    result.stderr_splitter = splitter.new("\n")
  end


  local j = job.new({
      cmd = cmd,
      opt = opt,
      on_stdout = function(_, err, data)
        if err then
          print("ERROR: "..err)
        end
        if data then
          if opt.split_lines then
            result.stdout_splitter:add(data)
            if not ut.table_is_empty(result.stdout_splitter.result) then
              ut.table_concat(result.output, result.stdout_splitter.result)
              result.stdout_splitter.result = {}
            end
          else
            table.insert(result.output, data)
          end
        end
      end,
      on_stderr = function(_, err, data)
        if err then
          print("ERROR: "..err)
        end
        if data then
          if opt.split_lines then
            result.stdout_splitter:add(data)
            if not ut.table_is_empty(result.stdout_splitter.result) then
              ut.table_concat(result.output, result.stdout_splitter.result)
              result.stdout_splitter.result = {}
            end
          else
            table.insert(result.err_output, data)
          end
        end
      end,
      on_exit = function(_, code, _)
        if opt.split_lines then
          result.stdout_splitter:stop()
          ut.table_concat(result.output, result.stdout_splitter.result)

          result.stderr_splitter:stop()
          ut.table_concat(result.err_output, result.stderr_splitter.result)
        elseif opt.merge_output and #result.output > 1 then
          result.output = { table.concat(result.output) }
        end
        result.exit_code = code
        result.done = true
        result.stop_time = nanotime()
        result.elapsed_time = result.stop_time - result.start_time
        if callback then
          callback(result)
        end
      end
    })

  result.start_time = nanotime()
  j:start()

  result.job = j
  return result
end

-- A version of `system` meant to work with async mechanims of `gitabra.async`
local system_async = a.wrap(system)

-- Returns the `system` call as a promise.
local function system_as_promise(cmd, opt, p)
  p = p or promise.new({})
  p.job = system(cmd, opt, function(j) p:deliver(j.output) end)
  return p
end

local function system_job_is_done(j)
  return j.done
end

local function system_jobs_are_done(jobs)
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

-- Wait until either `ms` has elapsed or when `predicate` returns true
local function system_job_wait_for(j, ms, predicate)
  return vim.wait(ms, predicate, 5)
end

local function system_job_wait(j, ms)
  return vim.wait(ms,
    function()
      return j.done
    end, 5)
end

-- Wait up to `ms` approximately milliseconds until all the jobs are done
function system_job_wait_all(jobs, ms)
  return vim.wait(ms,
    function()
      return M.are_jobs_done(jobs)
    end, 5)
end


-- Given the `root` of a tree of tables,
--
-- Returns the node sitting at the `path`, which should be
-- an array of keys.
--
-- Returns nil if the path cannot be fully traversed
local function node_from_path(root, path)
  local cursor = root

  for _, key in ipairs(path) do
    -- Try to traverse further into the path.
    -- This means we *need* something that can traversed.
    -- In lua, the only thing we can traverse is a table.
    -- So if we're not looking at a table, we've failed
    -- traversing the path.
    if type(cursor) ~= "table" then
      return nil
    end

    local candidate = cursor[key]
    cursor = candidate
  end

  return cursor
end

local get_in = node_from_path

-- Given a `root` and the `target_node` we're looking for,
-- Return the path of the first occurance of the node.
-- Returns nil if the node cannot be found
--
-- Note that only the node/table pointer is being compared here.
local function path_from_node_compare(root, target_node, compare_fn)
  local path = {}

  local depth_first_match
  depth_first_match = function(cur_node)
    if compare_fn(cur_node, target_node) then
      return true
    end

    -- If we can traverse further into the tree...
    if type(cur_node) ~= "table" then
      return false
    end

    -- Check each child...
    for k, v in pairs(cur_node) do
      ut.table_push(path, k)

      -- If we found a match, return immediately without messing up
      -- the path that has been accumulated
      local match = depth_first_match(v)
      if match == true then
        return match
      end
      ut.table_pop(path)
    end
  end

  local result = depth_first_match(root)
  if result then
    return path
  else
    return nil
  end
end


local function path_from_node(root, target_node)
  return path_from_node_compare(root, target_node,
    function(cur_node, target_node)
      if cur_node == target_node then
        return true
      else
        return false
      end
    end)
end

-- Make sure we have at least `lineno` lines in the buffer
-- This helps when we're trying to insert lines at a position beyond the
-- current end of the buffer
local function buf_padlines_to(buf, lineno)
  local count = api.nvim_buf_line_count(buf)
  if (lineno > count) then
    local empty_lines = {}
    for _ = 1, lineno-count do
      table.insert(empty_lines, "")
    end
    api.nvim_buf_set_lines(buf, count, count, true, empty_lines)
  end
end

local function partition(table, tuple_size, step)
  local result = {}

  if not step then
    step = tuple_size
  end

  for i = 1, #table-tuple_size+1, step do
    local tuple = {}
    for j = 0, tuple_size-1 do
      ut.table_push(tuple, table[i+j])
    end
    ut.table_push(result, tuple)
  end
  return result
end

local function partition_iterator(table, tuple_size, step)
  local t_size = #table
  if not step then
    step = tuple_size
  end
  local v = 1-step

  return function()
    v = v+step
    local end_idx = v + tuple_size-1

    -- Can we construct more tuples starting from the requested position?
    if end_idx > t_size then
      return nil
    end

    -- If so, grab all items into a tupe and return it unpacked
    local result = {}
    for i = v, end_idx do
      ut.table_push(result, table[i])
    end
    return unpack(result)
  end
end

local function remove_trailing_newlines(str)
  local result, _ = string.gsub(str, "[\r\n]+$", "")
  return result
end

local function trim(str)
  return string.match(str, "^[\n\r%s]*(.-)[\n\r%s]*$")
end

local function selected_region()
  return {vim.fn.line("v")-1, vim.fn.line(".")-1}
end

local function within_region(region, lineno)
  if region[1] <= lineno and lineno <= region[2] then
    return true
  else
    return false
  end
end

local function git_root_dir_p()
  return system_as_promise("git rev-parse --show-toplevel", {split_lines=true})
end

local function git_root_dir()
  local p = git_root_dir_p()
  p:wait(500)
  return p.job.output[1]
end

local function git_dot_git_dir()
  return git_root_dir() .. "/.git"
end

local function str_is_empty(str)
  return str == nil or str == ""
end

local function str_is_really_empty(str)
  if str_is_empty(str) then
    return true
  end

  if string.match(str, "^%s*$") then
    return true
  end

  return false
end

local function first_nonwhitespace_idx(str)
  return string.find(str, "[^%s]")
end

local function nvim_commands(str, strip_leading_whitespace)
  if not strip_leading_whitespace then
    for line in lines(str) do
      print(line)
    end
  else
    local idx = -1

    for line in lines(str) do
      local empty = str_is_really_empty(line)
      if idx == -1 and not empty then
        idx = first_nonwhitespace_idx(str)
      end
      vim.cmd(line:sub(idx))
    end
  end
end

local function math_clamp(v, min_val, max_val)
  return math.min(math.max(v, min_val), max_val)
end

local function markup_fn(m)
  m.type = "markup"
  return m
end

local function is_markup(markup)
  if type(markup) == "table" and markup.type == "markup" then
    return true
  else
    return false
  end
end

-- Given a `markup` that represents a string with text with highlghts on specific sections,
-- Construct the entire string itself, and the locations on the string where highlights should start and stop
local function markup_flatten(markup, concat_separator)
  local text = {}
  local hl = {}

  -- If we're called with a string,
  -- return a dummy result that we can still process like a markup.
  if type(markup) == "string" then
    return {text=markup, hl=hl}
  end

  local sep_len = 0
  if concat_separator then
    sep_len = concat_separator:len()
  end

  local cursor = 0
  for _, item in ipairs(markup) do
    if type(item) == "string" then
      table.insert(text, item)
      cursor = cursor + item:len()
    elseif type(item) == "table" then
      table.insert(text, item.text)
      local start = cursor
      cursor = cursor + item.text:len()
      table.insert(hl, {
          start = start,
          stop = cursor,
          group = item.group
      })
    end
    cursor = cursor + sep_len
  end

  return {text=table.concat(text, concat_separator), hl=hl}
end

local function nvim_synIDattr(synID, what, mode)
  if not mode then
    return api.nvim_eval(string.format("synIDattr(%i,'%s')", synID, what))
  else
    return api.nvim_eval(string.format("synIDattr(%i,'%s','%s')", synID, what, mode))
  end
end


local function hl_group_attrs(group_name, target_attrs)
  local hl_group_id = api.nvim_get_hl_id_by_name(group_name)
  if not target_attrs then
    target_attrs = {
      {"fg", "gui"},
      {"bg", "gui"},
      {"fg", "cterm"},
      {"bg", "cterm"},
    }
  end

  -- Fetch highlight group attributes
  -- Only keep entries that returned non-emtpy values
  local attrs = {}
  for _, item in ipairs(target_attrs) do
    local val = nvim_synIDattr(hl_group_id, unpack(item))
    if not str_is_empty(val) then
      attrs[string.format("%s%s", item[2], item[1])] = val
    end
  end
  return attrs
end

local function hl_group_attrs_to_str(attrs)
  local result = {}
  for k, v in pairs(attrs) do
    table.insert(result, string.format("%s=%s", k, v))
  end
  return table.concat(result, " ")
end

local function nvim_line_zero_idx(place)
  return vim.fn.line(place)-1
end

local function zipper_picks_by_type(z_in)
  local z = z_in:clone()
  local picks = {}
  local node = z:node()

  while true do
    if node.type then
      picks[node.type] = node
    end
    if not z:up() then
      break
    end
    node = z:node()
  end

  return picks
end

local function git_shorten_sha(sha)
  return string.sub(sha, 1, 7)
end

local function call_or_print_stacktrace(func, ...)
  local ok, res = xpcall(func, debug.traceback, ...)
  if not ok then
    print(res)
    return nil
  else
    return res
  end
end

local function wrap__call_or_print_stacktrace(func)
  return function(...)
    return call_or_print_stacktrace(func, ...)
  end
end

local function filter_empty_strings(strs)
  return uf.filter(strs, function(s) return not str_is_empty(s) end)
end

local function array_remove_trailing_empty_lines(strs)
  local last
  for cursor = #strs, 1, -1 do
    if not str_is_empty(strs[cursor]) then
      last = cursor
      break
    end
  end

  if last == nil then
    return {}
  else
    return ut.table_slice(strs, 1, last)
  end
end

return ut.table_copy_into({
    lines = lines,
    lines_array = lines_array,
    interp = interp,

    system = system,
    system_async = system_async,
    system_as_promise = system_as_promise,
    system_job_is_done = system_job_is_done,
    system_jobs_are_done = system_jobs_are_done,
    system_job_wait_for = system_job_wait_for,
    system_job_wait = system_job_wait,
    system_job_wait_all = system_job_wait_all,

    node_from_path = node_from_path,
    get_in = node_from_path,
    path_from_node = path_from_node,
    buf_padlines_to = buf_padlines_to,
    partition = partition,
    partition_iterator = partition_iterator,
    remove_trailing_newlines = remove_trailing_newlines,
    trim = trim,
    selected_region = selected_region,
    within_region = within_region,
    nanotime = nanotime,
    git_root_dir_p = git_root_dir_p,
    git_root_dir = git_root_dir,
    git_dot_git_dir = git_dot_git_dir,
    nvim_commands = nvim_commands,
    math_clamp = math_clamp,
    str_is_empty = str_is_empty,
    str_is_really_empty = str_is_really_empty,
    markup = markup_fn,
    is_markup = is_markup,
    markup_flatten = markup_flatten,
    nvim_synIDattr = nvim_synIDattr,
    string_split_by_pattern = string_split_by_pattern,
    hl_group_attrs = hl_group_attrs,
    hl_group_attrs_to_str = hl_group_attrs_to_str,
    nvim_line_zero_idx = nvim_line_zero_idx,
    zipper_picks_by_type = zipper_picks_by_type,
    git_shorten_sha = git_shorten_sha,
    call_or_print_stacktrace = call_or_print_stacktrace,
    wrap__call_or_print_stacktrace = wrap__call_or_print_stacktrace,
    filter_empty_strings = filter_empty_strings,
    array_remove_trailing_empty_lines = array_remove_trailing_empty_lines,
  },
  ut,
  require('gitabra.util.functional'),
  require('gitabra.util.color'))
