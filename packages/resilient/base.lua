--
-- Resilient base for style-enabled packages for SILE
--
-- It provides a base class for packages that want to use styles,
-- and a few convenience methods hide the internals.
--
-- License: MIT
-- Copyright (C) 2023-2025 Omikhleia / Didier Willis
--
local base = require("packages.base")
local package = pl.class(base)
package._name = "resilient.base"
package.styles = nil

function package:_init (options)
  base._init(self, options)

  self:loadPackage("resilient.styles")
  self.styles = self.class.packages["resilient.styles"]
  self:registerStyles()
end

function package:registerStyle (name, opts, styledef)
  return self.styles:defineStyle(name, opts, styledef, self._name)
end

function package:resolveStyle (name, discardable)
  return self.styles:resolveStyle(name, discardable)
end

function package:hasStyle (name)
  return self.styles:hasStyle(name)
end

-- For overriding in any package subclass, as a convenient hook
-- where to register all styles.
function package:registerStyles () end

return package
