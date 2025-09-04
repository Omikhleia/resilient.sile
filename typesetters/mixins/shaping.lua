
--- Shaping mixin for the typesetter.
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
-- This mixin provides methods for shaping unshaped nodes in a node list,
-- with support for automated italic correction (heuristic).
--
-- Pre-requisites:
--
--  - The properties checked on shaped nodes assume the harfbuzz (default) shaper,
--
-- @module typesetters.mixins.shaping

--- Extract the last shaped item from a node list.
-- @tparam table nodelist A list of nodes.
-- @treturn table The last shaped item.
-- @treturn boolean Whether the list contains a glue after the last shaped item.
-- @treturn number|nil The width of a punctuation kern after the last shaped item, if any.
local function getLastShape (nodelist)
   local lastShape
   local hasGlue
   local punctSpaceWidth
   if nodelist then
      -- The node list may contain nnodes, penalties, kern and glue
      -- We skip the latter, and retrieve the last shaped item.
      for i = #nodelist, 1, -1 do
         local n = nodelist[i]
         if n.is_nnode then
            local items = n.nodes[#n.nodes].value.items
            lastShape = items[#items]
            break
         end
         if n.is_kern and n.subtype == "punctspace" then
            -- Some languages such as French insert a special space around
            -- punctuations.
            -- In those case, we have different strategies for handling
            -- italic correction.
            punctSpaceWidth = n.width:tonumber()
         end
         if n.is_glue then
            hasGlue = true
         end
      end
   end
   return lastShape, hasGlue, punctSpaceWidth
end

--- Extract the first shaped item from a node list.
-- @tparam table nodelist A list of nodes.
-- @treturn table The first shaped item.
-- @treturn boolean Whether the list contains a glue before the first shaped item.
-- @treturn number|nil The width of a punctuation kern before the first shaped item, if any.
local function getFirstShape (nodelist)
   local firstShape
   local hasGlue
   local punctSpaceWidth
   if nodelist then
      -- The node list may contain nnodes, penalties, kern and glue
      -- We skip the latter, and retrieve the first shaped item.
      for i = 1, #nodelist do
         local n = nodelist[i]
         if n.is_nnode then
            local items = n.nodes[1].value.items
            firstShape = items[1]
            break
         end
         if n.is_kern and n.subtype == "punctspace" then
            -- Some languages such as French insert a special space around
            -- punctuations.
            -- In those case, we have different strategies for handling
            -- italic correction.
            punctSpaceWidth = n.width:tonumber()
         end
         if n.is_glue then
            hasGlue = true
         end
      end
   end
   return firstShape, hasGlue, punctSpaceWidth
end

--- Compute the italic correction when switching from italic to non-italic.
--
-- Automated italic correction is at best heuristics.
--
-- The strong assumption is that italic is slanted to the right.
--
-- Thus, the part of the character that goes beyond its width is usually maximal at the top of the glyph.
-- E.g. consider a "f", that would be the top hook extent.
--
-- Pathological cases exist, such as fonts with a Q with a long tail, but these will rarely occur in usual languages.
-- For instance, Klingon's "QaQ" might be an issue, but there's not much we can do...
--
-- Another assumption is that we can distribute that extent in proportion with the next character's height.
-- This might not work that well with non-Latin scripts.
--
-- Finally, there are cases where a punctuation character introduced an extra space (as in French typography
-- for high punctuation marks and guillemets), and take it into account for compensating the italic correction.
-- (That is, we only apply a correction if it exceeds that extra space.)
--
-- @tparam table precShape The last shaped item (italic).
-- @tparam table curShape The first shaped item (non-italic).
-- @tparam number|nil|false punctSpaceWidth The width of a punctuation kern between the two items, if applicable.
local function fromItalicCorrection (precShape, curShape, punctSpaceWidth)
   local xOffset
   if not curShape or not precShape then
      xOffset = 0
   elseif precShape.height <= 0 then
      xOffset = 0
   else
      local d = precShape.glyphWidth + precShape.x_bearing
      local delta = d > precShape.width and d - precShape.width or 0
      xOffset = precShape.height <= curShape.height and delta or delta * curShape.height / precShape.height
      if punctSpaceWidth then
         xOffset = xOffset - punctSpaceWidth > 0 and (xOffset - punctSpaceWidth) or 0
      end
   end
   return xOffset
end

--- Compute the italic correction when switching from non-italic to italic.
--
-- Same assumptions as fromItalicCorrection(), but on the starting side of the glyph.
--
-- @tparam table precShape The last shaped item (non-italic).
-- @tparam table curShape The first shaped item (italic).
-- @tparam number|nil|false punctSpaceWidth The width of a punctuation kern between the two items, if applicable.
local function toItalicCorrection (precShape, curShape, punctSpaceWidth)
   local xOffset
   if not curShape or not precShape then
      xOffset = 0
   elseif precShape.depth <= 0 then
      xOffset = 0
   else
      local d = curShape.x_bearing
      local delta = d < 0 and -d or 0
      xOffset = precShape.depth >= curShape.depth and delta or delta * precShape.depth / curShape.depth
      if punctSpaceWidth then
         xOffset = punctSpaceWidth - xOffset > 0 and xOffset or 0
      end
   end
   return xOffset
end

--- Check if a shaped node is in italic-like style.
-- @tparam SILE.node nnode The node to check.
-- @treturn boolean
local function isItalicLike (nnode)
   -- We could do...
   --  return nnode and string.lower(nnode.options.style) == "italic"
   -- But it's probably more robust to use the italic angle, so that
   -- thin italic, oblique or slanted fonts etc. may work too.
   local ot = require("core.opentype-parser")
   local face = SILE.font.cache(nnode.options, SILE.shaper.getFace)
   local font = ot.parseFont(face)
   return font.post.italicAngle ~= 0
end

---
-- @type typesetter
-- @see typesetters.silent
local typesetter = { -- Not a real class, just a mixin
   _name = "mixin.shaping"
}

--- Shape all unshaped nodes in a list.
--
-- This also inserts italic correction nodes if needed (and if enabled).
--
-- @tparam table nodelist A list of nodes, some of which may be unshaped.
-- @treturn table A new list of nodes
function typesetter:shapeAll (nodelist)
   local newNodelist = {}
   local prec
   local precShapedNodes
   local isItalicCorrectionEnabled = SILE.settings:get("typesetter.italicCorrection")
   local isItalicCorrectionPunctuationEnabled = SILE.settings:get("typesetter.italicCorrection.punctuation")
   for _, current in ipairs(nodelist) do
      if current.is_unshaped then
         local shapedNodes = current:shape()

         if isItalicCorrectionEnabled and prec then
            local itCorrOffset
            local isGlue
            if isItalicLike(prec) and not isItalicLike(current) then
               local precShape, precHasGlue = getLastShape(precShapedNodes)
               local curShape, curHasGlue, curPunctSpaceWidth = getFirstShape(shapedNodes)
               isGlue = precHasGlue or curHasGlue
               itCorrOffset = fromItalicCorrection(
                  precShape,
                  curShape,
                  isItalicCorrectionPunctuationEnabled and curPunctSpaceWidth
               )
            elseif not isItalicLike(prec) and isItalicLike(current) then
               local precShape, precHasGlue, precPunctSpaceWidth = getLastShape(precShapedNodes)
               local curShape, curHasGlue = getFirstShape(shapedNodes)
               isGlue = precHasGlue or curHasGlue
               itCorrOffset = toItalicCorrection(
                  precShape,
                  curShape,
                  isItalicCorrectionPunctuationEnabled and precPunctSpaceWidth
               )
            end
            if itCorrOffset and itCorrOffset ~= 0 then
               -- If one of the node contains a glue (e.g. "a \em{proof} is..."),
               -- line breaking may occur between them, so our correction shall be
               -- a glue too.
               -- Otherwise, the font change is considered to occur at a non-breaking
               -- point (e.g. "\em{proof}!") and the correction shall be a kern.
               local makeItCorrNode = isGlue and SILE.types.node.glue or SILE.types.node.kern
               newNodelist[#newNodelist + 1] = makeItCorrNode({
                  width = SILE.types.length(itCorrOffset),
                  subtype = "itcorr",
               })
            end
         end

         pl.tablex.insertvalues(newNodelist, shapedNodes)

         prec = current
         precShapedNodes = shapedNodes
      else
         prec = nil
         newNodelist[#newNodelist + 1] = current
      end
   end
   return newNodelist
end

return typesetter
