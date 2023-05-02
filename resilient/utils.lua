--
-- Common utilities for RESILIENT
-- 2023 Didier Willis
-- License: MIT
--

-- Measure an inter-word space (which, depending on settings, might be variable
-- and thus have stretch/shrink).
local function interwordSpace()
  return SILE.shaper:measureSpace(SILE.font.loadDefaults({}))
end

-- Cast a kern length (e.g. in styles), also supporting the special "iwsp"
-- pseudo unit.
local function castKern(kern)
  if type(kern) == "string" then
    local value, rest = kern:match("^(%d*)iwsp[ ]*(.*)$")
    if value then
      if rest ~= "" then
        SU.error("Could not parse kern '" .. kern .. "'")
      end
      return (tonumber(value) or 1) * interwordSpace()
    end
  end
  return SU.cast("length", kern)
end

-- Merge two tables.
-- It turns out that pl.tablex.union does not recurse into the table,
-- so let's do it the proper way.
-- N.B. modifies t1 (and t2 wins on "leaves" existing in both)
local function recursiveTableMerge(t1, t2)
  for k, v in pairs(t2) do
    if (type(v) == "table") and (type(t1[k]) == "table") then
      recursiveTableMerge(t1[k], t2[k])
    else
      t1[k] = v
    end
  end
end

-- Extract a node from SILE AST.
local function extractFromTree (tree, command)
  for i=1, #tree do
    if type(tree[i]) == "table" and tree[i].command == command then
      return table.remove(tree, i)
    end
  end
end

--- SILE AST utilities
-- @section ast

--- Create a command from a simple content tree.
-- So that's basically the same logic as the "inputfilter" package's
-- createComment() (with col, lno, pos set to 0, as we don't get them
-- from Lunamark or Pandoc.
--
-- @tparam  string command name of the command
-- @tparam  table  options command options
-- @tparam  table  content content tree
-- @treturn table  SILE AST command
local function createCommand (command, options, content)
  local result = { content }
  result.col = 0
  result.lno = 0
  result.pos = 0
  result.options = options or {}
  result.command = command
  result.id = "command"
  return result
end

--- Create a command from a structured content tree.
-- The content is normally a table of an already prepared content list.
--
-- @tparam  string command name of the command
-- @tparam  table  options command options
-- @tparam  table  contents content tree list
-- @treturn table  SILE AST command
local function createStructuredCommand (command, options, contents)
  -- contents = normally a table of an already prepared content list.
  local result = type(contents) == "table" and contents or { contents }
  result.col = 0
  result.lno = 0
  result.pos = 0
  result.options = options or {}
  result.command = command
  result.id = "command"
  return result
end

local function subTreeContent (content)
  local out = {}
  for _, val in ipairs(content) do
    out[#out+1] = val
  end
  return out
end

return {
  castKern = castKern,
  extractFromTree = extractFromTree,
  interwordSpace = interwordSpace,
  recursiveTableMerge = recursiveTableMerge,
  createCommand = createCommand,
  createStructuredCommand = createStructuredCommand,
  subTreeContent = subTreeContent,
}
