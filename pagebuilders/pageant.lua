--- The page·ant "new page builder" for re·sil·ient.
--
-- Derived from SILE's base/default pagebuilder.
--
-- Some code in this file comes from SILE's core pagebuilder.
--
-- License: MIT.
-- Copyright (c) The SILE Organization / Simon Cozens et al.
--
-- This file is part of re·sil·ient, a set of extensions to SILE.
--
-- License: MIT.
-- Copyright (c) 2025 Didier Willis / Omikhkeia
--
-- @module pagebuilders.pageant

--- The page·ant pagebuilder class.
-- @type pagebuilders.pageant

local pagebuilder = pl.class()
pagebuilder.type = "pagebuilder"
pagebuilder._name = "page·ant"

--- (Constructor) Initialize the pagebuilder.
function pagebuilder:_init ()
   self.awful_bad = 1073741823 -- FIXME CODE SMELL: Yet another redefinition of these constants
   self.inf_bad = 10000
   self.eject_penalty = -self.inf_bad
   self.deplorable = 100000
end

--- (Collate a list of vboxes into a single vbox.
--
-- FIXME: This has nothing to do here.
--
-- @tparam table vboxlist A list of vboxes
function pagebuilder:collateVboxes (vboxlist)
   local output = SILE.types.node.vbox()
   output:append(vboxlist)
   return output
end

--- Find the best page break in a list of vboxes.
--
-- Note: Almost 1/3 of the time in a typical SILE in taken iterating through
-- this function. As a result there are some micro-optimizations here that
-- make it a-typical of preferred coding styles. In particular note that
-- we absolutize heavily iterated lengths as early as possible and make
-- make direct calls to their integer amounts, assumed to be in points by
-- the point they are called **without actually checking**!
--
-- @tparam table options Options table (vboxlist, target, force)
function pagebuilder:findBestBreak (options)
   local vboxlist = SU.required(options, "vboxlist", "in findBestBreak")
   local target = SU.required(options, "target", "in findBestBreak", "length")
   local force = options.force or false
   local totalHeight = SILE.types.length()
   local bestBreak = nil
   local leastC = self.inf_bad
   SU.debug("pagebuilder", function ()
      return "Page builder for frame "
         .. SILE.typesetter.frame.id
         .. " called with "
         .. #vboxlist
         .. " nodes, "
         .. tostring(target)
   end)

   -- Skip leading vglues
   -- TODO FIXME CODE SMELL:
   -- Apparent discrepancy which is a mystery to me...
   -- Contrary to the typesetter, we do not check whether the vglue is discardable or explicit!?
   -- See typesetter.setVerticalGlue() and typesetter.outputLinesToPage().
   local i = 1
   while i <= #vboxlist and vboxlist[i].is_vglue do
      i = i + 1
   end

   i = i - 1 -- we are now at the last vglue before the first non-vglue
   local pi
   while i < #vboxlist do
      i = i + 1
      local vbox = vboxlist[i]
      SU.debug("pagebuilder", "Dealing with VBox", vbox)
      if vbox.is_vbox then
         totalHeight:___add(vbox.height)
         totalHeight:___add(vbox.depth)
      elseif vbox.is_vglue then
         totalHeight:___add(vbox.height)
      elseif vbox.is_insertion then
         -- TODO: refactor as hook and without side effects!
         target = SILE.insertions.processInsertion(vboxlist, i, totalHeight, target)
         vbox = vboxlist[i]
      end
      local left = target - totalHeight
      SU.debug("pagebuilder", "I have", left, "left")
      -- if left < -20 then SU.error("\nCatastrophic page breaking failure!"); end
      pi = 0
      if vbox.is_penalty then
         pi = vbox.penalty
      end
      if
         vbox.is_penalty and vbox.penalty < self.inf_bad
         or (vbox.is_vglue and i > 1 and not vboxlist[i - 1].discardable) -- CODE SMELL FIXME
         -- Non discardable vglue are usually explicit ones (but not always)
         -- Those conditions are never explained, I've no idea what the intent is.
      then
         local badness
         SU.debug("pagebuilder", "totalHeight", totalHeight, "with target", target)
         if totalHeight.length.amount < target.length.amount then -- TeX #1039
            -- Account for infinite stretch?
            badness = SU.rateBadness(self.inf_bad, left.length.amount, totalHeight.stretch.amount)
         elseif left.length.amount < totalHeight.shrink.amount then
            badness = self.awful_bad
         else
            badness = SU.rateBadness(self.inf_bad, -left.length.amount, totalHeight.shrink.amount)
         end

         local c
         if badness < self.awful_bad then
            if pi <= self.eject_penalty then
               c = pi
            elseif badness < self.inf_bad then
               c = badness + pi -- plus insert
            else
               c = self.deplorable
            end
         else
            c = badness
         end
         if c < leastC then
            leastC = c
            bestBreak = i
         end

         SU.debug("pagebuilder", "Badness:", c)
         if c == self.awful_bad or pi <= self.eject_penalty then
            SU.debug("pagebuilder", "outputting")
            local onepage = {}
            if not bestBreak then
               bestBreak = i
            end
            for j = 1, bestBreak do
               onepage[j] = table.remove(vboxlist, 1)
            end
            while #onepage > 1 and onepage[#onepage].discardable do
               onepage[#onepage] = nil
            end
            return onepage, pi
         end
      end
   end
   SU.debug("pagebuilder", "No page break here")
   if force and bestBreak then
      local onepage = {}
      for j = 1, bestBreak do
         onepage[j] = table.remove(vboxlist, 1)
      end
      return onepage, pi
   end
   return false
end

return pagebuilder
