local u = require("gitabra.util")
local promise = require("gitabra.promise")
local api = vim.api

local active_bufs = {}

local function buf_id(opts)
  return string.format("%s/%s~%s~", opts.git_root, opts.filename, opts.rev)
end

local function get_current_rev_file_buf()
  assert(vim.b.rev_file_buf_id)
  return active_bufs[vim.b.rev_file_buf_id]
end

local function remove_rev_file_buf_by_bufnr(bufnr)
  bufnr = tonumber(bufnr)
  local id = vim.api.nvim_buf_get_var(bufnr, "rev_file_buf_id")
  active_bufs[id] = nil
end

local function git_file_from_rev(rev, filename)
  print(vim.inspect( {"git", "show", rev, filename} ))
  return u.system_as_promise({"git", "show", rev, filename}, {split_lines=true})
end

local function close_buf(skip_buf_delete)
  local rev_buf = get_current_rev_file_buf()
  if rev_buf then
    active_bufs[rev_buf.id] = nil

    if not skip_buf_delete then
      api.nvim_buf_delete(rev_buf.bufnr, {})
    end
  end
end

local function setup_keybinds(bufnr)
  local function set_keymap(...) vim.api.nvim_buf_set_keymap(bufnr, ...) end
  local opts = { noremap=true, silent=true }
  set_keymap('n', 'q', '<cmd>lua require("gitabra.rev_file_buffer").close_buf()<cr>', opts)
end

local function setup_buffer()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].swapfile = false
  vim.bo[buf].buftype = 'nofile'
  setup_keybinds(buf)
  return buf
end

local function show(opts)
  local id = buf_id(opts)
  local existing_buf = active_bufs[id]
  if existing_buf then
    api.nvim_set_current_buf(existing_buf.bufnr)
    return existing_buf
  end

  -- Get the contents of the file
  local file_content_p = git_file_from_rev(opts.rev, opts.filename)
  local wait_result = promise.wait(file_content_p, 2000)
  if not wait_result then
    local funcname = debug.getinfo(1, "n").name
    print(vim.inspect(file_content_p))
    error(string.format("%s: unable to complete git commands within the alotted time", funcname))
  end

  local buf = u.table_copy_into({}, opts, {
    id = id,
    bufnr = setup_buffer()
  })
  api.nvim_set_current_buf(buf.bufnr)

  api.nvim_buf_set_lines(buf.bufnr, 0, #file_content_p.value+1, false, file_content_p.value)

  vim.b.rev_file_buf_id = buf.id

  active_bufs[buf.id] = buf
  vim.bo[buf.bufnr].modifiable = false

  -- Ask vim to detect the file type
  -- We want to:
  -- 1) Have a proper file name for vim to work with, but
  -- 2) Not to get it confused with another buffer with the same name
  -- 3) Assign some arbitrary filename after filetype detection is completed
  api.nvim_buf_set_name(buf.bufnr, "gitabra_temp://"..buf.filename)
  vim.cmd("filetype detect")
  api.nvim_buf_set_name(buf.bufnr, string.format("%s.~%s~", buf.filename, buf.commit_rev))

  u.nvim_commands([[
    augroup CleanupRevFileBuffer
      autocmd! * <buffer>
      autocmd BufUnload <buffer> lua require('gitabra.rev_file_buffer').remove_rev_file_buf_by_bufnr(vim.fn.expand("<abuf>"))
    augroup END
    ]], true)

  return buf
end

return {
  show = u.wrap__call_or_print_stacktrace(show),
  close_buf = close_buf,
  remove_rev_file_buf_by_bufnr = remove_rev_file_buf_by_bufnr,
}

