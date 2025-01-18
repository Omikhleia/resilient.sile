--
-- Resilient base for style-enabled packages for SILE
--
-- 2023, 2025, Didier Willis
-- License: MIT
--
-- It provides a base class for packages that want to use styles,
-- and a few convenience methods hide the internals.
--
require("silex")
local base = require("packages.base")

local package = pl.class(base)
package._name = "resilient.base"
package.styles = nil

function package:_init (options)
  base._init(self, options)

  self.class:loadPackage("resilient.styles")
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
function package.registerStyles (_) end

return package
