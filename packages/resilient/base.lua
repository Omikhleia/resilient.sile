--
-- Resilient base package
-- 2023, Didier Willis
-- License: MIT
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

-- For overriding in subclass
function package.registerStyles (_) end

return package
