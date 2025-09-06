--- Text extraction mixin for the typesetter.
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
-- @module typesetters.mixins.totext

--- Flatten a node list into just its string representation.
-- @tparam table nodes Typeset nodes
-- @treturn string Text reconstruction of the nodes
local function nodesToText (nodes)
   -- A real interword space width depends on several settings (depending on variable
   -- spaces being enabled or not, etc.), and the computation below takes that into
   -- account.
   local iwspc = SILE.shaper:measureSpace(SILE.font.loadDefaults({}))
   local iwspcmin = (iwspc.length - iwspc.shrink):tonumber()

   local string = ""
   for i = 1, #nodes do
      local node = nodes[i]
      if node.is_nnode or node.is_unshaped then
         string = string .. node:toText()
      elseif node.is_glue or node.is_kern then
         -- What we want to avoid is "small" glues or kerns to be expanded as full
         -- spaces.
         -- Comparing them to half of the smallest width of a possibly shrinkable
         -- interword space is fairly fragile and empirical: the content could contain
         -- font changes, so the comparison is wrong in the general case.
         -- It's a simplistic approach. We cannot really be sure what a "space" meant
         -- at the point where the kern or glue got absolutized.
         if node.width:tonumber() > iwspcmin * 0.5 then
            string = string .. " "
         end
      elseif node.is_liner then
         -- A liner box just wraps other regular nodes, we can safely recurse into it.
         string = string .. nodesToText(node.inner)
      elseif not (node.is_zerohbox or node.is_migrating) then
         -- Here, typically, the main case is an hbox.
         -- Extracting its content could be possible in some regular cases...
         local extract = nil
         if node.value and node.is_unwrappable then
            -- Sometimes we probably know what's in the box under reasonable assumptions.
            extract = type(node.value) == "table" and #node.value > 0 and node.value
         end
         -- There could be other case of unwrappable boxes, to consider later on a case
         -- by-case basis.
         if extract then
            string = string .. nodesToText(extract)
         else
            -- Yet, we cannot take a general decision, as it is a versatile object and
            -- its outputYourself() method could moreover have been redefined to do fancy
            -- things. Better warn and skip.
            SU.warn("Some hbox's content could not be converted to text: " .. tostring(node))
         end
      end
   end
   -- Trim leading and trailing spaces, and simplify internal spaces.
   return pl.stringx.strip(string):gsub("%s%s+", " ")
end

---
-- @type typesetter
-- @see typesetters.silent
local typesetter = { -- Not a real class, just a mixin
   _name = "mixin.totext"
}

--- Convert a SILE AST to a textual representation.
-- This is similar to `SU.ast.contentToString()`, but it performs a full
-- typesetting of the content, and then reconstructs the text from the
-- typeset nodes.
-- @tparam table content SILE AST to process
-- @treturn string Textual representation of the content
function typesetter:contentToText (content)
   self:pushState()
   -- Switch to horizontal-restricted mode, paragraphs are not wanted here.
   self.state.hmodeOnly = true
   -- Disable any contextual command that could interfere with text output.
   SILE.resilient.cancelContextualCommands("textual", function ()
      SILE.process(content)
   end)
   local text = nodesToText(self.state.nodes)
   self:popState()
   return text
end

return typesetter
