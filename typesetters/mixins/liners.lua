--- Liner support mixin for the typesetter.
--
-- Some code in this file comes from SILE's core typesetter,
--
-- License: MIT.
-- Copyright (c) The SILE Organization / Simon Cozens et al.
--
-- This file is part of re·sil·ient, a set of extensions to SILE.
--
-- License: MIT.
-- Copyright (c) 2025 Omikhkeia / Didier Willis
--
-- Pre-requisites:
--
--  - The typesetter has a `state.liners` table, initially empty, used as a stack.
--
-- @module typesetters.mixins.liners

local linerNodes = require("typesetters.nodes.liners")
local linerEnterNode, linerLeaveNode, linerBox = linerNodes.linerEnterNode, linerNodes.linerLeaveNode, linerNodes.linerBox

---
-- @type typesetter
-- @see typesetters.silent
local typesetter = { -- Not a real class, just a mixin
   _name = "mixin.liners"
}

--- Repeat any unclosed liner at the start of the current line.
-- Any unclosed liner is reopened on the current line, so we clone and repeat it.
-- An assumption is that the inserts are done after the current slice content,
-- supposed to be just before meaningful (visible) content.
-- @tparam table slice Flat nodes from current line
-- @treturn boolean Whether a liner was reopened
function typesetter:_repeatEnterLiners (slice)
   local m = self.state.liners
   if #m > 0 then
      for i = 1, #m do
         local n = m[i]:clone()
         slice[#slice + 1] = n
         SU.debug("typesetter.liner", "Reopening liner", n)
      end
      return true
   end
   return false
end

--- Rebox liners in a line slice.
-- All pairs of liners are rebuilt as hboxes wrapping their content.
-- Migrating content, however, must be kept outside the hboxes at top slice level.
-- @tparam table slice Flat nodes from current line
-- @treturn table New reboxed slice
function typesetter:_reboxLiners (slice)
   local outSlice = {}
   local migratingList = {}
   local lboxStack = {}
   for i = 1, #slice do
      local node = slice[i]
      if node.is_enter then
         SU.debug("typesetter.liner", "Start reboxing", node)
         local n = linerBox(node.name, node.outputMethod)
         lboxStack[#lboxStack + 1] = n
      elseif node.is_leave then
         if #lboxStack == 0 then
            SU.error("Multiliner box stacking mismatch" .. node)
         elseif #lboxStack == 1 then
            SU.debug("typesetter.liner", "End reboxing", node, "(toplevel) =", lboxStack[1]:count(), "nodes")
            if lboxStack[1]:count() > 0 then
               outSlice[#outSlice + 1] = lboxStack[1]
            end
         else
            SU.debug("typesetter.liner", "End reboxing", node, "(sublevel) =", lboxStack[#lboxStack]:count(), "nodes")
            if lboxStack[#lboxStack]:count() > 0 then
               local hbox = lboxStack[#lboxStack - 1]
               hbox:append(lboxStack[#lboxStack])
            end
         end
         lboxStack[#lboxStack] = nil
         pl.tablex.insertvalues(outSlice, migratingList)
         migratingList = {}
      else
         if #lboxStack > 0 then
            if not node.is_migrating then
               local lbox = lboxStack[#lboxStack]
               lbox:append(node)
            else
               migratingList[#migratingList + 1] = node
            end
         else
            outSlice[#outSlice + 1] = node
         end
      end
   end
   return outSlice -- new reboxed slice
end

--- Check if a node is a liner, and process it if so, in a stack.
-- @tparam SILE.types.node.xxx node Current node (of any type)
-- @treturn boolean Whether a liner was opened
function typesetter:_processIfLiner (node)
   local entered = false
   if node.is_enter then
      SU.debug("typesetter.liner", "Enter liner", node)
      self.state.liners[#self.state.liners + 1] = node
      entered = true
   elseif node.is_leave then
      SU.debug("typesetter.liner", "Leave liner", node)
      if #self.state.liners == 0 then
         SU.error("Multiliner stack mismatch" .. node)
      elseif self.state.liners[#self.state.liners].name == node.name then
         self.state.liners[#self.state.liners].link = node -- for consistency check
         self.state.liners[#self.state.liners] = nil
      else
         SU.error("Multiliner stack inconsistency" .. self.state.liners[#self.state.liners] .. "vs. " .. node)
      end
   end
   return entered
end

--- Repeat any unclosed liner at some index in the current line slice.
-- @tparam table slice Flat nodes from current line
-- @tparam integer insertIndex Index where to insert the leave liners
function typesetter:_repeatLeaveLiners (slice, insertIndex)
   for _, v in ipairs(self.state.liners) do
      if not v.link then
         local n = linerLeaveNode(v.name)
         SU.debug("typesetter.liner", "Closing liner", n)
         table.insert(slice, insertIndex, n)
      else
         SU.error("Multiliner stack inconsistency" .. v)
      end
   end
end

--- Build a liner around some content.
-- This is the user-facing method for creating such liners in packages.
-- The content may be line-broken, and each bit on each line will be wrapped
-- into a box.
-- These boxes will be formatted according to some output logic.
-- The output method has the same signature as the outputYourself method
-- of a box, and is responsible for outputting the liner inner content with its
-- outputContent() method, possibly surrounded by some additional effects.
-- If we are already in horizontal-restricted mode, the liner is processed
-- immediately, since line breaking won't occur then.
-- @tparam string name Name of the liner (useful for debugging)
-- @tparam table content SILE AST to process
-- @tparam function outputYourself Output method for wrapped boxes
function typesetter:liner (name, content, outputYourself)
   if self.state.hmodeOnly then
      SU.debug("typesetter.liner", "Applying liner in horizontal-restricted mode")
      local hbox, hlist = self:makeHbox(content)
      local lbox = linerBox(name, outputYourself)
      lbox:append(hbox)
      self:pushHorizontal(lbox)
      self:pushHlist(hlist)
   else
      self.state.linerCount = (self.state.linerCount or 0) + 1
      local uname = name .. "_" .. self.state.linerCount
      SU.debug("typesetter.liner", "Applying liner in standard mode")
      local enter = linerEnterNode(uname, outputYourself)
      local leave = linerLeaveNode(uname)
      self:pushHorizontal(enter)
      SILE.process(content)
      self:pushHorizontal(leave)
   end
end

return typesetter
