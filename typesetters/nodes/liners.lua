--- Liner nodes for supporting multi-line constructs in the typesetter.
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
-- These nodes are used to mark and track constructs that may span
-- over several lines, with some effect applied on each line (repeatedly).
-- as a paragraph is being typeset and line-broken.
--
-- Examples of such constructs are:
--
--  - Underlined or strikethrough content,
--  - Links (which can be long URLs at unpleasant places),
--  - Redacted content,
--  - etc.
--
-- The content may be line-broken, and each bit on each line will be wrapped
-- into a box.
-- These boxes will be formatted according to some output logic, possibly
-- with some effects applied (e.g. decorations), besides outputting the content
-- itself if wanted.
--
-- This modules defines three node types:
--
--  - `linerEnterNode` and `linerLeaveNode` shall always be used in pairs.
--  - `linerBox` is a box node for a single-line content.
--
-- As Sith Lords, the enter/leave nodes always come in pairs, or the Force will
-- be unbalanced.
-- The typesetter is responsible for introducing one at the start of some content,
-- the other at the end.
-- After having line-broken the paragraph, the typesetter must then look for
-- these pairs, and for each pair found, extract the content between them,
-- re-assemble it into a linerBox node.
-- When doing so, it should transfer the output method from the enter node to the
-- linerBox.
--
-- @module typesetters.nodes.liners

--- Liner enter node.
-- @type linerEnterNode
-- @see linerBox
local linerEnterNode = pl.class(SILE.types.node.hbox)

--- (Constructor) Create a new liner enter node.
-- @tparam string name Name of the liner
-- @tparam function outputMethod Output method for eventual liner boxes
function linerEnterNode:_init (name, outputMethod)
   SILE.types.node.hbox._init(self)
   self.outputMethod = outputMethod
   self.name = name
   self.is_enter = true
end

--- Clone a liner enter node.
-- @treturn linerEnterNode Clone of the node
function linerEnterNode:clone ()
   return linerEnterNode(self.name, self.outputMethod)
end

--- Output the node.
-- Liner enter nodes should never make it to output, so this raises an error.
-- @raise Error
function linerEnterNode:outputYourself ()
   SU.error("A liner enter node " .. tostring(self) .. "'' made it to output", true)
end

function linerEnterNode:__tostring ()
   return "+L[" .. self.name .. "]"
end

--- Liner leave node.
-- @type linerLeaveNode
-- @see linerBox
local linerLeaveNode = pl.class(SILE.types.node.hbox)

--- (Constructor) Create a new liner leave node.
-- @tparam string name Name of the liner
function linerLeaveNode:_init (name)
   SILE.types.node.hbox._init(self)
   self.name = name
   self.is_leave = true
end

--- Clone a liner leave node.
-- @treturn linerLeaveNode Clone of the node
function linerLeaveNode:clone ()
   return linerLeaveNode(self.name)
end

--- Output the node.
-- Liner leave nodes should never make it to output, so this raises an error.
-- @raise Error
function linerLeaveNode:outputYourself ()
   SU.error("A liner leave node " .. tostring(self) .. "'' made it to output", true)
end

function linerLeaveNode:__tostring ()
   return "-L[" .. self.name .. "]"
end

--- Liner box node.
-- @type linerBox
local linerBox = pl.class(SILE.types.node.hbox)

--- (Constructor) Create a new liner box.
-- @tparam string name Name of the liner
-- @tparam function outputMethod Output method
function linerBox:_init (name, outputMethod)
   SILE.types.node.hbox._init(self)
   self.width = SILE.types.length()
   self.height = SILE.types.length()
   self.depth = SILE.types.length()
   self.name = name
   self.inner = {}
   self.is_liner = true
   self.outputYourself = outputMethod
end

--- Append a content node to the liner box.
-- This updates the box dimensions as needed.
-- @tparam node node Node to append
function linerBox:append (node)
   self.inner[#self.inner + 1] = node
   if node.is_discretionary then
      -- Discretionary nodes don't have a width of their own.
      if node.used then
         if node.is_prebreak then
            self.width:___add(node:prebreakWidth())
         else
            self.width:___add(node:postbreakWidth())
         end
      else
         self.width:___add(node:replacementWidth())
      end
   else
      self.width:___add(node.width:absolute())
   end
   self.height = SU.max(self.height, node.height)
   self.depth = SU.max(self.depth, node.depth)
end

--- Count the number of nodes in the liner box.
-- @treturn number Number of nodes
function linerBox:count ()
   return #self.inner
end

--- Output the line box content.
-- This should be called from the ouput routine passed at construction,
-- to output the actual content of the liner.
-- @param typesetter Current typesetter
-- @param line Current line properties
function linerBox:outputContent (typesetter, line)
   for _, node in ipairs(self.inner) do
      node.outputYourself(node, typesetter, line)
   end
end

function linerBox:__tostring ()
   return "*L["
      .. self.name
      .. "]H<"
      .. tostring(self.width)
      .. ">^"
      .. tostring(self.height)
      .. "-"
      .. tostring(self.depth)
      .. "v"
end

return {
   linerEnterNode = linerEnterNode,
   linerLeaveNode = linerLeaveNode,
   linerBox = linerBox
}
