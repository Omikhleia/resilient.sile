--
-- Base resilient class
-- 2023, Didier Willis
-- License: MIT
--
local parent = require("classes.plain")
local class = pl.class(parent)
class._name = "resilient.base"
class.styles = nil

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

-- BEGIN HACKS FOR MULTIPLE INSTANTION SIDE EFFECTS
-- OPINIONATED AND DIRTY
-- ... but just run SILE with -d resilient... and wonder WHY we
-- keep redefining things in obscure places.
-- See https://github.com/sile-typesetter/sile/issues/1531
-- Since August 2021 (initial effort porting my 0.12.5 packages to 0.14.x),
-- I have struggled with it. I can't make sense of it now in Feb. 2023, so
-- moving on...

SILE.settings.declare = function (self, spec)
  if self.declarations[spec.parameter] then
    return SU.debug("resilient", "Settings redeclaration ignore ", spec.parameter) -- HACK
  end
  self.declarations[spec.parameter] = spec
  self:set(spec.parameter, spec.default, true)
end

SILE.use = function (module, options)
  local pack
  if type(module) == "string" then
    pack = require(module)
  elseif type(module) == "table" then
    pack = module
  end
  local name = pack._name
  local class = SILE.documentState.documentClass -- luacheck: ignore
  if not pack.type then
    SU.error("Modules must declare their type")
  elseif pack.type == "class" then
    SILE.classes[name] = pack
    if class then
      SU.error("Cannot load a class after one is already instantiated")
    end
    SILE.scratch.class_from_uses = pack
  elseif pack.type == "inputter" then
    SILE.inputters[name] = pack
    SILE.inputter = pack(options)
  elseif pack.type == "outputter" then
    SILE.outputters[name] = pack
    SILE.outputter = pack(options)
  elseif pack.type == "shaper" then
    SILE.shapers[name] = pack
    SILE.shaper = pack(options)
  elseif pack.type == "typesetter" then
    SILE.typesetters[name] = pack
    SILE.typesetter = pack(options)
  elseif pack.type == "pagebuilder" then
    SILE.pagebuilders[name] = pack
    SILE.pagebuilder = pack(options)
  elseif pack.type == "package" then
    SILE.packages[name] = pack
    -- HACK
    if class then
      if class.packages[name] then
        return SU.debug("resilient", "\\use with resilient already loaded", name)
      end
      class.packages[name] = pack(options)
    else
      table.insert(SILE.input.preambles, { pack = pack, options = options })
    end
  end
end
-- END HACKS FOR MULTIPLE INSTANTION SIDE EFFECTS

function class:_init (options)
  parent._init(self, options)

  self:loadPackage("resilient.styles")
  self.styles = self.packages["resilient.styles"]
  self:registerStyles()
end

function class:_post_init ()
  parent._post_init(self)
  self.styles:freezeStyles()
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
      return SU.debug("resiient", "Already load into class (hack) "..pack._name)
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

function class.registerRawHandlers (_)
  parent:registerRawHandlers()

end


function class.registerCommands (_)
  parent:registerCommands()

end

return class
