--
-- Base resilient class
-- 2023, Didier Willis
-- License: MIT
--
local parent = require("classes.plain")
local class = pl.class(parent)
class._name = "resilient.base"
class.styles = nil

require("resilient.hacks") -- Global SILE hacks for resilient

-- BEGIN HACK FOR PARINDENT ISSUE
function class.newPar (typesetter)
  local parindent = SILE.settings:get("current.parindent") or SILE.settings:get("document.parindent")
  -- See https://github.com/sile-typesetter/sile/issues/1361
  -- The parindent *cannot* be pushed non-absolutized, as it may be evaluated
  -- outside the (possibly temporary) setting scope where it was used for line
  -- breaking.
  -- Early absolutization can be problematic sometimes, but here we do not
  -- really have the choice.
  -- As of problematic cases, consider a parindent that would be defined in a
  -- frame-related unit (%lw, %fw, etc.). If a frame break occurs and the next
  -- frame has a different width, the parindent won't be re-evaluated in that
  -- new frame context. However, defining a parindent in such a unit is quite
  -- unlikely. And anyway pushback() has plenty of other issues.
  typesetter:pushGlue(parindent:absolute()) -- HACK
  SILE.settings:set("current.parindent", nil)
  local hangIndent = SILE.settings:get("current.hangIndent")
  if hangIndent then
    SILE.settings:set("linebreak.hangIndent", hangIndent)
  end
  local hangAfter = SILE.settings:get("current.hangAfter")
  if hangAfter then
    SILE.settings:set("linebreak.hangAfter", hangAfter)
  end
end
-- END HACK FOR PARINDENT ISSUE

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

-- BEGIN HACKS FOR MULTIPLE INSTANTION SIDE EFFECTS
function class:loadPackage (packname, options)
  local pack = require(("packages.%s"):format(packname))
  if type(pack) == "table" and pack.type == "package" then -- new package
    -- I beg to disagree with SILE here
    if self.packages[pack._name] then
      return SU.debug("resilient", "Already load into class (hack) "..pack._name)
    end
    self.packages[pack._name] = pack(options)
  else -- legacy package
    SU.warn("CLASS: legacy package "..pack._name)
    self:initPackage(pack, options)
  end
end
-- END HACKS FOR MULTIPLE INSTANTION SIDE EFFECTS

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
