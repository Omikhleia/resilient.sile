--- The base style-aware document class for re·sil·ient.
--
-- It provides a base class for document classes that want to use styles,
-- following the re·sil·ient styling paradigm, with a few convenience methods
-- hide the internals.
--
-- @license MIT
-- @copyright (c) 2023-2025 Omikhleia / Didier Willis
-- @module classes.resilient.base

--- The base document class for re·sil·ient documents.
--
-- Extends `classes.resilient.override`.
--
-- @type classes.resilient.base

local parent = require("classes.resilient.override")
local class = pl.class(parent)
class._name = "resilient.base"
class.styles = nil

-- Some defaults
class.firstContentFrame = "content"
class.defaultFrameset = {
  content = {
    left = "left(page) + 10%pw",
    right = "left(page) + 90%pw",
    top = "top(page) + 10%pw",
    bottom = "bottom(page)-10%pw"
  },
  header = {
    left = "left(content)",
    right = "right(content)",
    top = "top(content) - 5%ph",
    bottom = "top(content) - 2%ph"
  },
  footer = {
    left = "left(content)",
    right = "right(content)",
    top = "bottom(content) + 2%ph",
    bottom = "bottom(content) + 5%ph"
  },
  folio = { -- same as footer for now, compatibility with folio package
    left = "left(content)",
    right = "right(content)",
    top = "bottom(content) + 2%ph",
    bottom = "bottom(content) + 5%ph"
  },
}

--- (Constructor) Initialize the class.
--
-- It initialize the parent class, loads the `packages.resilient.styles` module,
-- and invokes the `registerStyles()` method, which is a convenient hook
-- for subclasses where to register all their styles.
--
-- @tparam table options Class options
function class:_init (options)
  parent._init(self, options)

  self:loadPackage("resilient.styles")
  self.styles = self.packages["resilient.styles"]
  self:registerStyles()
end

local alternateVariant = {
  -- These have style-aware resilient variants and extra features
  lists = "resilient.lists",
  verbatim = "resilient.verbatim",
  tableofcontents = "resilient.tableofcontents",
  footnotes = "resilient.footnotes",
  -- The following one is not really style-aware but has a resilient variant
  -- with extra features, used (and documented) in the resilient styling paradigm.
  background = "resilient.background",
}

--- (Override) Load a package, using a resilient alternative if available.
--
-- Some core or 3rd-party packages may load a non-resilient variant of
-- another package, and this would cause issues with the commands being
-- redefined to the non-resilient variant.
--
-- We enforce loading the alternative resilient variant instead, assuming
-- compatibility (though we cannot fully guarantee it).
--
-- @tparam string|table packname Package name or package instance
-- @tparam table options Package options
function class:loadPackage (packname, options)
  -- Darn. SILE is weird as hell sometimes.
  -- "packname" can be a string, but it can also be a package instance.
  -- If this isn't being defective by design, I don't know what is.
  local name = type(packname) == "string" and packname or packname._name
    or SU.error("Invalid package name " .. tostring(packname))
  if alternateVariant[name] then
    SU.debug("resilient", "Loading the resilient variant of package", name, "=", alternateVariant[name],
    [[

This should be compatible, but there might be differences such as hooks not
being available (as the resilient version may use styles instead), or commands
having different options.
Please consider using resilient-compatible style-aware packages when available!
]])
    packname = alternateVariant[packname]
  end
  return parent.loadPackage(self, packname, options)
end

--- Register a style.
-- @tparam string name Style name
-- @tparam table opts Style options
-- @tparam table styledef Style definition
function class:registerStyle (name, opts, styledef)
  return self.styles:defineStyle(name, opts, styledef, self._name)
end

--- Resolve a style name into a style definition.
-- @tparam string name Style name
-- @tparam[opt] boolean discardable If true, do not raise an error if the style is not found
-- @treturn table|nil Style definition
function class:resolveStyle (name, discardable)
  return self.styles:resolveStyle(name, discardable)
end

--- Check if a style is defined.
-- @tparam string name Style name
-- @treturn boolean True if the style is defined
function class:hasStyle (name)
  return self.styles:hasStyle(name)
end

--- (Abstract) Register all styles.
--
-- For overriding in any document subclass, as a convenient hook
-- where to register all styles.
function class:registerStyles () end

return class
