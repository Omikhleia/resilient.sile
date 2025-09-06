--- Speaker change node for the typesetter.
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
-- Some typography conventions use an em-dash at the start of a paragraph line
-- to denote a speaker change in a dialogue.
-- This is the case in particular in French and Turkish typography.
-- All spaces following an em-dash at the beginning of a paragraph
-- in the input should be replaced by a single _fixed_ inter-word space,
-- so that subsequent dialogue lines all start identically, while other
-- inter-wordspaces may still be variable for justification purposes.
--
-- @module typesetters.nodes.speaker

--- Speaker change node.
-- @type speakerChangeNode
local speakerChangeNode = pl.class(SILE.types.node.unshaped)

--- Shape the node.
-- The typesetter can insert this node when it detects a speaker change
-- at the start of a paragraph, i.e. an em-dash followed by some space.
-- The typesetter is responsible for passing the correct text to this node,
-- i.e. the em-dash followed by a regular space, as in "— Some dialogue".
-- This special unshaped node subclass, when shaped, replaces the
-- shaped space (now a glue) by a fixed-width kern.
-- @treturn table Array of shaped nodes (nnodes, glues, penalties...)
function speakerChangeNode:shape ()
   local nodes = self._base.shape(self)
   local spc = nodes[2]
   if spc and spc.is_glue then
      -- Switch the variable-space glue to a fixed kern
      nodes[2] = SILE.types.node.kern({ width = spc.width.length })
      nodes[2].parent = self.parent
   else
      -- Should not occur:
      -- How could it possibly be shaped differently?
      -- If correctly passed the expected test upon creation, then the first
      -- node should be the em-dash (shped as a `SILE.types.node.nnode`),
      -- and the secon dnode should be the space following it (shaped as a
      -- `SILE.types.node.glue`).
      SU.warn("Speaker change logic met an unexpected case, this might be a bug")
   end
   return nodes
end

return {
   speakerChangeNode = speakerChangeNode,
}
