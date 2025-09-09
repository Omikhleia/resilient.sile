--- Experimental hanging punctuation (overhang) support.
--
-- This file is part of re·sil·ient, a set of extensions to SILE.
--
-- See LIMITATIONS below.
--
-- Knuth said that hanging punctuation is a solved problem...
-- There are (at least) two approaches, for the general case:
--
-- One is to cancel the width of the punctuation and to add the overhang width
-- to the next glue. It thus require a lookahead to check that there is a glue after
-- the punctuation, and to modify it.
--
-- The other is to insert two kerns after the punctuation (one negative, one positive),
-- and to let the Knuth-Plass line breaker do its job (see TeXbook, app. D "dirty tricks").
--
-- This implementation uses the second approach.
--
-- Both approaches requires some tweaks at the node breaking (segmenter) level,
-- so this is what we do here, though in a monkey-patch way.
--
-- Discretionary nodes neeed another dedicated approach.
-- It's simpler, in a way, because we can just tweak the width of the prebreak content.
--
-- @license MIT
-- @copyright (c) 2025 Omikhkeia / Didier Willis
-- @module resilient.patches.overhang
--
SU.debug("resilient.patches", "Patching SILE for experimental overhang support")

-- Table of punctuation marks to consider for overhang,
-- with a default ratio (somewhat emppirical, overridable by settings).
local overhang = {
   -- Latin
   [","] = { name = "comma", ratio = 0.8 }, -- U+002C COMMA
   ["."] = { name = "period", ratio = 0.8 }, -- U+002E FULL STOP
   [":"] = { name = "colon", ratio = 0.3 }, -- U+003A COLON
   [";"] = { name = "semicolon", ratio = 0.3 }, -- U+003B SEMICOLON
   ["!"] = { name = "exclamation", ratio = 0.3 }, -- U+0021 EXCLAMATION MARK
   ["?"] = { name = "question", ratio = 0.3 }, -- U+003F QUESTION MARK
   ["—"] = { name = "emdash", ratio = 0.2 }, -- U+2014 EM DASH
   ["-"] = { name = "hyphen", ratio = 0.45 }, -- U+002D HYPHEN-MINUS
   -- Arabic
   ["،"] = { name = "arabic.comma", ratio = 0.8 }, -- U+060C ARABIC COMMA
   ["۔"] = { name = "arabic.period", ratio = 0.8 }, -- U+06D4 ARABIC FULL STOP
   -- CJK
   -- Not covered, this author doesn't know expectations for CJK punctuation hanging.
}

-- A generic setting to enable/disable all overhang.
SILE.settings:declare({
   parameter = "experimental.overhang",
   type = "boolean",
   default = false,
   help = "Whether to enable punctuation overhang into the margin.",
})

-- Specific settings for each punctuation type
for punct, spec in pairs(overhang) do
   SILE.settings:declare({
      parameter = "experimental.overhang." .. spec.name,
      type = "number",
      default = spec.ratio,
      help = "The proportion of the width of a '" .. punct .. "' (" .. spec.name .. ") to hang into the right margin.",
   })
end

local function overhangWidth (item, ratio)
   return (item.glyphWidth + item.x_bearing) * ratio
end

--- Hook into the Unicode node maker to insert the overhang logic.
-- @type SILE.nodeMakers.unicode

local unicode = SILE.nodeMakers.unicode
local oldHandleWordBreak = unicode.handleWordBreak

--- (Hard-patch) Add a makeOverhang() method to the unicode node maker.
-- @param self Instance pointer
-- @tparam number w Width of the overhang
unicode.makeOverhang = function (self, w)
   SU.debug("experimental.overhang", "Making overhang of width ", w)
   coroutine.yield(SILE.types.node.kern({
      width = -w,
   }))
   coroutine.yield(SILE.types.node.kern({
       width = w,
   }))
   self.lastnode = "kern"
end

--- (Hard-patch) Override the handleWordBreak method.
--
-- LIMITATIONS:
--
-- This will NOT work for languages that inherit from unicode but override handleWordBreak,
-- such as:
--
--  - French (because of the special space rules before punctuation)
--  - Czech, Spanish, and others (because of special handling for repeated dashes)
--
-- So this experiment is not a general solution, but raises other questions on how the
-- various Unicode segmenters work in SILE.
-- @param self Instance pointer
-- @tparam table item The item to handle
unicode.handleWordBreak = function (self, item)
   if overhang[item.text] and SILE.settings:get("experimental.overhang") then
      SU.debug("experimental.overhang", "Handling overhang for ", item.text)
      self:makeToken()
      self:addToken(item.text, item)
      local spec = overhang[item.text]
      local ratio = SILE.settings:get("experimental.overhang." .. spec.name)
      self:makeToken()
      self:makeOverhang(overhangWidth(item, ratio))
   else
      oldHandleWordBreak(self, item)
   end
end

--- Hook into the discretionary node to adjust the width of the prebreak.
-- @type SILE.types.node.discretionary

local orig = SILE.types.node.discretionary
local discretionary = pl.class(orig)

--- (Hard-patch) Override the discretionary constructor to adjust the width of the prebreak.
function discretionary:_init (...)
   self:super(...) -- I am told there are issues with super() but I don't see them here.
   if self.prebreak then
      -- Dig into the last item of the prebreak
      -- to see if it is a punctuation mark we want to overhang, typically the hyphen.
      local last = self.prebreak[#self.prebreak]
      local nodes = last.nodes
      local lastnode = nodes[#nodes]
      local lastitem = lastnode.value.items[#lastnode.value.items]
      if overhang[lastitem.text] and SILE.settings:get("experimental.overhang") then
         local spec = overhang[lastitem.text]
         local ratio = SILE.settings:get("experimental.overhang." .. spec.name)
         local w = overhangWidth(lastitem, ratio)
         -- Reduce the width of the last node
         last.width = last.width - w
      end
   end
end

SILE.types.node.discretionary = discretionary
