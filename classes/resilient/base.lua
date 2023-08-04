--
-- Base resilient class
-- 2023, Didier Willis
-- License: MIT
--
require("silex")

local parent = require("classes.plain")
local class = pl.class(parent)
class._name = "resilient.base"
class.styles = nil

function class:_init (options)
  parent._init(self, options)

  self:loadPackage("resilient.styles")
  self.styles = self.packages["resilient.styles"]
  self:registerStyles()
end

function class:registerStyle (name, opts, styledef)
  return self.styles:defineStyle(name, opts, styledef, self._name)
end

function class:resolveStyle (name, discardable)
  return self.styles:resolveStyle(name, discardable)
end

-- For overriding in subclass
function class.registerStyles (_) end

function class:declareOptions ()
  parent.declareOptions(self)

  self:declareOption("resolution", function(_, value)
    if value then
      self.resolution = SU.cast("integer", value)
    end
    return self.resolution
  end)
end

function class:registerRawHandlers ()
  parent.registerRawHandlers(self)

end

function class:registerCommands ()
  parent.registerCommands(self)

end

return class
