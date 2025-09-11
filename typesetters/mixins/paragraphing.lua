--- Paragraphing mixin for the typesetter.
--
-- Some code in this file comes from SILE's core typesetter.
--
-- License: MIT.
-- Copyright (c) The SILE Organization / Simon Cozens et al.
--
-- This file is part of re·sil·ient, a set of extensions to SILE.
--
-- License: MIT.
-- Copyright (c) 2025 Omikhkeia / Didier Willis
--
-- There is still some **code smell** in this component.
--
-- This component provides methods for line-breaking paragraphs, and assembling them
-- into vertical boxes.
--
-- @module typesetters.mixins.paragraphing

local linebreak = require("typesetters.algorithms.knuthplass")

local inf_bad = 10000 -- Penalty value for forced breaks in Knuth-Plass
-- CODE SMELL: This is repeated in typesetters.algorithms.knuthplass
-- The numeric value (10000, -10000) is also used directly in a few places,
-- such as the "plain" commands...

---
-- @type typesetter
-- @see typesetters.silent
local typesetter = { -- Not a real class, just a mixin
   _name = "mixin.paragraphing"
}

--- Box up the current node list into a list of vboxes.
--
-- SMELL: Bad name, undocumented behavior, ad-hoc logic...
-- It does too many things at once, and should be refactored.
--
-- Empties self.state.nodes, breaks into lines, puts lines into vbox, adds vbox to
-- Turns a node list into a list of vboxes
function typesetter:boxUpNodes ()
   local nodelist = self.state.nodes
   if #nodelist == 0 then
      return {}
   end
   for j = #nodelist, 1, -1 do
      if not nodelist[j].is_migrating then
         if nodelist[j].discardable then
            table.remove(nodelist, j)
         else
            break
         end
      end
   end
   while #nodelist > 0 and nodelist[1].is_penalty do
      table.remove(nodelist, 1)
   end
   if #nodelist == 0 then
      return {}
   end

   nodelist = self:shapeAll(nodelist) -- FIXME HOW MANY PLACES DO WE NEED TO CALL THIS?
   self.state.nodes = nodelist -- FIXME CODE SMELL (BIDI BREAKS OTHERWISE)

   local parfillskip = SILE.settings:get("typesetter.parfillskip")
   parfillskip.discardable = false
   self:pushGlue(parfillskip)
   self:pushPenalty(-inf_bad)
   SU.debug("typesetter", function ()
      return "Boxed up " .. (#nodelist > 500 and #nodelist .. " nodes" or SU.ast.contentToString(nodelist))
   end)
   local breakWidth = SILE.settings:get("typesetter.breakwidth") or self.frame:getLineWidth()
   local lines = self:breakIntoLines(nodelist, breakWidth)
   local vboxes = {}
   for index = 1, #lines do
      local line = lines[index]
      local migrating = {}
      -- Move any migrating material
      local nodes = {}
      for i = 1, #line.nodes do
         local node = line.nodes[i]
         if node.is_migrating then
            for j = 1, #node.material do
               migrating[#migrating + 1] = node.material[j]
            end
         else
            nodes[#nodes + 1] = node
         end
      end
      local vbox = SILE.types.node.vbox({ nodes = nodes, ratio = line.ratio })
      local pageBreakPenalty = 0
      if #lines > 1 and index == 1 then
         pageBreakPenalty = SILE.settings:get("typesetter.widowpenalty")
      elseif #lines > 1 and index == (#lines - 1) then
         pageBreakPenalty = SILE.settings:get("typesetter.orphanpenalty")
      elseif line.is_broken then
         pageBreakPenalty = SILE.settings:get("typesetter.brokenpenalty")
      end
      vboxes[#vboxes + 1] = self:leadingFor(vbox, self.state.previousVbox)
      vboxes[#vboxes + 1] = vbox
      for i = 1, #migrating do
         vboxes[#vboxes + 1] = migrating[i]
      end
      self.state.previousVbox = vbox

      if line.hanged then
         -- Do not break the frame in hanged lines for dropped capitals etc.
         vboxes[#vboxes+1] = SILE.types.node.penalty(10000)
      elseif pageBreakPenalty > 0 then
         SU.debug("typesetter", "adding penalty of", pageBreakPenalty, "after", vbox)
         vboxes[#vboxes + 1] = SILE.types.node.penalty(pageBreakPenalty)
      end
   end
   return vboxes
end


--- Break a list of nodes into lines.
--
-- SMELL how many times are we invoking shapeAll() in the whole process?
-- How badly the bidi package hacks into these things?
--
-- @tparam table nodelist List of nodes to break into lines
-- @tparam SILE.types.length breakWidth Target width for the lines
-- @treturn table List of lines
function typesetter:breakIntoLines (nodelist, breakWidth)
   nodelist = self:shapeAll(nodelist)

   -- NOTE: There's some scope confusion between what should be settings and
   -- current typesetter states. It might take time to be properly
   -- addressed.
   -- INTENT: Hanged lines are tracked (counted) so as to propagate the
   -- remaining offset to the next paragraph.
   local hangIndent = SILE.settings:get("current.hangIndent")
   self.state.hangAfter = SILE.settings:get("current.hangAfter")
   SILE.settings:set("linebreak.hangIndent", hangIndent or 0)
   SILE.settings:set("linebreak.hangAfter", self.state.hangAfter)

   local breakpoints, nlist = linebreak:doBreak(nodelist, breakWidth)
   local lines = self:breakpointsToLines(breakpoints, nlist)

   if self.state.hangAfter == 0 then
      SILE.settings:set("current.hangIndent", nil)
      SILE.settings:set("current.hangAfter", nil)
   else
      SILE.settings:set("current.hangAfter", self.state.hangAfter)
   end
   return lines
end

--- Inhibit leading insertion before the next line.
--
-- FIXME DUBIOUS NEED.
-- And this is problematic in general baseline-grid layout.
function typesetter:inhibitLeading ()
   self.state.previousVbox = nil
end

--- Compute the leading (interline space) between two lines.
--
-- FIXME DUBIOUS APPROACH.
-- Somewhat TeX-like in essence... But the grid package's hacks into it are dubious.
-- This may have to be revisited if the page·ant page builder ever sees
-- the light... In some future not yet written.
--
-- @tparam SILE.types.node.vbox vbox Current line box
-- @tparam SILE.types.node.vbox|nil previous Previous line box, if any
-- @treturn SILE.types.node.vglue Leading glue to insert
function typesetter:leadingFor (vbox, previous)
   -- Insert leading
   SU.debug("typesetter", "   Considering leading between two lines:")
   SU.debug("typesetter", "   1)", previous)
   SU.debug("typesetter", "   2)", vbox)
   if not previous then
      return SILE.types.node.vglue()
   end
   local prevDepth = previous.depth
   SU.debug("typesetter", "   Depth of previous line was", prevDepth)
   local bls = SILE.settings:get("document.baselineskip")
   local depth = bls.height:absolute() - vbox.height:absolute() - prevDepth:absolute()
   SU.debug("typesetter", "   Leading height =", bls.height, "-", vbox.height, "-", prevDepth, "=", depth)

   -- the lineskip setting is a vglue, but we need a version absolutized at this point, see #526
   local lead = SILE.settings:get("document.lineskip").height:absolute()
   if depth > lead then
      return SILE.types.node.vglue(SILE.types.length(depth.length, bls.height.stretch, bls.height.shrink))
   else
      return SILE.types.node.vglue(lead)
   end
end

--- Turn a list of breakpoints into a list of lines.
--
-- @tparam table breakpoints Breakpoints as returned by the linebreaking algorithm
-- @tparam table nodelist Corresponding list of nodes
-- @treturn table List of lines
function typesetter:breakpointsToLines (breakpoints, nodelist)
   local linestart = 1
   local lines = {}
   local nodes = nodelist -- FIXME TRANSITIONAL

   for i = 1, #breakpoints do
      local point = breakpoints[i]
      if point.position ~= 0 then
         local slice = {}
         local seenNonDiscardable = false
         local seenLiner = false
         local lastContentNodeIndex

         for j = linestart, point.position do
            local currentNode = nodes[j]
            if
               -- FIXME CODE SMELL: This is a kludge of sorts to detect...
               not currentNode.discardable
               and not (currentNode.is_glue and not currentNode.explicit)
               and not currentNode.is_zero
               -- My addition, but debatable...
               -- See removeEndingStuff().
               and not currentNode.is_kern
            then
               -- actual visible content starts here
               lastContentNodeIndex = #slice + 1
            end
            if not seenLiner and lastContentNodeIndex then
               -- Any stacked liner (unclosed from a previous line) is reopened on
               -- the current line.
               seenLiner = self:_repeatEnterLiners(slice)
               lastContentNodeIndex = #slice + 1
            end
            if currentNode.is_discretionary and currentNode.used then
               -- This is the used (prebreak) discretionary from a previous line,
               -- repeated. Replace it with a clone, changed to a postbreak.
               currentNode = currentNode:cloneAsPostbreak()
            end
            slice[#slice + 1] = currentNode
            if currentNode then
               if not currentNode.discardable then
                  seenNonDiscardable = true
               end
               seenLiner = self:_processIfLiner(currentNode) or seenLiner
            end
         end
         if not seenNonDiscardable then
            -- Slip lines containing only discardable nodes (e.g. glues).
            SU.debug("typesetter", "Skipping a line containing only discardable nodes")
            linestart = point.position + 1
         else
            local is_broken = false
            if slice[#slice].is_discretionary then
               -- The line ends, with a discretionary:
               -- repeat it on the next line, so as to account for a potential postbreak.
               linestart = point.position
               -- And mark it as used as prebreak for now.
               slice[#slice]:markAsPrebreak()
               -- We'll want a "brokenpenalty" eventually (if not an orphan or widow)
               -- to discourage page breaking after this line.
               is_broken = true
            else
               linestart = point.position + 1
            end


            if lastContentNodeIndex then
               self:_repeatLeaveLiners(slice, lastContentNodeIndex + 1)
            end

            self:_pruneDiscardables(slice)

            -- Track hanged lines
            if self.state.hangAfter then
               if self.state.hangAfter < 0
                  and (point.left > 0 or point.right > 0) then
                  -- count a hanged line
                  self.state.hangAfter = self.state.hangAfter + 1
               elseif self.state.hangAfter > 0
                  and point.left == 0 and point.right == 0 then
                  -- count a full line
                  self.state.hangAfter = self.state.hangAfter - 1
               end
            end

            -- Then only we can add some extra margin glue...
            local mrg = self:getMargins()
            self:_addrlskip(slice, mrg, point.left, point.right)

            -- And compute the line...
            local ratio = self:computeLineRatio(point.width, slice)

            -- Re-shuffle liners, if any, into their own boxes.
            if seenLiner then
               slice = self:_reboxLiners(slice)
            end

            local thisLine = { ratio = ratio, nodes = slice, is_broken = is_broken }
            lines[#lines + 1] = thisLine

            if self.state.hangAfter and self.state.hangAfter < 0 then
               -- Mark the line as hanged so we can later add a penalty:
               -- Surely we don't want a frame break in the middle of dropped
               -- capitals &c.
               thisLine.hanged = true
            end
         end
      end
   end
   if linestart < #nodes then
      -- Abnormal, but warn so that one has a chance to check which bits
      -- are missing at output.
      SU.warn("Internal typesetter error " .. (#nodes - linestart) .. " skipped nodes")
   end
   return lines
end

--- Remove trailing and leading discardable nodes from a slice
--
-- The slice is modified in place.
--
-- For leading nodes, this means glues and penalties (i.e. all discardable nodes).
-- For trailing nodes, this means glues (unless made non-discardable explicitly), zero boxes,
-- and trailing kerns (if consecutive).
--
-- FIXME: Clearly messy logic here, needs a clarification pass.
--
-- @tparam table slice Flat nodes from current line
function typesetter:_pruneDiscardables (slice)
   -- Leading discardables
   while slice[1].discardable do -- FIXME CODE SMELL WHY HERE?
      -- Remove any leading discardable nodes = in SILE's lingo, glues and penalties
      -- (but not kerns and zero boxes).
      table.remove(slice, 1)
   end

   -- Trailing discardables
   local npos = #slice
   -- Remove trailing glues and zero boxes, and trailing kerns.
   while npos > 1 do
      if not(
         slice[npos].discardable -- glue (unless made non-discardable explicitly) or penalty
         or slice[npos].is_zero -- zero box
         -- FIXME
         -- TeXBook ch. 14, seems to say kerns are discardable too.
         -- But if they were, TeXBook app. D "dirty tricks" for hanging punctuation
         -- would not work. The latter says however: "Consecutive glue, kern, and penalty
         -- items disappear at a break." (referring vaguely to ch. 14)"
         -- So kerns are not really discardable, but consecutive kerns are.
         -- Erm. This works for the overhang logic, but we are quite far from
         -- the original wording here, which is quite opaque...
         or (slice[npos].is_kern and slice[npos - 1].is_kern)
      ) then
         break
      end
      npos = npos - 1
   end
   for i = npos + 1, #slice do
      slice[i] = nil
   end
end

--- Add left and right skips to a line slice.
--
-- It takes taking into account the writing direction of the current frame,
-- and potential hanging indents on either side.
--
-- (Breaking change)
-- Compare to SILE's original typesetter:addrlskip() method, it doesn't do
-- anything else than handling the margin skips.
--
-- @tparam table slice Line slice
-- @tparam table margins Margins (`lskip` and `rskip` glues)
-- @tparam number hangLeft Amount to hang on the left side (absolute number)
-- @tparam number hangRight Amount to hang on the right side (absolute number)
function typesetter:_addrlskip (slice, margins, hangLeft, hangRight)
   local LTR = self.frame:writingDirection() == "LTR"
   local rskip = margins[LTR and "rskip" or "lskip"]
   if not rskip then
      rskip = SILE.types.node.glue(0)
   end
   if hangRight and hangRight > 0 then
      rskip = SILE.types.node.glue({ width = rskip.width:tonumber() + hangRight })
   end
   rskip.value = "margin"
   table.insert(slice, rskip)
   table.insert(slice, SILE.types.node.zerohbox()) -- CODE SMELL: WHY?
   local lskip = margins[LTR and "lskip" or "rskip"]
   if not lskip then
      lskip = SILE.types.node.glue(0)
   end
   if hangLeft and hangLeft > 0 then
      lskip = SILE.types.node.glue({ width = lskip.width:tonumber() + hangLeft })
   end
   lskip.value = "margin"
   table.insert(slice, 1, lskip)
   table.insert(slice, 1, SILE.types.node.zerohbox()) -- CODE SMELL: WHY?
end

function typesetter:addrlskip (slice, margins) -- FIXME TRANSITIONAL COMPATIBILITY
   SU.warn("The sile·nt typesetter does not expose the addrlskip() method, what are you trying to do?")
   self:_addrlskip(slice, margins)
end

--- Compute the natural width and ratio for a line slice.
--
-- The natural width is the width of the line if no stretching or shrinking
-- were to occur.
-- The ratio is the amount of stretch or shrink that would be needed to
-- make the line fit exactly the break width.
--
-- SMELL: This should be a public method.
-- But **ptable.sile** uses it, as the natural width of the line is not
-- stored anywhere else. Bad design.
--
-- @tparam SILE.types.length breakwidth Target width for the line
-- @tparam table slice Line slice
-- @treturn number ratio Stretching (>0) or shrinking (<0) ratio
-- @treturn SILE.types.length naturalTotals Natural width of the line
function typesetter:computeLineRatio (breakwidth, slice)
   local naturalTotals = SILE.types.length()

   -- From the line end, account for the margin but skip any trailing
   -- glues (spaces to ignore) and zero boxes until we reach actual content.
   -- CODE SMELL:
   -- Theoretically, we have already removed most of these earlier.
   -- But for some reason, addrlskip() adds some zero boxes in the mix,
   local npos = #slice
   while npos > 1 do
      if (slice[npos].is_glue and slice[npos].discardable) or slice[npos].is_zero then
         if slice[npos].value == "margin" then
            naturalTotals:___add(slice[npos].width)
            break-- Stop here at margin glue
         end
      else
         break
      end
      npos = npos - 1
   end

   -- Due to discretionaries, keep track of seen parent nodes
   local seenNodes = {}
   -- CODE SMELL: Not sure which node types were supposed to be skipped
   -- at initial positions in the line!
   local skipping = true

   -- Until end of actual content
   for i = 1, npos do
      local node = slice[i]
      if node.is_box then
         skipping = false
         if node.parent and not node.parent.hyphenated then
            if not seenNodes[node.parent] then
               naturalTotals:___add(node.parent:lineContribution())
            end
            seenNodes[node.parent] = true
         else
            naturalTotals:___add(node:lineContribution())
         end
      elseif node.is_penalty and node.penalty == -inf_bad then
         skipping = false
      elseif node.is_discretionary then
         skipping = false
         local seen = node.parent and seenNodes[node.parent]
         if not seen then
            if node.used then
               if node.is_prebreak then
                  naturalTotals:___add(node:prebreakWidth())
                  node.height = node:prebreakHeight()
               else
                  naturalTotals:___add(node:postbreakWidth())
                  node.height = node:postbreakHeight()
               end
            else
               naturalTotals:___add(node:replacementWidth():absolute())
               node.height = node:replacementHeight():absolute()
            end
         end
      elseif not skipping then
         naturalTotals:___add(node.width)
      end
   end

   local _left = breakwidth:tonumber() - naturalTotals:tonumber()
   local ratio = _left / naturalTotals[_left < 0 and "shrink" or "stretch"]:tonumber()
   ratio = math.max(ratio, -1)
   return ratio, naturalTotals
end

return typesetter
