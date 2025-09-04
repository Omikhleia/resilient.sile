--- The sile·nt "new typesetter" for re·sil·ient.
--
-- Derived from SILE's base/default typesetter.
--
-- Some code in this file comes from SILE's core typesetter,
--
-- License: MIT.
-- Copyright (c) The SILE Organization / Simon Cozens et al.
--
-- This file is part of re·sil·ient, a set of extensions to SILE.
--
-- License: MIT.
-- Copyright (c) 2025 Didier Willis / Omikhkeia
--
-- @module typesetters.silent

--- Mixins support
-- @tparam p.class cls Class to extend
-- @tparam table t Mixin table
local function mixin(cls, t)
   SU.debug("resilient.typesetter", "Applying mixin", (t._name or "<unnname>"), "to",  (cls._name or "<unnamed>"))
   for k, v in pairs(t) do
     if type(v) == 'function' then
         assert(cls[k] == nil, ("Mixin conflict: %s already exists in %s"):format(k, cls._name or "<unnamed>"))
         assert(k ~= '_init',  "refuse to override constructor _init")
         cls[k] = v
      end
   end
end

--- The sile·nt typesetter class.
-- @type typesetter
local typesetter = pl.class()
typesetter.type = "typesetter"
typesetter._name = "sile·nt"

mixin(typesetter, require("typesetters.mixins.liners"))
mixin(typesetter, require("typesetters.mixins.totext"))
mixin(typesetter, require("typesetters.mixins.hbox"))
mixin(typesetter, require("typesetters.mixins.shaping"))

-- This is the default typesetter. You are, of course, welcome to create your own.
local awful_bad = 1073741823
local inf_bad = 10000
-- local eject_penalty = -inf_bad
local supereject_penalty = 2 * -inf_bad
-- local deplorable = 100000

-- Local helper class to compare pairs of margins
local _margins = pl.class({
   lskip = SILE.types.node.glue(),
   rskip = SILE.types.node.glue(),

   _init = function (self, lskip, rskip)
      self.lskip, self.rskip = lskip, rskip
   end,

   __eq = function (self, other)
      return self.lskip.width == other.lskip.width and self.rskip.width == other.rskip.width
   end,
})

--- Constructor
-- @param frame A initial frame to attach the typesetter to.
function typesetter:_init (frame)
   self:declareSettings()
   self.hooks = {}
   self.frame = nil
   self.stateQueue = {}
   self:initFrame(frame)
   self:initState()
   -- In case people use stdlib prototype syntax off of the instantiated typesetter...
   getmetatable(self).__call = self.init
   return self
end

--- Declare common settings for the typesetter.
function typesetter:declareSettings ()
   -- Settings common to any typesetter instance.
   -- These shouldn't be re-declared and overwritten/reset in the typesetter
   -- constructor (see issue https://github.com/sile-typesetter/sile/issues/1708).
   -- On the other hand, it's fairly acceptable to have them made global:
   -- Any derived typesetter, whatever its implementation, should likely provide
   -- some logic for them (= widows, orphans, spacing, etc.)

   SILE.settings:declare({
      parameter = "typesetter.widowpenalty",
      type = "integer",
      default = 3000,
      help = "Penalty to be applied to widow lines (at the start of a paragraph)",
   })

   SILE.settings:declare({
      parameter = "typesetter.parseppattern",
      type = "string or integer",
      default = "\r?\n[\r\n]+",
      help = "Lua pattern used to separate paragraphs",
   })

   SILE.settings:declare({
      parameter = "typesetter.obeyspaces",
      type = "boolean or nil",
      default = nil,
      help = "Whether to ignore paragraph initial spaces",
   })

   SILE.settings:declare({
      parameter = "typesetter.brokenpenalty",
      type = "integer",
      default = 100,
      help = "Penalty to be applied to broken (hyphenated) lines",
   })

   SILE.settings:declare({
      parameter = "typesetter.orphanpenalty",
      type = "integer",
      default = 3000,
      help = "Penalty to be applied to orphan lines (at the end of a paragraph)",
   })

   SILE.settings:declare({
      parameter = "typesetter.parfillskip",
      type = "glue",
      default = SILE.types.node.glue("0pt plus 10000pt"),
      help = "Glue added at the end of a paragraph",
   })

   SILE.settings:declare({
      parameter = "document.letterspaceglue",
      type = "glue or nil",
      default = nil,
      help = "Glue added between tokens",
   })

   SILE.settings:declare({
      parameter = "typesetter.underfulltolerance",
      type = "length or nil",
      default = SILE.types.length("1em"),
      help = "Amount a page can be underfull without warning",
   })

   SILE.settings:declare({
      parameter = "typesetter.overfulltolerance",
      type = "length or nil",
      default = SILE.types.length("5pt"),
      help = "Amount a page can be overfull without warning",
   })

   SILE.settings:declare({
      parameter = "typesetter.breakwidth",
      type = "measurement or nil",
      default = nil,
      help = "Width to break lines at",
   })

   SILE.settings:declare({
      parameter = "typesetter.italicCorrection",
      type = "boolean",
      default = false,
      help = "Whether italic correction is activated or not",
   })

   SILE.settings:declare({
      parameter = "typesetter.italicCorrection.punctuation",
      type = "boolean",
      default = true,
      help = "Whether italic correction is compensated on special punctuation spaces (e.g. in French)",
   })

   SILE.settings:declare({
      parameter = "typesetter.softHyphen",
      type = "boolean",
      default = true,
      help = "When true, soft hyphens are rendered as discretionary breaks, otherwise they are ignored",
   })

   SILE.settings:declare({
      parameter = "typesetter.softHyphenWarning",
      type = "boolean",
      default = false,
      help = "When true, a warning is issued when a soft hyphen is encountered",
   })

   SILE.settings:declare({
      parameter = "typesetter.fixedSpacingAfterInitialEmdash",
      type = "boolean",
      default = true,
      help = "When true, em-dash starting a paragraph is considered as a speaker change in a dialogue",
   })
end

function typesetter:initState ()
   self.state = {
      nodes = {},
      outputQueue = {},
      lastBadness = awful_bad,
      liners = {},
   }
end

function typesetter:initFrame (frame)
   if frame then
      self.frame = frame
      self.frame:init(self)
   end
end

function typesetter.getMargins ()
   return _margins(SILE.settings:get("document.lskip"), SILE.settings:get("document.rskip"))
end

function typesetter:setMargins (margins)
   SILE.settings:set("document.lskip", margins.lskip)
   SILE.settings:set("document.rskip", margins.rskip)
end

function typesetter:pushState ()
   self.stateQueue[#self.stateQueue + 1] = self.state
   self:initState()
end

function typesetter:popState (ncount)
   local offset = ncount and #self.stateQueue - ncount or nil
   self.state = table.remove(self.stateQueue, offset)
   if not self.state then
      SU.error("Typesetter state queue empty")
   end
end

function typesetter:isQueueEmpty ()
   if not self.state then
      return nil
   end
   return #self.state.nodes == 0 and #self.state.outputQueue == 0
end

function typesetter:vmode ()
   return #self.state.nodes == 0
end

function typesetter:debugState ()
   print("\n---\nI am in " .. (self:vmode() and "vertical" or "horizontal") .. " mode")
   print("Writing into " .. tostring(self.frame))
   print("Recent contributions: ")
   for i = 1, #self.state.nodes do
      io.stderr:write(self.state.nodes[i] .. " ")
   end
   print("\nVertical list: ")
   for i = 1, #self.state.outputQueue do
      print("  " .. self.state.outputQueue[i])
   end
end

-- Boxy stuff
function typesetter:pushHorizontal (node)
   self:initline()
   self.state.nodes[#self.state.nodes + 1] = node
   return node
end

function typesetter:pushVertical (vbox)
   self.state.outputQueue[#self.state.outputQueue + 1] = vbox
   return vbox
end

function typesetter:pushHbox (spec)
   local ntype = SU.type(spec)
   local node = (ntype == "hbox" or ntype == "zerohbox") and spec or SILE.types.node.hbox(spec)
   return self:pushHorizontal(node)
end

function typesetter:pushUnshaped (spec)
   local node = SU.type(spec) == "unshaped" and spec or SILE.types.node.unshaped(spec)
   return self:pushHorizontal(node)
end

function typesetter:pushGlue (spec)
   local node = SU.type(spec) == "glue" and spec or SILE.types.node.glue(spec)
   return self:pushHorizontal(node)
end

function typesetter:pushExplicitGlue (spec)
   local node = SU.type(spec) == "glue" and spec or SILE.types.node.glue(spec)
   node.explicit = true
   node.discardable = false
   return self:pushHorizontal(node)
end

function typesetter:pushPenalty (spec)
   local node = SU.type(spec) == "penalty" and spec or SILE.types.node.penalty(spec)
   return self:pushHorizontal(node)
end

function typesetter:pushMigratingMaterial (material)
   local node = SILE.types.node.migrating({ material = material })
   return self:pushHorizontal(node)
end

function typesetter:pushVbox (spec)
   local node = SU.type(spec) == "vbox" and spec or SILE.types.node.vbox(spec)
   return self:pushVertical(node)
end

function typesetter:pushVglue (spec)
   local node = SU.type(spec) == "vglue" and spec or SILE.types.node.vglue(spec)
   return self:pushVertical(node)
end

function typesetter:pushExplicitVglue (spec)
   local node = SU.type(spec) == "vglue" and spec or SILE.types.node.vglue(spec)
   node.explicit = true
   node.discardable = false
   return self:pushVertical(node)
end

function typesetter:pushVpenalty (spec)
   local node = SU.type(spec) == "penalty" and spec or SILE.types.node.penalty(spec)
   return self:pushVertical(node)
end

-- Actual typesetting functions
function typesetter:typeset (text)
   text = tostring(text)
   if text:match("^%\r?\n$") then
      return
   end
   local pId = SILE.traceStack:pushText(text)
   local parsepattern = SILE.settings:get("typesetter.parseppattern")
   -- NOTE: Big assumption on how to guess were are in "obeylines" mode.
   -- See https://github.com/sile-typesetter/sile/issues/2128
   local obeylines = parsepattern == "\n"

   local seenParaContent = true
   for token in SU.gtoke(text, parsepattern) do
      if token.separator then
         if obeylines and not seenParaContent then
            -- In obeylines mode, each standalone line must be kept.
            -- The zerohbox is not discardable, so it will be kept in the output,
            -- and the baseline skip will do the rest.
            self:pushHorizontal(SILE.types.node.zerohbox())
         else
            seenParaContent = false
         end
         self:endline()
      else
         seenParaContent = true
         if SILE.settings:get("typesetter.softHyphen") then
            local warnedshy = false
            for token2 in SU.gtoke(token.string, luautf8.char(0x00AD)) do
               if token2.separator then -- soft hyphen support
                  local discretionary = SILE.types.node.discretionary({})
                  local hbox = SILE.typesetter:makeHbox({ SILE.settings:get("font.hyphenchar") })
                  discretionary.prebreak = { hbox }
                  table.insert(SILE.typesetter.state.nodes, discretionary)
                  if not warnedshy and SILE.settings:get("typesetter.softHyphenWarning") then
                     SU.warn("Soft hyphen encountered and replaced with discretionary")
                  end
                  warnedshy = true
               else
                  self:setpar(token2.string)
               end
            end
         else
            if
               SILE.settings:get("typesetter.softHyphenWarning") and luautf8.match(token.string, luautf8.char(0x00AD))
            then
               SU.warn("Soft hyphen encountered and ignored")
            end
            text = luautf8.gsub(token.string, luautf8.char(0x00AD), "")
            self:setpar(text)
         end
      end
   end
   SILE.traceStack:pop(pId)
end

function typesetter:initline ()
   if self.state.hmodeOnly then
      return
   end -- https://github.com/sile-typesetter/sile/issues/1718
   if #self.state.nodes == 0 then
      table.insert(self.state.nodes, SILE.types.node.zerohbox())
      SILE.documentState.documentClass.newPar(self)
   end
end

function typesetter:endline ()
   self:leaveHmode()
   SILE.documentState.documentClass.endPar(self)
end

-- Just compute once, to avoid unicode characters in source code.
local speakerChangePattern = "^"
   .. luautf8.char(0x2014) -- emdash
   .. "[ "
   .. luautf8.char(0x00A0)
   .. luautf8.char(0x202F) -- regular space or NBSP or NNBSP
   .. "]+"
local speakerChangeReplacement = luautf8.char(0x2014) .. " "

local speaker = require("typesetters.nodes.speaker")
local speakerChangeNode = speaker.speakerChangeNode

-- Takes string, writes onto self.state.nodes
function typesetter:setpar (text)
   text = text:gsub("\r?\n", " "):gsub("\t", " ")
   if #self.state.nodes == 0 then
      if not SILE.settings:get("typesetter.obeyspaces") then
         text = text:gsub("^%s+", "")
      end
      self:initline()

      if
         SILE.settings:get("typesetter.fixedSpacingAfterInitialEmdash")
         and not SILE.settings:get("typesetter.obeyspaces")
      then
         local speakerChange = false
         local dialogue = luautf8.gsub(text, speakerChangePattern, function ()
            speakerChange = true
            return speakerChangeReplacement
         end)
         if speakerChange then
            local node = speakerChangeNode({ text = dialogue, options = SILE.font.loadDefaults({}) })
            self:pushHorizontal(node)
            return -- done here: speaker change space handling is done after nnode shaping
         end
      end
   end
   if #text > 0 then
      self:pushUnshaped({ text = text, options = SILE.font.loadDefaults({}) })
   end
end

local linebreak = require("typesetters.algorithms.knuthplass")

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

function typesetter:shapeAllNodes (nodelist, inplace)
   inplace = SU.boolean(inplace, true) -- Compatibility with earlier versions FIXME CODE SMELL
   local newNodelist = self:shapeAll(nodelist)

   if not inplace then
      return newNodelist
   end

   for i = 1, #newNodelist do
      nodelist[i] = newNodelist[i]
   end
   if #nodelist > #newNodelist then
      for i = #newNodelist + 1, #nodelist do
         nodelist[i] = nil
      end
   end
end

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

function typesetter.pageTarget (_)
   SU.deprecated("SILE.typesetter:pageTarget", "SILE.typesetter:getTargetLength", "0.13.0", "0.14.0")
end

function typesetter:getTargetLength ()
   return self.frame:getTargetLength()
end

function typesetter:registerHook (category, func)
   if not self.hooks[category] then
      self.hooks[category] = {}
   end
   table.insert(self.hooks[category], func)
end

function typesetter:runHooks (category, data)
   if not self.hooks[category] then
      return data
   end
   for _, func in ipairs(self.hooks[category]) do
      data = func(self, data)
   end
   return data
end

function typesetter:registerFrameBreakHook (func)
   self:registerHook("framebreak", func)
end

function typesetter:registerNewFrameHook (func)
   self:registerHook("newframe", func)
end

function typesetter:registerPageEndHook (func)
   self:registerHook("pageend", func)
end

function typesetter:buildPage ()
   local pageNodeList
   local res
   if self:isQueueEmpty() then
      return false
   end
   if SILE.scratch.insertions then
      SILE.scratch.insertions.thisPage = {}
   end
   pageNodeList, res = SILE.pagebuilder:findBestBreak({
      vboxlist = self.state.outputQueue,
      target = self:getTargetLength(),
   })
   if not pageNodeList then -- No break yet
      self:runHooks("noframebreak")
      return false
   end
   SU.debug("pagebuilder", "Buildding page for", self.frame.id)
   self.state.lastPenalty = res
   pageNodeList = self:runHooks("framebreak", pageNodeList)
   self:setVerticalGlue(pageNodeList, self:getTargetLength())
   self:outputLinesToPage(pageNodeList)
   return true
end

function typesetter:setVerticalGlue (pageNodeList, target)
   local glues = {}
   local gTotal = SILE.types.length()
   local totalHeight = SILE.types.length()

   local pastTop = false
   for _, node in ipairs(pageNodeList) do
      if not pastTop and not node.discardable and not node.explicit then
         -- "Ignore discardable and explicit glues at the top of a frame."
         -- See typesetter:outputLinesToPage()
         -- Note the test here doesn't check is_vglue, so will skip other
         -- discardable nodes (e.g. penalties), but it shouldn't matter
         -- for the type of computing performed here.
         pastTop = true
      end
      if pastTop then
         if not node.is_insertion then
            totalHeight:___add(node.height)
            totalHeight:___add(node.depth)
         end
         if node.is_vglue then
            table.insert(glues, node)
            gTotal:___add(node.height)
         end
      end
   end

   if totalHeight:tonumber() == 0 then
      return SU.debug("pagebuilder", "No glue adjustment needed on empty page")
   end

   local adjustment = target - totalHeight
   if adjustment:tonumber() > 0 then
      if adjustment > gTotal.stretch then
         if
            (adjustment - gTotal.stretch):tonumber() > SILE.settings:get("typesetter.underfulltolerance"):tonumber()
         then
            SU.warn(
               "Underfull frame "
                  .. self.frame.id
                  .. ": "
                  .. adjustment
                  .. " stretchiness required to fill but only "
                  .. gTotal.stretch
                  .. " available"
            )
         end
         adjustment = gTotal.stretch
      end
      if gTotal.stretch:tonumber() > 0 then
         for i = 1, #glues do
            local g = glues[i]
            g:adjustGlue(adjustment:tonumber() * g.height.stretch:absolute() / gTotal.stretch)
         end
      end
   elseif adjustment:tonumber() < 0 then
      adjustment = 0 - adjustment
      if adjustment > gTotal.shrink then
         if (adjustment - gTotal.shrink):tonumber() > SILE.settings:get("typesetter.overfulltolerance"):tonumber() then
            SU.warn(
               "Overfull frame "
                  .. self.frame.id
                  .. ": "
                  .. adjustment
                  .. " shrinkability required to fit but only "
                  .. gTotal.shrink
                  .. " available"
            )
         end
         adjustment = gTotal.shrink
      end
      if gTotal.shrink:tonumber() > 0 then
         for i = 1, #glues do
            local g = glues[i]
            g:adjustGlue(-adjustment:tonumber() * g.height.shrink:absolute() / gTotal.shrink)
         end
      end
   end
   SU.debug("pagebuilder", "Glues for this page adjusted by", adjustment, "drawn from", gTotal)
end

function typesetter:initNextFrame ()
   local oldframe = self.frame
   self.frame:leave(self)
   if #self.state.outputQueue == 0 then
      self.state.previousVbox = nil
   end
   if self.frame.next and self.state.lastPenalty > supereject_penalty then
      self:initFrame(SILE.getFrame(self.frame.next))
   elseif not self.frame:isMainContentFrame() then
      if #self.state.outputQueue > 0 then
         SU.warn("Overfull content for frame " .. self.frame.id)
         self:chuck()
      end
   else
      self:runHooks("pageend")
      SILE.documentState.documentClass:endPage()
      self:initFrame(SILE.documentState.documentClass:newPage())
   end

   if not SU.feq(oldframe:getLineWidth(), self.frame:getLineWidth()) then
      self:pushBack()
      -- Some what of a hack below.
      -- Before calling this method, we were in vertical mode...
      -- pushback occurred, and it seems it messes up a bit...
      -- Regardless what it does, at the end, we ought to be in vertical mode
      -- again:
      self:leaveHmode()
   else
      -- If I have some things on the vertical list already, they need
      -- proper top-of-frame leading applied.
      if #self.state.outputQueue > 0 then
         local lead = self:leadingFor(self.state.outputQueue[1], nil)
         if lead then
            table.insert(self.state.outputQueue, 1, lead)
         end
      end
   end
   self:runHooks("newframe")
end

function typesetter:pushBack ()
   -- FIxME DIRTY HACK
   if #self.state.outputQueue == 0 then
      -- Nothing to push back
      return
   end
   SU.error("Typesetter:pushBack not implemented in the sile·nt typesetter")
   -- The pushback mechanism in SILE core is entirely brkoken.
   -- Better to error out than to try and do something halfway.
end

function typesetter:outputLinesToPage (lines)
   SU.debug("pagebuilder", "OUTPUTTING frame", self.frame.id)
   -- It would have been nice to avoid storing this "pastTop" into a frame
   -- state, to keep things less entangled. There are situations, though,
   -- we will have left horizontal mode (triggering output), but will later
   -- call typesetter:chuck() do deal with any remaining content, and we need
   -- to know whether some content has been output already.
   local pastTop = self.frame.state.totals.pastTop
   for _, line in ipairs(lines) do
      -- Ignore discardable and explicit glues at the top of a frame:
      -- Annoyingly, explicit glue *should* disappear at the top of a page.
      -- if you don't want that, add an empty vbox or something.
      if not pastTop and not line.discardable and not line.explicit then
         -- Note the test here doesn't check is_vglue, so will skip other
         -- discardable nodes (e.g. penalties), but it shouldn't matter
         -- for outputting.
         pastTop = true
      end
      if pastTop then
         line:outputYourself(self, line)
      end
   end
   self.frame.state.totals.pastTop = pastTop
end

function typesetter:leaveHmode (independent)
   if self.state.hmodeOnly then
      SU.error("Paragraphs are forbidden in restricted horizontal mode")
   end
   SU.debug("typesetter", "Leaving hmode")
   local margins = self:getMargins()
   local vboxlist = self:boxUpNodes()
   self.state.nodes = {}
   -- Push output lines into boxes and ship them to the page builder
   for _, vbox in ipairs(vboxlist) do
      vbox.margins = margins
      self:pushVertical(vbox)
   end
   if independent then
      return
   end
   if self:buildPage() then
      self:initNextFrame()
   end
end

function typesetter:inhibitLeading ()
   self.state.previousVbox = nil
end

function typesetter.leadingFor (_, vbox, previous)
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

function typesetter:addrlskip (slice, margins, hangLeft, hangRight)
   local LTR = self.frame:writingDirection() == "LTR"
   local rskip = margins[LTR and "rskip" or "lskip"]
   if not rskip then
      rskip = SILE.types.node.glue(0)
   end
   if hangRight and hangRight > 0 then
      rskip = SILE.types.node.glue({ width = rskip.width:tonumber() + hangRight })
   end
   rskip.value = "margin"
   -- while slice[#slice].discardable do table.remove(slice, #slice) end
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
   while slice[1].discardable do
      table.remove(slice, 1)
   end
   table.insert(slice, 1, lskip)
   table.insert(slice, 1, SILE.types.node.zerohbox()) -- CODE SMELL: WHY?
end

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
               not currentNode.discardable
               and not (currentNode.is_glue and not currentNode.explicit)
               and not currentNode.is_zero
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

            -- Any unclosed liner is closed on the next line in reverse order.
            if lastContentNodeIndex then
               self:_repeatLeaveLiners(slice, lastContentNodeIndex + 1)
            end

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
            self:addrlskip(slice, mrg, point.left, point.right)

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

function typesetter.computeLineRatio (_, breakwidth, slice)
   local naturalTotals = SILE.types.length()

   -- From the line end, account for the margin but skip any trailing
   -- glues (spaces to ignore) and zero boxes until we reach actual content.
   local npos = #slice
   while npos > 1 do
      if slice[npos].is_glue or slice[npos].is_zero then
         if slice[npos].value == "margin" then
            naturalTotals:___add(slice[npos].width)
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

function typesetter:chuck () -- emergency shipout everything
   self:leaveHmode(true)
   if #self.state.outputQueue > 0 then
      SU.debug("typesetter", "Emergency shipout", #self.state.outputQueue, "lines in frame", self.frame.id)
      self:outputLinesToPage(self.state.outputQueue)
      self.state.outputQueue = {}
   end
end

return typesetter
