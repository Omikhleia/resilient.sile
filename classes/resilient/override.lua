--
-- Base overrides on SILE's base class for use in resilient classes
-- (as toplevel superclass).
--
-- License: GPL-3.0-or-later
--
-- Copyright (C) 2023-2025 Didier Willis
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
--

-- INPUTTERS
-- This ensure our inputters are loaded, so one can \include files of the relevant format
-- afterwards, without having to load the inputter first.

SU.debug("resilient.override", "Loading extra inputters if available")
pcall(function () local _ = SILE.inputters.silm end)
pcall(function () local _ = SILE.inputters.markdown end)
pcall(function () local _ = SILE.inputters.djot end)
pcall(function () local _ = SILE.inputters.pandocast end)

-- CANCELLATION OF MULTIPLE PACKAGE INSTANCIATION
-- Packages such as resilient.style are stateful and freeze the styles at some point
-- in their workflow.
-- The multiple package instantiation model was introduced in SILE 0.13-0.14.
-- I struggled too many times with this issue in August 2022 (initial effort porting
-- my 0.12.5 packages to 0.14.x) and afterwards.
-- See SILE issue 1531 for some details.
-- I could never make any sense of this half-baked "feature", which introduces
-- unintended side-effects and problems impossible to decently address,
-- making the life of package and class developers real harder.
-- Some of the issues were supposed to be fixed in SILE 0.15, but removing the hacks
-- below still breaks (at least) package resilient.style...

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
      if class then
         -- BEGIN SILEX/RESILIENT CANCEL MULTIPLE PACKAGE INSTANCIATION
         if class.packages[name] then
            return SU.debug("resilient.override", "\\use fork ignoring already loaded package:", name)
         end
         -- END SILEX/RESILIENT CANCEL MULTIPLE PACKAGE INSTANCIATION
         class.packages[name] = pack(options)
      else
         table.insert(SILE.input.preambles, {
            pack = pack,
            options = options
         })
      end
   end
end

-- BASE CLASS OVERLOAD
-- We do a few things here:
-- - We replace SILE's default typesetter with the SILEnt typesetter
-- - Our classes do not use SILE's plain class, but implement minimal compatibility
-- - We cancel multiple package instanciation, as some packages are stateful (see above)

local base = require("classes.base")
local class = pl.class(base)
class._name = "resilient.override"

function class:_init (options)
   SU.debug("resilient.override", "Replacing SILE's default typesetter with the SILEnt typesetter")
   SILE.typesetters.default = require("typesetters.silent")

   base._init(self, options)

   -- We do not use SILE's plain class, but implement minimal compatibility via packages
   SU.debug("resilient.override", "Loading plain compatibility packages")
   self:loadPackage("resilient.plain")
   self:loadPackage("bidi")
end

function class:declareOptions ()
   -- Also from SILE's plain class
   self:declareOption("direction", function (_, value)
      if value then
         SILE.documentState.direction = value
         SILE.settings:set("font.direction", value, true)
         for _, frame in pairs(self.defaultFrameset) do
            if not frame.direction then
               frame.direction = value
            end
         end
      end
      return SILE.documentState.direction
   end)
   -- Specifically for resilient
   self:declareOption("resolution", function (_, value)
      if value then
         self.resolution = SU.cast("integer", value)
      end
      return self.resolution
   end)
end

function class:loadPackage (packname, options)
   local pack = require(("packages.%s"):format(packname))
   -- BEGIN SILEX/RESILIENT CANCEL MULTIPLE PACKAGE INSTANCIATION
   -- I beg to disagree with SILE here.
   if type(pack) == "table" and pack.type == "package" then -- new package
      if self.packages[pack._name] then
         return SU.debug("resilient.override", "Ignoring package already loaded in the class:", pack._name)
      end
   end
   base.loadPackage(self, packname, options)
end

-- WARNING: not called as class method
function class.newPar (typesetter)
   local parindent = SILE.settings:get("current.parindent") or SILE.settings:get("document.parindent")
   typesetter:pushGlue(parindent:absolute())
   SILE.settings:set("current.parindent", nil)
   -- BEGIN SILEX/RESILIENT HANGED LINES
   --   (MOVED TO THE TYPESETTER)
   -- END SILEX/RESILIENT HANGED LINES
end

-- WARNING: not called as class method
function class.endPar (typesetter)
   typesetter:pushVglue(SILE.settings:get("document.parskip"))
  -- BEGIN SILEX/RESILIENT HANGED LINES
  --   (MOVED TO THE TYPESETTER)
  -- END SILEX/RESILIENT HANGED LINES
end

function class:finish ()
   SILE.inputter:postamble()
   -- SILE/RESILIENT: Original typesetter calls SILE.typesetter:endline() here.
   -- We really need to clean up and clarify the typesetter's expectations....
   SILE.call("vfill")
   while not SILE.typesetter:isQueueEmpty() do
      SILE.call("supereject")
      SILE.typesetter:leaveHmode(true)
      SILE.typesetter:buildPage()
      if not SILE.typesetter:isQueueEmpty() then
         SILE.typesetter:initNextFrame()
      end
   end
   SILE.typesetter:runHooks("pageend") -- normally run by the typesetter
   self:endPage()
   if SILE.typesetter and not SILE.typesetter:isQueueEmpty() then
      SU.error("Queues are not empty as expected after ending last page", true)
   end
   SILE.outputter:finish()
   self:runHooks("finish")
end

return class
