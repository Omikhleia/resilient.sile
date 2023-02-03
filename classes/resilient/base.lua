--
-- Base resilient class
-- 2023, Didier Willis
-- License: MIT
--
local plain = require("classes.plain")
local class = pl.class(plain)
class._name = "resilient.base"
class.styles = nil

-- HACKS FOR MULTIPLE INSTANTION SIDE EFFECTS
-- Not complete (autodoc does similar things, and SILE.require() too)
--
-- SILE.settings.declare = function (self, spec)
--   if self.declarations[spec.parameter] then ---- HACK
--     SU.warn("SETTINGS: ignoring redeclaration "..spec.parameter)
--     return
--   end
--   self.declarations[spec.parameter] = spec
--   self:set(spec.parameter, spec.default, true)
-- end

-- SILE.use = function (module, options)
--   local pack
--   if type(module) == "string" then
--     pack = require(module)
--   elseif type(module) == "table" then
--     pack = module
--   end
--   local name = pack._name
--   local class = SILE.documentState.documentClass
--   if not pack.type then
--     SU.error("Modules must declare their type")
--   elseif pack.type == "class" then
--     SILE.classes[name] = pack
--     if class then
--       SU.error("Cannot load a class after one is already instantiated")
--     end
--     SILE.scratch.class_from_uses = pack
--   elseif pack.type == "inputter" then
--     SILE.inputters[name] = pack
--     SILE.inputter = pack(options)
--   elseif pack.type == "outputter" then
--     SILE.outputters[name] = pack
--     SILE.outputter = pack(options)
--   elseif pack.type == "shaper" then
--     SILE.shapers[name] = pack
--     SILE.shaper = pack(options)
--   elseif pack.type == "typesetter" then
--     SILE.typesetters[name] = pack
--     SILE.typesetter = pack(options)
--   elseif pack.type == "pagebuilder" then
--     SILE.pagebuilders[name] = pack
--     SILE.pagebuilder = pack(options)
--   elseif pack.type == "package" then
--     SILE.packages[name] = pack
--     if class then
--       if class.packages[name] then
--         SU.warn("USE: ignore reloading "..name) ----- HACK
--         return
--       end
--       pack(options)
--     else
--       table.insert(SILE.input.preambles, { pack = pack, options = options })
--     end
--   end
-- end

function class:_init (options)
  plain._init(self, options)

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

function class:loadPackage (packname, options)
  local pack = require(("packages.%s"):format(packname))
  if type(pack) == "table" and pack.type == "package" then -- new package
    -- See HACK above
    -- if self.packages[pack._name] then
    --   SU.warn("CLASS: ignore package reloading "..pack._name)
    --   return
    -- end
    self.packages[pack._name] = pack(options)
  else -- legacy package
    SU.warn("CLASS: legacy package "..pack._name)
    self:initPackage(pack, options)
  end
end


function class.registerRawHandlers (_)
  plain:registerRawHandlers()

end


function class.registerCommands (_)
  plain:registerCommands()

end

return class
