--- The sile·nt "new typesetter" for re·sil·ient.
--
-- Derived from SILE's base/default typesetter.
--
-- Some code in this file comes from SILE's core typesetter.
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

--- Naive mixins support (merging mixin tables into a class).
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
--
-- The typesetter does a lot of different things.
--
--  - Managing the typesetter state (horizontal/vertical mode, node node queues etc.)
--  - Shaping text into glyphs,
--  - Breaking paragraphs into lines,
--  - And many other things...
--
-- It's a huge beast, with many interdependent parts and several roles.
--
-- SILE's typesetter, in this author's viewpoint, has become somewhat intricate over time,
-- with lots of obscure decisions all over the place, and loosely organized parts and
-- undocumented behaviors. all in a big monolithic file.
--
-- The sile·nt typesetter is a rewrite of SILE's base/default typesetter, where some parts
-- of the logic have been split into "mixin" modules, each implementing a specific feature:
--
--  - @{typesetters.mixins.hbox}
--  - @{typesetters.mixins.liners}
--  - @{typesetters.mixins.paragraphing}
--  - @{typesetters.mixins.shaping}
--  - @{typesetters.mixins.totext}
--  - And possibly more in the future.
--
-- There are also other deviations in the way it handles some algorithms, e.g., regarding
-- in which order some operations are performed, in a attempt to make things more logical
-- and easier to follow; and in some cases more efficient.
-- The are also some API changes, as some methods have are considered internal and not part
-- of the public-facing API.
-- These methods are all documented, but their name starts with an underscore.
-- Finaally, some weird code paths and non-functional features have been removed.
--
-- @type typesetters.silent

local typesetter = pl.class()
typesetter.type = "typesetter"
typesetter._name = "sile·nt"

mixin(typesetter, require("typesetters.mixins.hbox"))
mixin(typesetter, require("typesetters.mixins.liners"))
mixin(typesetter, require("typesetters.mixins.paragraphing"))
mixin(typesetter, require("typesetters.mixins.shaping"))
mixin(typesetter, require("typesetters.mixins.totext"))

-- This is the default typesetter. You are, of course, welcome to create your own.
local inf_bad = 10000 -- CODE SMELL: VALUES REPEATED / USED AT SEVERAL PLACES
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
   self:_initState()
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

--- Initialize the typesetter state.
function typesetter:_initState ()
   self.state = {
      nodes = {},
      outputQueue = {},
      liners = {},
   }
end

--- Initialize the typesetter with a frame.
function typesetter:initFrame (frame)
   if frame then
      self.frame = frame
      self.frame:init(self)
   end
end

--- Get the current left and right margins.
function typesetter:getMargins ()
   return _margins(SILE.settings:get("document.lskip"), SILE.settings:get("document.rskip"))
end

--- Set the current left and right margins.
function typesetter:setMargins (margins)
   SILE.settings:set("document.lskip", margins.lskip)
   SILE.settings:set("document.rskip", margins.rskip)
end

--- Push the current typesetter state onto the state queue,
function typesetter:pushState ()
   self.stateQueue[#self.stateQueue + 1] = self.state
   self:_initState()
end

--- Pop the last typesetter state from the state queue,
function typesetter:popState ()
   self.state = table.remove(self.stateQueue)
   if not self.state then
      SU.error("Typesetter state queue empty")
   end
end

--- Check if the typesetter queue is empty (no pending nodes, no output).
function typesetter:isQueueEmpty ()
   if not self.state then
      return nil
   end
   return #self.state.nodes == 0 and #self.state.outputQueue == 0
end

--- Check if the typesetter is in vertical mode (no pending nodes).
function typesetter:vmode ()
   return #self.state.nodes == 0
end

--- Debug print of the current typesetter state.
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

--- Push a horizontal node into the current horizontal list.
function typesetter:pushHorizontal (node)
   self:initline()
   self.state.nodes[#self.state.nodes + 1] = node
   return node
end

--- Push a vertical node into the current vertical list.
function typesetter:pushVertical (vbox)
   self.state.outputQueue[#self.state.outputQueue + 1] = vbox
   return vbox
end

--- Push an hbox into the current horizontal list.
function typesetter:pushHbox (spec)
   local ntype = SU.type(spec)
   local node = (ntype == "hbox" or ntype == "zerohbox") and spec or SILE.types.node.hbox(spec)
   return self:pushHorizontal(node)
end

--- Push an unshaped node into the current horizontal list.
function typesetter:pushUnshaped (spec)
   local node = SU.type(spec) == "unshaped" and spec or SILE.types.node.unshaped(spec)
   return self:pushHorizontal(node)
end

--- Push a glue node into the current horizontal list.
function typesetter:pushGlue (spec)
   local node = SU.type(spec) == "glue" and spec or SILE.types.node.glue(spec)
   return self:pushHorizontal(node)
end

--- Push an explicit glue node into the current horizontal list.
function typesetter:pushExplicitGlue (spec)
   local node = SU.type(spec) == "glue" and spec or SILE.types.node.glue(spec)
   node.explicit = true
   node.discardable = false
   return self:pushHorizontal(node)
end

--- Push a penalty node into the current horizontal list.
function typesetter:pushPenalty (spec)
   local node = SU.type(spec) == "penalty" and spec or SILE.types.node.penalty(spec)
   return self:pushHorizontal(node)
end

--- Push a migrating node into the current horizontal list.
function typesetter:pushMigratingMaterial (material)
   local node = SILE.types.node.migrating({ material = material })
   return self:pushHorizontal(node)
end

--- Push a vbox node into the current vertical list.
function typesetter:pushVbox (spec)
   local node = SU.type(spec) == "vbox" and spec or SILE.types.node.vbox(spec)
   return self:pushVertical(node)
end

--- Push a vglue node into the current vertical list.
function typesetter:pushVglue (spec)
   local node = SU.type(spec) == "vglue" and spec or SILE.types.node.vglue(spec)
   return self:pushVertical(node)
end

--- Push an explicit vglue node into the current vertical list.
function typesetter:pushExplicitVglue (spec)
   local node = SU.type(spec) == "vglue" and spec or SILE.types.node.vglue(spec)
   node.explicit = true
   node.discardable = false
   return self:pushVertical(node)
end

--- Push a penalty node into the current vertical list.
function typesetter:pushVpenalty (spec)
   local node = SU.type(spec) == "penalty" and spec or SILE.types.node.penalty(spec)
   return self:pushVertical(node)
end

--- Split the input text into paragraphs, and push them to the current horizontal list.
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

--- Initialize a new line if needed, entering horizontal mode and starting a new paragraph.
function typesetter:initline ()
   if self.state.hmodeOnly then
      return
   end -- https://github.com/sile-typesetter/sile/issues/1718
   if #self.state.nodes == 0 then
      table.insert(self.state.nodes, SILE.types.node.zerohbox())
      SILE.documentState.documentClass.newPar(self)
   end
end

--- Leave horizontal mode and end the current paragraph.
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

--- Takes an input paragraph string, and pushes it to the current horizontal list,
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

--- Shape all unshaped nodes in a list (legacy compatibility function).
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

--- Get the target length for the current frame.
function typesetter:getTargetLength ()
   return self.frame:getTargetLength()
end

--- Register a hook function to be called at a certain event.
function typesetter:registerHook (category, func)
   if not self.hooks[category] then
      self.hooks[category] = {}
   end
   table.insert(self.hooks[category], func)
end

--- Run all hooks registered for a certain event.
function typesetter:runHooks (category, data)
   if not self.hooks[category] then
      return data
   end
   for _, func in ipairs(self.hooks[category]) do
      data = func(self, data)
   end
   return data
end

--- Register a hook function to be called at each frame break.
--
-- Convenience helper.
function typesetter:registerFrameBreakHook (func)
   self:registerHook("framebreak", func)
end

--- Register a hook function to be called at each new frame initialization.
--
-- Convenience helper.
function typesetter:registerNewFrameHook (func)
   self:registerHook("newframe", func)
end

--- Register a hook function to be called at page end.
--
-- Convenience helper.
function typesetter:registerPageEndHook (func)
   self:registerHook("pageend", func)
end

--- Attempt to build a page from the current vertical list.
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

--- Adjust vertical glues on a page to fit the target length.
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

--- Initialize the next frame for typesetting.
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

function typesetter:pushBack () -- Not documented, since not implemented
   if #self.state.outputQueue == 0 then
      -- Nothing to push back (safe guard).
      -- Within re·sil·ient, this notably happens after switching from cover pages
      -- to book content, or between layout changes.
      -- But normally, there is nothing to push back at these points.
      return
   end
   SU.error("Typesetter:pushBack not implemented in the sile·nt typesetter")
   -- The "pushback" mechanism in SILE core is entirely brkoken.
   -- Better to error out than to try and do something halfway.
   -- Comment kept for reference:
   -- Before calling this method, we were in vertical mode.
   -- So whatever we may eventually do here, at the end we must be
   -- back in vertical mode.
end

--- Output a list of lines to the current page.
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

--- Leave horizontal mode, ending the current paragraph.
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

--- Emergency shipout everything
function typesetter:chuck () -- emergency shipout everything
   self:leaveHmode(true)
   if #self.state.outputQueue > 0 then
      SU.debug("typesetter", "Emergency shipout", #self.state.outputQueue, "lines in frame", self.frame.id)
      self:outputLinesToPage(self.state.outputQueue)
      self.state.outputQueue = {}
   end
end

return typesetter
