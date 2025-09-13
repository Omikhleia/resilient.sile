--- Horizontal box builder mixin for the typesetter.
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
-- Logic for building an hbox from content.
--
-- It returns the hbox and an horizontal list of (migrating) elements
-- extracted outside of it.
-- None of these are pushed to the typesetter node queue. The caller
-- is responsible of doing it, if the hbox is built for anything
-- else than e.g. measuring it. Likewise, the call has to decide
-- what to do with the migrating content.
--
-- Pre-requisites:
--
--  - The typesetter has a `state.hmodeOnly` boolean flag,
--  - The typesetter has a `shapeAll()` method,
--  - The typesetter has a `frame` object with appropriate methods.
--
-- @module typesetters.mixins.hbox

local bidi = require("typesetters.algorithms.bidi")

---
-- @type typesetter
-- @see typesetters.silent
local typesetter = { -- Not a real class, just a mixin
   _name = "mixin.hbox"
}

--- Make an hbox from some content.
-- The content is processed in horizontal-restricted mode, and shaped.
-- Migrating nodes (typically footnotes) are extracted from the content
-- and returned separately.
-- The typesetter is reponsible, if it pushes the hbox for output,
-- for pushing the migrating nodes too, typically just after the hbox.
-- The idea here is that migrating nodes are not part of the hbox,
-- but need to be re-inserted in the main horizontal list at the same place
-- as the hbox.
-- @tparam function content AST content to process
-- @treturn SILE.types.node.hbox Resulting hbox
-- @treturn table List of migrating nodes extracted from the content
function typesetter:makeHbox (content)
   local recentContribution = {}
   local migratingNodes = {}

   self:pushState()
   self.state.hmodeOnly = true
   SILE.process(content)

   -- We must do a first pass for shaping the nnodes:
   -- This is also where italic correction may occur.
   local nodelist = bidi.splitNodelistIntoBidiRuns(self.state.nodes, self.frame:writingDirection())
   local nodes = self:shapeAll(nodelist)
   nodes = bidi.reorder(nodes, self.frame:writingDirection())

   -- Then we can process and measure the nodes.
   local l = SILE.types.length()
   local h, d = SILE.types.length(), SILE.types.length()
   for i = 1, #nodes do
      local node = nodes[i]
      if node.is_migrating then
         migratingNodes[#migratingNodes + 1] = node
      elseif node.is_discretionary then
         -- HACK https://github.com/sile-typesetter/sile/issues/583
         -- Discretionary nodes have a null line contribution...
         -- But if discretionary nodes occur inside an hbox, since the latter
         -- is not line-broken, they will never be marked as 'used' and will
         -- evaluate to the replacement content (if any)...
         recentContribution[#recentContribution + 1] = node
         l = l + node:replacementWidth():absolute()
         -- The replacement content may have ascenders and descenders...
         local hdisc = node:replacementHeight():absolute()
         local ddisc = node:replacementDepth():absolute()
         h = hdisc > h and hdisc or h
         d = ddisc > d and ddisc or d
      -- By the way it's unclear how this is expected to work in TTB
      -- writing direction. For other type of nodes, the line contribution
      -- evaluates to the height rather than the width in TTB, but the
      -- whole logic might then be dubious there too...
      else
         recentContribution[#recentContribution + 1] = node
         l = l + node:lineContribution():absolute()
         h = node.height > h and node.height or h
         d = node.depth > d and node.depth or d
      end
   end
   self:popState()

   local hbox = SILE.types.node.hbox({
      height = h,
      width = l,
      depth = d,
      value = recentContribution,
      is_unwrappable = true, -- Several hbox re-wrapping layers may use a value field.
                             -- This is annoying for contentToText() extraction below,
                             -- but here we know what we are doing.
      outputYourself = function (box, atypesetter, line)
         local ox = atypesetter.frame.state.cursorX
         local oy = atypesetter.frame.state.cursorY
         SILE.outputter:setCursor(atypesetter.frame.state.cursorX, atypesetter.frame.state.cursorY)
         SU.debug("hboxes", function ()
            local isRtl = atypesetter.frame:writingDirection() == "RTL"
            -- setCursor is also invoked by the internal (wrapped) hboxes etc.
            -- so we must show our debug box before outputting its content.
            if isRtl then
               SILE.outputter:setCursor(ox - box:scaledWidth(line), oy)
            end
            SILE.outputter:debugHbox(box, box:scaledWidth(line))
            if isRtl then
               SILE.outputter:setCursor(ox, oy)
            end
            return "Drew debug outline around hbox"
         end)
         for _, node in ipairs(box.value) do
            node:outputYourself(atypesetter, line)
         end
         atypesetter.frame.state.cursorX = ox
         atypesetter.frame.state.cursorY = oy
         atypesetter.frame:advanceWritingDirection(box:scaledWidth(line))
      end,
   })
   return hbox, migratingNodes
end

--- Push an horizontal list of nodes to the typesetter node list.
-- This is a convenience method, notably used for pushing migrating nodes
-- extracted from an hbox.
-- @tparam table hlist List of nodes
function typesetter:pushHlist (hlist)
   for _, h in ipairs(hlist) do
      self:pushHorizontal(h)
   end
end

return typesetter
