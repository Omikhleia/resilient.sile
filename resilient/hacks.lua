--
-- Global hacks to SILE for RESILIENT
-- 2023 Didier Willis
-- License: MIT
--
-- Some of these are a departure from SILE's intents.
-- Some are fixes or workarounds for issues in SILE.
--

-- BEGIN HACKS FOR MULTIPLE INSTANTION SIDE EFFECTS
-- OPINIONATED DEPARTURE FROM SILE.
-- ... but just run SILE with -d resilient... and wonder WHY we
-- keep redefining things in obscure places.
-- See https://github.com/sile-typesetter/sile/issues/1531
-- Since August 2021 (initial effort porting my 0.12.5 packages to 0.14.x),
-- I have struggled with it. I can't make sense of it now in Feb. 2023, so
-- moving on and cancelling it...
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
        return SU.debug("resilient", "\\use with resilient: package already loaded", name)
      end
      class.packages[name] = pack(options)
    else
      table.insert(SILE.input.preambles, {
        pack = pack,
        options = options
      })
    end
  end
end
-- END HACKS FOR MULTIPLE INSTANTION SIDE EFFECTS

-- BEGIN HACK FOR PARINDENT HBOX ISSUE
-- The paragraph indent was re-applied inside an hbox at the start of a
-- paragraph.
-- See https://github.com/sile-typesetter/sile/issues/1718
local oldInitLine = SILE.typesetters.base.initline
SILE.typesetters.base.initline = function (self)
  if self.state.hmodeOnly then
    return
  end
  oldInitLine(self)
end
-- END HACK FOR PARINDENT HBOX ISSUE
