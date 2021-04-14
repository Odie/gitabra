local api = vim.api
local u = require('gitabra.util')
local zipper = require('gitabra.zipper')

local M = {}
M.__index = M

local namespace_id = api.nvim_create_namespace("gitabra.outliner")
local linemark_ns = api.nvim_create_namespace("gitabra.outliner/linemark")
local highlight_ns = api.nvim_create_namespace("gitabra.outliner/highlight")
M.namespace_id = namespace_id

local disclosure_sign_group = "disclosure_sign_group"
local collapsed_sign_name = "gitabra_outline_collapsed"
local expanded_sign_name = "gitabra_outline_expanded"

M.module_initialized = false
local function module_initialize()
  if M.module_initialized then
    return
  end

  vim.fn.sign_define(collapsed_sign_name, {text = vim.g.gitabra_outline_collapsed_text})

  vim.fn.sign_define(expanded_sign_name, {text = vim.g.gitabra_outline_expanded_text})
  M.module_initialized = true
end

local function node_debug_text(node)
  local text = node.id or node.text
  if type(text) == "table" then
    text = vim.inspect(text)
  end
  if #text > 100 then
    text = string.sub(text, 1, 97).."..."
  end
  return text
end

local function print_cs(cs)
  for _, n in ipairs(cs) do
    print(node_debug_text(n))
  end
end

-- Given some `target_node` and its `parent_node`, determine
-- which line the target_node's text should start on
local function determine_node_lineno(self, parent_node, target_node)

  -- The root node has no text
  -- There is no line where it can start
  if target_node == self.root then
    assert(true, "target_node should not be root")
    return 0
  end

  -- print("Scanning all nodes that come before the target node")
  -- Look through the parent node and see if we can find a node that sits just
  -- before the target node, which has a valid linemark
  local last_row = 0
  local matched_node = nil

  -- Look for the last visible item in the tree that appears just before the
  -- target node.
  -- This will visit all sibling nodes and their descendents.
  -- It might be better if we implemented `prev` in the zipper.
  local z = zipper.new(parent_node, "children")
  while not z:at_end() do
    local node = z:node()
    -- print("@", vim.inspect(node))

    -- The document tree is already fully formed...
    -- We want to figure out where content that comes before
    -- the target node has been placed.
    -- If we come across the target_node, we're done
    if node == target_node then
      break
    end

    if node.linemark ~= nil then
      -- print("located a node with linemark")
      local position = api.nvim_buf_get_extmark_by_id(self.buffer, linemark_ns, node.linemark, {})

      if position[1] then
        last_row = math.max(last_row, position[1])
        matched_node = node
        -- print("position for node is:", vim.inspect(position))
        -- print("new last row:", last_row)
      else
        -- print("linemark is invalid")
      end
    end

    z:next()
  end

  if not matched_node then
    -- print("no matched node, returning 0")
    return 0
  end

  local result = last_row + #matched_node.text
  if target_node.padlines_before then
    result = result + target_node.padlines_before
  end
  return result
end

local function lineno_from_linemark(self, linemark)
  local position = api.nvim_buf_get_extmark_by_id(self.buffer, linemark_ns, linemark, {})
  return position[1]
end

function M:lineno_from_node(node)
  if node.linemark then
    return lineno_from_linemark(node.linemark)
  end
end

function M.new(o_in)
  module_initialize()
  local o = o_in or {}
  o.root = o.root or {}
  o.root.id = "outliner-root"
  if o.root.depth == nil then
    o.root.depth = 0
  end
  o.root.children = o.root.children or {}
  setmetatable(o, M)
  return o
end

function M:node_zipper()
  return zipper.new(self.root, "children")
end

function node_text_has_markup(lines)
  for _, line in ipairs(lines) do
    if u.is_markup(line) then
      return true
    end
  end
  return false
end


-- Add a `child_node` into the `parent_node`
-- Return the added child node
function M:add_node(parent_node, child_node)
  -- Use the root node if a parent node is not specified
  if not parent_node then
    parent_node = self.root
  end

  if not child_node.children then
    child_node.children = {}
  end

  -- Add the child node
  -- the `text` field in a node indicates a array of lines
  -- Each line might also be a 'markup, which is itself an array
  -- For convenience, we'll allow the field to contain just a single
  -- line input.
  if type(child_node.text) == "string" then
    child_node.text = u.lines_array(child_node.text)
  elseif u.is_markup(child_node.text) then
    child_node.text = { child_node.text }
  end

  if node_text_has_markup(child_node.text) then
    child_node.has_markup = true

    local text_hls = u.table_copy_into({}, child_node.text)
    u.map(text_hls, u.markup_flatten, " ")
    local text_lines = {}
    for _, item in ipairs(text_hls) do
      table.insert(text_lines, u.remove_trailing_newlines(item.text))
    end

    child_node.markup = child_node.text
    child_node.text = text_lines
    child_node.text_hls = text_hls
  end

  child_node.depth = parent_node.depth + 1
  table.insert(parent_node.children, child_node)

  return child_node
end

function delete_all_linemarks(self)
  api.nvim_buf_clear_namespace(self.buffer, linemark_ns, 0, -1)
end

function delete_all_disclosure_signs(self)
  vim.fn.sign_unplace(disclosure_sign_group, {buffer = self.buffer})
end

function delete_all_text(self)
  api.nvim_buf_set_lines(self.buffer, 0, -1, true, {})
end

-- Clean up node data that should be temporary.
function cleanup_node_transients(self)
  for node in u.table_depth_first_visit(self.root) do
    if node.linemark then
      node.linemark = nil
      node.sign_id = nil
    end
  end
end

function M:refresh()
  local modifiable = vim.bo[self.buffer].modifiable
  if not modifiable then
    vim.bo[self.buffer].modifiable = true
  end

  cleanup_node_transients(self)
  delete_all_linemarks(self)
  delete_all_disclosure_signs(self)
  delete_all_text(self)
  -- We should also delete all highlights here
  -- Looks like the highlights are deleted along with the text though.

  -- Start a new zipper and move to the first child of the root node
  local z = self:node_zipper()
  z:down()

  -- print("About to start loop")
  while not z:at_end() do
    -- print("loop start")
    local node = z:node()
    local parent = z:parent_node()

    -- print("node:", vim.inspect(node))
    -- print(">>>>>>>>>>>>>>>>>>>>>>> looking to place:", node_debug_text(node))
    -- Determine where we should be placing the text
    local lineno = determine_node_lineno(self, parent, node)
    -- print("**** extmark & content] adding at line:", lineno)

    -- Place the text into the buffer at said location
    u.buf_padlines_to(self.buffer, lineno+#node.text)
 	  api.nvim_buf_set_lines(self.buffer, lineno, lineno+#node.text, true, node.text)

    if node.text_hls then
      for i, line in ipairs(node.text_hls) do
        for _, hl in ipairs(line.hl) do
          -- print(string.format("setting line %i [%i,%i] to %s", lineno+i-1, hl.start, hl.stop, hl.group))
          api.nvim_buf_add_highlight(self.buffer, highlight_ns, hl.group, lineno+i-1, hl.start, hl.stop)
        end
      end
    end

    -- Add extmark at the same location
 	  node.linemark = api.nvim_buf_set_extmark(self.buffer, linemark_ns, lineno, 0, {})
    node.lineno = lineno

    -- Place a sign depending on if there are child nodes or not
    local cs = z:children()
    if cs and not u.table_is_empty(cs) then
      local sign_name
      if node.collapsed then
        sign_name = collapsed_sign_name
      else
        sign_name = expanded_sign_name
      end
      node.sign_id = vim.fn.sign_place(0, disclosure_sign_group, sign_name, self.buffer, {lnum = lineno+1})
    end

    -- If this node has been collapsed, move on to the next sibling branch
    if node.collapsed then
      -- print("moving right")
      if not z:right() then
        -- print("moving right failed, no more siblings")
        z:next_up_right()
      end
    else
      -- Otherwise, continue the depth-first traversal
      -- print("moving next")
      z:next()
    end
  end

  if not modifiable then
    vim.bo[self.buffer].modifiable = modifiable
  end
end

-- Returns a {start, end} tuple where the content of the node resides
function M:region_occupied(node)
  local position = api.nvim_buf_get_extmark_by_id(self.buffer, linemark_ns, node.linemark, {})
  if position[1] then
    return {position[1], position[1] + #node.text - 1}
  end
end

function M:node_zipper_at_lineno(lineno)
  local z = self:node_zipper()
  local cs = z:children()

  while cs and #cs ~= 0 do
    -- print("loop start")
    -- print("path so far:", vim.inspect(z.path_idxs))
    -- print("cs @")
    -- print_cs(cs)

    -- Filter for children with linemarks
    cs = u.filter(cs, function(c)
      if c.linemark then
        return true
      end
    end)

    -- print("filtered @")
    -- print_cs(cs)

    -- Retrieve/update all starting lineno of children
    u.map(cs, function(c)
      c.lineno = lineno_from_linemark(self, c.linemark)
      return c
    end)

    -- print("mapped @")
    -- print_cs(cs)

    -- From the valid child candidates, pick the node that seems to contain the lineno
    -- we're searching for
    local candidate = nil
    if #cs == 1 then
      -- print("Picking only child")
      if lineno >= cs[1].lineno then
        candidate = cs[1]
      end
    else
      -- print("choosing best match from children")
      -- Using the starting line number for each sibling pair,
      -- try to figure out which node/path we should go down towards
      for c1, c2 in u.partition_iterator(cs, 2, 1) do
        -- print("c1", c1.lineno, node_debug_text(c1))
        -- print("c2", c2.lineno, node_debug_text(c2))

        if c1.lineno <= lineno and lineno < c2.lineno then
          -- print("Picking c1")
          candidate = c1
          break
        end
      end

      -- If we found no results after examining all pairs, we'll
      -- assume it's because the last node is the matching node
      if not candidate then
        -- print("Picking last child")
        candidate = cs[#cs]
      end
    end

    -- Can't drill down any further?
    -- Use the path we have so far as the result
    if not candidate then
      -- print("No available candidates this loop")
      break
    end

    -- print("navigating to child @", node_debug_text(candidate))
    z:to_child_node(candidate)

    if candidate.lineno == lineno then
      break
    end
    cs = z:children()
  end

  -- print("No more child nodes")
  -- print("picked node:", node_debug_text(z:node()))

  -- At this point, the zipper should be pointing at a node
  -- that we think contains the target linenumber.
  if u.within_region(self:region_occupied(z:node()) , lineno) then
    -- print("is in region")
    return z
  else
    -- print("not within region")
    return nil
  end
end

function M:close()
  api.nvim_buf_delete(self.buffer, {})
end


function M:find_node(pred)
  return u.table_find_node(self.root, pred)
end

function M:node_children(node)
  return node.children
end

function M:set_node_children(node, new_children)
  node.children = new_children
end


-- Walk the document/outline and find an item with
-- the given `name` in the `id` field.
function M:node_by_id(name)
  return u.table_find_node(self.root, function(node)
    if node.id == name then
      return true
    end
  end)
end

return M
