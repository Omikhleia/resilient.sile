--- Top-level super-class for re·sil·ient document classes.
--
-- Opinionated changes and overrides to SILE's standard base document class behavior.
--
-- @license MIT
-- @copyright (c) 2023-2025 Omikhleia / Didier Willis
-- @module classes.resilient.override

-- BOOTSTRAP GLOBAL OVERRIDES
-- This ensure our inputters are loaded, so one can \include files of the relevant format
-- afterwards, without having to load the inputter first.
-- This also tweaks some SILE core behavior.
-- In our setup notes, we recommended users to define an alias to run sile with the
-- resilient bootstrap file loaded, e.g.:
--   alias resilient='sile -e "require('"'"'resilient.bootstrap'"'"')"'
-- So this should be already done, but we ensure it here anyway in case
-- the user did not do so.
require("resilient.bootstrap")

--- The base document class for re·sil·ient documents.
--
-- Extends SILE's `classes.base`.
--
-- It deviates from SILE's implementation in several ways:
--
--  - It replaces SILE's default typesetter with the sile·nt typesetter?
--  - It does not used SILE's "plain" class, but implements minimal compatibility via packages.
--  - It cancels multiple package instantiation, as some of our packages are stateful.
--
-- @type classes.resilient.override

local base = require("classes.base")
local class = pl.class(base)
class._name = "resilient.override"

--- (Constructor) Initialize the class.
--
-- It enforces the use for the sile·nt typesetter.
-- It loads the `packages.resilient.plain` and `bidi` packages for compatibility.
--
-- @tparam table options Class options
function class:_init (options)
   SU.debug("resilient.override", "Replacing SILE's default typesetter with the silent new typesetter")
   SILE.resilient.enforceSilentTypesetterAndPagebuilder () -- TRANSITIONAL

   base._init(self, options)

   -- We do not use SILE's plain class, but implement minimal compatibility via packages
   SU.debug("resilient.override", "Loading plain compatibility packages")
   self:loadPackage("resilient.plain")
   self:loadPackage("bidi")
end

--- (Override) Declare class options.
--
-- The options added here are:
--
--  - direction: text direction (from SILE's plain class)
--  - resolution: resolution in DPI (specific to resilient)
--
function class:declareOptions ()
   -- From SILE's plain class (bidi-related)
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

--- (Override) Load a package.
--
-- Packages such as `packages.resilient.styles` are stateful and freeze the styles at some point
-- in their workflow.
--
-- The multiple package instantiation model was introduced in SILE 0.13-0.14.
-- I struggled too many times with this issue in August 2022 (initial effort porting
-- my 0.12.5 packages to 0.14.x) and afterwards.
-- See SILE issue 1531 for some details.
-- I could never make any sense of this "feature", which introduces unintended
-- side-effects and problems difficult to decently address.
-- Some of the issues were supposed to be fixed in SILE 0.15, but removing the hacks
-- below still breaks (at least) the styling logic.
-- SILE's standard method has an extra "reload" argument, which we do not use here.
-- There is no way to distinguish between a new package instantiation and a non-forced reload.
-- Some classes and packages need to modify and extend commands from other packages,
-- but package reloading can break this.
--
-- In brief: we cancel the multiple package instantiation.
--
-- @tparam string packname Package name
-- @tparam table options Package options
function class:loadPackage (packname, options)
   local pack
   if type(packname) == "table" then
      pack, packname = packname, packname._name
   elseif type(packname) == "nil" or packname == "nil" or pl.stringx.strip(packname) == "" then
      SU.error(("Attempted to load package with an invalid packname '%s'"):format(packname))
   else
      pack = require(("packages.%s"):format(packname))
      if pack._name ~= packname then
         SU.error(("Loaded module name '%s' does not match requested name '%s'"):format(pack._name, packname))
      end
   end
   SILE.packages[packname] = pack
   if type(pack) == "table" and pack.type == "package" then -- current package API (0.14+)
      if self.packages[packname] then
         return SU.debug("resilient.override", "Ignoring package already loaded in the class:", pack._name)
      else
         self.packages[packname] = pack(options)
      end
   else -- legacy package API (pre-0.14)
      -- We do not support legacy packages anymore in resilient.
      SU.error(("Package '%s' does not use the current package API"):format(packname))
   end
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

--- (Override) Finish the document.
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
