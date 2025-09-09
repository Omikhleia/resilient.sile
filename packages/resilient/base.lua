--- Base class for style-enabled packages in re·sil·ient.
--
-- It provides a base class for packages that want to use styles,
-- and a few convenience methods hide the internals.
--
-- @license MIT
-- @copyright (c) 2023-2025 Omikhleia / Didier Willis
-- @module packages.resilient.base

--- Base class for style-enabled packages.
--
-- Extends SILE's `packages.base`.
--
-- @type packages.resilient.base

local base = require("packages.base")
local package = pl.class(base)
package._name = "resilient.base"
package.styles = nil

--- (Constructor) Initialize the package.
--
-- It ensures the `packages;resilient.styles` package is loaded,
-- and calls the `registerStyles` method, which is a convenient
-- hook to register all styles for subclasses.
--
-- @tparam table options Package options
function package:_init (options)
  base._init(self, options)

  self:loadPackage("resilient.styles")
  self.styles = self.class.packages["resilient.styles"]
  self:registerStyles()
end

--- Register a style.
-- @tparam string name Style name
-- @tparam table opts Style options
-- @tparam table styledef Style definition
function package:registerStyle (name, opts, styledef)
  return self.styles:defineStyle(name, opts, styledef, self._name)
end

--- Resolve a style name into a style definition.
-- @tparam string name Style name
-- @tparam[opt] boolean discardable If true, do not raise an error if the style is not found
-- @treturn table|nil Style definition
function package:resolveStyle (name, discardable)
  return self.styles:resolveStyle(name, discardable)
end

--- Check if a style is defined.
-- @tparam string name Style name
-- @treturn boolean True if the style is defined
function package:hasStyle (name)
  return self.styles:hasStyle(name)
end

--- (Abstract) Register all styles.
--
-- For overriding in any package subclass, as a convenient hook
-- where to register all styles.
function package:registerStyles () end

return package
