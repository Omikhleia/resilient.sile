--- A few utilities for the markdown / pandocast inputters
--
-- @copyright License: MIT (c) 2022-2025 Omikhleia
-- @module packages.markdown.utils
--
local createCommand = SU.ast.createCommand
local createStructuredCommand = SU.ast.createStructuredCommand

--- Extract the extension from a file name.
--
-- Assumes a POSIX-compliant name (with a slash as path separators).
--
-- @tparam string fname File name
-- @treturn string File extension
local function getFileExtension (fname)
  return fname:match("[^/]+$"):match("[^.]+$")
end

--- Non-breakable space extraction from a string.
--
-- It replaces them with an appropriate non-breakable inter-word space command.
--
-- @tparam string str Input string
-- @treturn string|table Filtered string or SILE AST table
local function nbspFilter (str)
  local t = {}
  for token in SU.gtoke(str, " ") do -- Warning, U+00A0 here.
    if(token.string) then
      t[#t+1] = token.string
    else
      t[#t+1] = createCommand("markdown:internal:nbsp")
    end
  end
  -- Returns a string or a (SILE AST) table
  if #t == 0 then return "" end
  return #t == 1 and t[1] or t
end

--- Check if a given class is present in the options.
--
-- @tparam table options Command options
-- @tparam string classname Pseudo-class specifier
-- @treturn boolean
local function hasClass (options, classname)
  -- N.B. we want a true boolean here
  if options.class and string.match(' ' .. options.class .. ' ',' '..classname..' ') then
    return true
  end
  return false
end

--- Find the first raw handler suitable for the given pseudo-class attributes.
--
-- @tparam table options Command options
-- @treturn function|nil Handler function (if found)
local function hasRawHandler (options)
  for name, handler in pairs(SILE.rawHandlers) do
    if hasClass(options, name) then
      SU.debug("markdown", "Found a raw handler for", name)
      return handler
    end
  end
  return nil
end

--- Find the first embedder suitable for the given pseudo-class attributes.
--
-- @tparam table options Command options with class attribute (nil or list of comma-separated classes)
-- @treturn string|nil Embedder name (if found)
-- @treturn function|nil Embedder handler function (if applicable)
local function hasEmbedHandler (options)
  if not options.class then
    return nil
  end
  local handler = SILE.rawHandlers["embed"]
  if not handler then
    -- Shouldn't occur since we loaded the embedders package
    -- but let's play safe...
    return nil
  end
  -- HACK TODO: Use of a scratch variable is ugly, tapping into the
  -- internals of the embedders package.
  local embedders = SILE.scratch.embedders
  if not embedders then
    return nil
  end
  local classes = pl.stringx.split(options.class, " ")
  for _, name in ipairs(classes) do
    SU.debug("markdown", "Checking for embedder", name)
    if embedders[name] then
      -- NOTE: Accessing the embedder table causes the entry to be loaded
      -- if it exists and is not loaded yet.
      SU.debug("markdown", "Found an embedder for", name)
      return name, handler
    end
  end
  SU.debug("markdown", "No embedder found")
  return nil
end

local metrics = require("fontmetrics")
local bsratiocache = {}

--- Compute the baseline ratio for the current font.
--
-- This is a ratio of the descender to the theoretical height of the font.
--
-- @treturn number Descender ratio
local function computeBaselineRatio ()
  local fontoptions = SILE.font.loadDefaults({})
  local bsratio = bsratiocache[SILE.font._key(fontoptions)]
  if not bsratio then
    local face = SILE.font.cache(fontoptions, SILE.shaper.getFace)
    local m = metrics.get_typographic_extents(face)
    bsratio = m.descender / (m.ascender + m.descender)
    bsratiocache[SILE.font._key(fontoptions)] = bsratio
  end
  return bsratio
end

--- Naive citation reference parser.
--
-- We only support a very simple syntax for now: `@key[, ]+[locator]`,
-- where the unique locator consists of a name and a value separated by spaces.
--
-- @tparam string str Citation string
-- @tparam[opt] table pos Position in the source (for error reporting)
-- @treturn table AST for the citation command
local function naiveCitations (str, pos)
  local refs = pl.stringx.split(str, ";")
  pl.tablex.transform(function (ref)
    local key, locator = ref:match("^[%s]*@([^%s,]+)[, ]*(.*)$")
    if not key or key == "" then
      SU.warn("Skipping citation reference '" .. ref .. "'")
      return {}
    end
    if locator and locator ~= "" then
      local locnname, locnvalue = locator:match("^([^%s]+)[%s]+(.+)$")
      if locnname and locnvalue then
        -- Remove trailing periods in locname if any
        locnname = locnname:gsub("%.+$", "")
        return createCommand("cite", { key = key, [locnname] = locnvalue })
      end
    end
    return createCommand("cite", { key = key }, nil, pos)
  end, refs)
  if #refs == 0 then
    SU.warn("No valid citation reference found in '" .. str .. "'")
    return {}
  end
  if #refs == 1 then
    return refs[1]
  end
  return createStructuredCommand("cites", {}, refs, pos)
end

--- A sandboxed loadfile implementation.
--
-- Load and run a Lua file in a restricted environment.
--
-- @tparam string filename File name
-- @tparam[opt] table env Additional environment entries
-- @treturn unknown|nil Loaded chunk
-- @treturn string|nil Error message
local function sandboxedLoadfile(filename, env)
  local envbase = {
    -- Handy for debugging: print, SU logging functions, pl.pretty.dump.
    -- Handy for table and string manipulations: table, pl.tablex, string, pl.stringx, pl.List, pl.Map, pl.Set.
    print = print,
    SU = {
      debug = SU.debug,
      error = SU.error,
      warn = SU.warn,
    },
    pl = {
      pretty = {
        dump = function (data) pl.pretty.dump(data) end -- To avoid the second unsafe argument
      },
      tablex = pl.tablex,
      stringx = pl.stringx,
      List = pl.List,
      Map = pl.Map,
      Set = pl.Set,
    },
    table = table,
    string = string,
    -- And a few basic safe functions...
    math = math,
    ipairs = ipairs,
    pairs = pairs,
    type = type,
    tostring = tostring,
    tonumber = tonumber,
    next = next,
    error = error,
    pcall = pcall,
  }
  env = pl.tablex.union(envbase, env or {}, true)
  local f, err
  -- Load in a sandboxed environment:
  -- Strategies differ between Lua 5.1 and later versions.
  if _VERSION == "Lua 5.1" then
    f, err = loadfile(filename)
    if not f then
      return nil, err
    end
    -- luacheck: push globals setfenv
    setfenv(f, env)
    -- luacheck: pop
  else
    f, err = loadfile(filename, "t", env)
    if not f then
      return nil, err
    end
  end
  -- Run the chunk in protected mode
  local ok, res = pcall(f)
  if not ok then
    return nil, res end
  return res
end

--- @export
return {
  getFileExtension = getFileExtension,
  nbspFilter = nbspFilter,
  hasClass = hasClass,
  hasRawHandler = hasRawHandler,
  hasEmbedHandler = hasEmbedHandler,
  computeBaselineRatio = computeBaselineRatio,
  naiveCitations = naiveCitations,
  sandboxedLoadfile = sandboxedLoadfile,
}
