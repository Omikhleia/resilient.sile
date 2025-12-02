--- (Modified) Knuth-Plass line breaking algorithm.
--
-- TEX82 comments and numbers refer to <https://tug.ctan.org/info/knuth-pdf/tex/tex.pdf>
-- (At the time of writing, the linked document indicates March 12, 2025 15:39 as date of generation).
--
-- PDFTeX comments and numbers refer to <https://tug.ctan.org/info/knuth-pdf/pdftex/pdftex.pdf>
-- (At the time of writing, the linked document indicates March 12, 2025 15:39 as date of generation).
-- The latter has the "doLastLineFit" extension from ε-TeX (see comments below),
-- and several other PDFTeX-specific extensions (not implemented here).
--
-- SILE comments refer to SILE's change to the original algorithm.
--
-- Interesting other references for readers:
--
--   - <https://tug.ctan.org/macros/luatex/latex/linebreaker/linebreaker-doc.pdf>
--   - <https://www.latex-project.org/publications/2012-FMi-TUB-tb106mittelbach-e-tex-revisited.pdf>
--
-- **Original code from SILE**
--
-- License: MIT
-- Copyright (c) The SILE Organization / Simon Cozens
--
-- **Modified**
--
--  - See RESILIENT comments for adaptations to work with the sile·nt typesetter.
--  - Removed non-stantard "alternates" nodes (SILE's `gutenberg` non-working package).
--  - Removed non-standard "sideways" logic (SILE's experimental `pagebuilder-bestfit` package).
--  - Refactored based on TeX82 and PDFTeX documentation, with comments (partial pass)
--  - Notably added comments for non-implemented parts (doLastLineFit), but perhaps not all yet.
--  - Removed some dead code or hard-to-follow debug code absent from the original algorithm
--
-- License: MIT
-- Copyright (c) 2025 Omikhleia / Didier Willis
--
-- @module typesetters.algorithms.knuthplass

SILE.settings:declare({
   parameter = "linebreak.parShape",
   type = "boolean",
   default = false,
   help = "If set to true, the paragraph shaping method is activated.",
})
SILE.settings:declare({ parameter = "linebreak.tolerance", type = "integer or nil", default = 500 })
SILE.settings:declare({ parameter = "linebreak.pretolerance", type = "integer or nil", default = 100 })
SILE.settings:declare({ parameter = "linebreak.hangIndent", type = "measurement", default = 0 })
SILE.settings:declare({ parameter = "linebreak.hangAfter", type = "integer or nil", default = nil })
SILE.settings:declare({
   parameter = "linebreak.adjdemerits",
   type = "integer",
   default = 10000,
   help = "Additional demerits which are accumulated in the course of paragraph building when two consecutive lines are visually incompatible. In these cases, one line is built with much space for justification, and the other one with little space.",
})
SILE.settings:declare({ parameter = "linebreak.looseness", type = "integer", default = 0 })
SILE.settings:declare({ parameter = "linebreak.prevGraf", type = "integer", default = 0 })
SILE.settings:declare({ parameter = "linebreak.emergencyStretch", type = "measurement", default = 0 })
SILE.settings:declare({ parameter = "linebreak.linePenalty", type = "integer", default = 10 })
SILE.settings:declare({ parameter = "linebreak.hyphenPenalty", type = "integer", default = 50 })
SILE.settings:declare({ parameter = "linebreak.doubleHyphenDemerits", type = "integer", default = 10000 })
SILE.settings:declare({ parameter = "linebreak.finalHyphenDemerits", type = "integer", default = 5000 })

-- Not implemented yet,
-- But erroneous definition here, the boolean is internal, and the \lastlinefit primitive
-- from ε-TEX sets it to an integer value: For a value of 0 or less, ε-TEX behaves as TEX, values from 1
-- to 1000 indicate a glue adjustment fraction f times 1000, values above 1000 are
-- interpreted as f = 1
SILE.settings:declare({ parameter = "linebreak.doLastLineFit", type = "boolean", default = false }) -- unimplemented,

-- (TeX82 817; PDFTeX 993)
local TIGHT_FIT = 3 -- fitness classification for lines shrinking 0.5 to 1.0 of their shrinkability
local LOOSE_FIT = 1 -- fitness classification for lines stretching 0.5 to 1.0 of their stretchability
local VERY_LOOSE_FIT = 0 -- fitness classification for lines stretching more than their stretchability
local DECENT_FIT = 2 -- fitness classification for all other lines

local classes = { TIGHT_FIT, DECENT_FIT, LOOSE_FIT, VERY_LOOSE_FIT }
local passSerial = 0
local awful_bad = 1073741823
local inf_bad = 10000
local ejectPenalty = -inf_bad

--[[
  Basic control flow:
  doBreak:
    init
    for each node:
      checkForLegalBreak
        tryBreak
          createNewActiveNodes
          considerDemerits
            deactivateR (or) recordFeasible
    tryFinalBreak
    postLineBreak
]]

local param = function (key)
   local value = SILE.settings:get("linebreak." .. key)
   return type(value) == "table" and value:absolute() or value
end

-- Routines here will be called thousands of times; we micro-optimize
-- to avoid debugging and concat calls.
local debugging = false

--- Knuth-Plass line breaking algorithm.
--
-- @type lineBreak

local lineBreak = {}

--- Initialize the line breaker.
--
-- CHECK (TeX82 816; PDFTeX 992).
function lineBreak:init ()
   self:trimGlue() -- See (TeX82 816; PDFTeX 992)
   -- 849
   self.activeWidth = SILE.types.length()
   self.curActiveWidth = SILE.types.length()
   self.breakWidth = SILE.types.length()

   -- BEGIN (TeX82 827; PDFTeX 1003)
   -- NOTE: More or less... TeX uses lots of registers here, no very clear.
   local rskip = (SILE.settings:get("document.rskip") or SILE.types.node.glue()).width:absolute()
   local lskip = (SILE.settings:get("document.lskip") or SILE.types.node.glue()).width:absolute()
   self.background = rskip + lskip

   -- FIXME NOT IMPLEMENTED YET
   -- Check for special treatment of last line of paragraph.
   -- The new algorithm for the last line requires that the stretchability of par_fill_skip is infinite
   -- and the stretchability of left_skip plus right_skip is finite.
   -- do_last_line_fit ← false;
   -- active_node_size ← active_node_size_normal ; { just in case }
   -- if last_line_fit > 0 then
   --    begin q ← glue_ptr (last_line_fill);
   --    if (stretch (q) > 0) ∧ (stretch_order (q) > normal ) then
   --       if (background [3] = 0) ∧ (background [4] = 0) ∧ (background [5] = 0) then
   --          begin do last_line_fit ← true ; active_node_size ← active_node_size_extended ; fill_width [0] ← 0;
   --          fill_width [1] ← 0; fill_width [2] ← 0; fill_width [stretch_order (q) − 1] ← stretch (q);
   --          end;
   --    end
   -- END (TeX82 827; PDFTeX 1003)

   -- BEGIN (TeX82 834; PDFTeX 1010)
   self.bestInClass = {}
   for i = 1, #classes do
      self.bestInClass[classes[i]] = {
         minimalDemerits = awful_bad,
      }
   end
   self.minimumDemerits = awful_bad
   -- END (TeX82 834; PDFTeX 1010)

   -- BEGIN (TeX 848; PDFTeX 1024)
   -- (Setup line length parameters)
   self.parShaping = param("parShape") or false
   if self.parShaping then
      -- (SILE) Done differently as we use a parShape function.
      self.lastSpecialLine = nil
      self.easy_line = nil
   else
      self.hangAfter = param("hangAfter") or 0
      self.hangIndent = param("hangIndent"):tonumber()
      if self.hangIndent == 0 then
         self.lastSpecialLine = 0
         self.secondWidth = self.hsize or SU.error("No hsize")
      else
         -- BEGIN (TeX82 849; PDFTeX 1025)
         -- Set line length parameters in preparation for hanging indentation.
         self.lastSpecialLine = math.abs(self.hangAfter)
         if self.hangAfter < 0 then
            self.secondWidth = self.hsize or SU.error("No hsize")
            self.firstWidth = self.hsize - math.abs(self.hangIndent)
         else
            self.firstWidth = self.hsize or SU.error("No hsize")
            self.secondWidth = self.hsize - math.abs(self.hangIndent)
         end
         -- END (TeX82 849; PDFTeX 1025)
      end
      if param("looseness") == 0 then
         self.easy_line = self.lastSpecialLine
      else
         self.easy_line = awful_bad -- (SILE) TeX uses a different high value here
      end
   end
   -- END (TeX 848; PDFTeX 1024)
end

--- Trim_glue procedure.
--
-- Partial implementation of (TeX82 816; PDFTeX 992)
--
-- (SILE) Removes trailing glue nodes from the paragraph node list.
-- Done differently as we handle parfillskip outside.
   -- FIXME This might however have to be revisited for doLastLineFit, as there's some setup
   -- for that in PDFTeX 992 not implemented here yet.
function lineBreak:trimGlue ()
   local nodes = self.nodes
   if nodes[#nodes].is_glue then
      nodes[#nodes] = nil
   end
   nodes[#nodes + 1] = SILE.types.node.penalty(inf_bad)
end

--- Paragraph shaping method.
--
-- NOTE FOR DEVELOPERS: this method is called when the linebreak.parShape
-- setting is true. The arguments passed are self (the linebreaker instance)
-- and a counter representing the current line number.
--
-- The default implementation does nothing but waste a function call, resulting
-- in normal paragraph shapes. Extended paragraph shapes are intended to be
-- provided by overriding this method.
--
-- The expected return is three values, any of which may be nil to use default
-- values or a measurement to override the defaults. The values are considered
-- as left, width, and right respectively.
--
-- Since self.hsize holds the current line width, these three values should add
-- up to the that total. Returning values that don't add up may produce
-- unexpected results.
--
-- TeX wizards shall also note that this is slightly different from
-- Knuth's definition "nline l1 i1 l2 i2 ... lN iN".
--
-- @tparam number _ Current line number (not used here in the default implementation)
function lineBreak:parShape (_)
   return 0, self.hsize, 0
end

local parShapeCache = {}

local grantLeftoverWidth = function (hsize, l, w, r)
   local width = SILE.types.measurement(w or hsize)
   if not w and l then
      width = width - SILE.types.measurement(l)
   end
   if not w and r then
      width = width - SILE.types.measurement(r)
   end
   local remaining = hsize:tonumber() - width:tonumber()
   local left = SU.cast("number", l or (r and (remaining - SU.cast("number", r))) or 0)
   local right = SU.cast("number", r or (l and (remaining - SU.cast("number", l))) or remaining)
   return left, width, right
end

-- Wrap linebreak:parShape in a memoized table for fast access
function lineBreak:parShapeCache (n)
   local cache = parShapeCache[n]
   if not cache then
      local l, w, r = self:parShape(n)
      local left, width, right = grantLeftoverWidth(self.hsize, l, w, r)
      cache = { left, width, right }
   end
   return cache[1], cache[2], cache[3]
end

function lineBreak:parShapeCacheClear ()
   pl.tablex.clear(parShapeCache)
end

--- Try_break procedure.
--
-- Partially checked, see in-code comments.
--
function lineBreak:tryBreak ()
   local pi, breakType
   local node = self.nodes[self.place]
   if not node then
      pi = ejectPenalty
      breakType = "hyphenated"
   elseif node.is_discretionary then
      breakType = "hyphenated"
      pi = param("hyphenPenalty")
   else
      breakType = "unhyphenated"
      pi = node.penalty or 0
   end

   -- procedure try_break(pi, break_type) in PDFTeX 1005.
   -- FIXME NOT DONE HERE "Make sure that pi is in the proper range" for some reason?

   self.no_break_yet = true -- We have to store all this state crap in the object, or it's global variables all the way
   self.prev_prev_r = nil
   self.prev_r = self.activeListHead
   self.old_l = 0
   self.r = nil
   self.curActiveWidth = SILE.types.length(self.activeWidth)
   while true do
      while true do -- allows "break" to function as "continue"
         self.r = self.prev_r.next
         -- BEGIN (PDFTeX 1008)
         if self.r.type == "delta" then
            self.curActiveWidth:___add(self.r.width) -- update width
            self.prev_prev_r = self.prev_r
            self.prev_r = self.r
            break -- goto continue
            -- END (PDFTeX 1008)
         end
         -- BEGIN (PDFTeX 1011)
         -- If a line number class has ended, create new active nodes for the best feasible breaks in that class;
         -- then return if r = last_active , otherwise compute the new line width;
         if self.r.lineNumber > self.old_l then
            -- now we are no longer in the inner loop.
            if self.minimumDemerits < awful_bad and (self.old_l ~= self.easy_line or self.r == self.activeListHead) then
               self:createNewActiveNodes(breakType)
            end
            if self.r == self.activeListHead then
               return
            end
            -- BEGIN (TeX82 850; PDFTeX 1026)
            -- Compute the new line width.
            if self.easy_line and self.r.lineNumber > self.easy_line then
               self.lineWidth = self.secondWidth
               self.old_l = awful_bad - 1 -- (SILE) TeX uses a different high value here
            else
               self.old_l = self.r.lineNumber
               if self.lastSpecialLine and self.r.lineNumber > self.lastSpecialLine then
                  self.lineWidth = self.secondWidth
               elseif self.parShaping then
                  local _
                  _, self.lineWidth, _ = self:parShapeCache(self.r.lineNumber)
               else
                  self.lineWidth = self.firstWidth
               end
            end
            -- END (TeX82 850; PDFTeX 1026)
         end
         -- END (PDFTeX 1011)

         self:considerDemerits(pi, breakType) -- Calls (TeX82 851; PDFTeX 1027)
      end
   end
end

-- Note: This function gets called a lot and to optimize it we're assuming that
-- the lengths being passed are already absolutized. This is not a safe
-- assumption to make universally.
local function fitclass (self, shortfall)
   shortfall = shortfall.amount
   local badness, class
   local stretch = self.curActiveWidth.stretch.amount
   local shrink = self.curActiveWidth.shrink.amount
   if shortfall > 0 then
      if shortfall > 110 and stretch < 25 then
         badness = inf_bad
      else
         badness = SU.rateBadness(inf_bad, shortfall, stretch)
      end
      if badness > 99 then
         class = VERY_LOOSE_FIT
      elseif badness > 12 then
         class = LOOSE_FIT
      else
         class = DECENT_FIT
      end
   else
      shortfall = -shortfall
      if shortfall > shrink then
         badness = inf_bad + 1
      else
         badness = SU.rateBadness(inf_bad, shortfall, shrink)
      end
      if badness > 12 then
         class = TIGHT_FIT
      else
         class = DECENT_FIT
      end
   end
   return badness, class
end

--- Consider the demerits for a line from `r` to `cur_p`.
--
-- (TeX82 851; PDFTeX 1027).
--
-- Calculation of demerits for a break from `r` to `cur_p`.
-- The first thing to do is calculate the badness, b. This value will always be between zero and `inf_bad` + 1;
-- the latter value occurs only in the case of lines from `r` to `cur_p` that cannot shrink enough to fit the necessary
-- width. In such cases, node `r` will be deactivated. We also deactivate node `r` when a break at `cur_p` is forced,
-- since future breaks must go through a forced break
--
-- PARTIALLY CHECKED TODO FIXME
--
-- @tparam number pi Penalty
-- @tparam string breakType ("hyphenated" or "unhyphenated")
function lineBreak:considerDemerits (pi, breakType)
   self.artificialDemerits = false
   local nodeStaysActive = false
   local shortfall = self.lineWidth - self.curActiveWidth

   -- FIXME TO CHECK for fitclass, should implement:
   -- (TeX82 852; PDFTeX 1028): Set the value of b to the badness for stretching the line, and compute the corresponding fit class.
   -- (TeX82 853; PDFTeX 1029): Set the value of b to the badness for shrinking the line, and compute the corresponding fit class.
   self.badness, self.fitClass = fitclass(self, shortfall)

   -- FIXME NOT IMPLEMENTED YET
   -- if doLastLineFit then
      -- BEGIN (PDFTeX 1849)
      -- Adjust the additional data for last line.
      -- begin
      --    if cur p = null then shortfall ← 0;
      --    if shortfall > 0 then g ← cur active width [2]
      --    else if shortfall < 0 then g ← cur active width [6]
      --    else g ← 0;
      -- end

      -- END (PDFTeX 1849)
   -- end

   -- (TeX82 851; PDFTeX 1027) = from the "found" label
   if self.badness > inf_bad or pi == ejectPenalty then
      -- BEGIN (TeX82 854; PDFTeX 1030)
      -- Prepare to deactivate node `r`, and goto deactivate unless there is a reason to consider lines of text from `r` to `cur_p`.
      -- During the final pass, we dare not lose all active nodes, lest we lose touch with the line breaks already
      -- found. The code shown here makes sure that such a catastrophe does not happen, by permitting overfull
      -- boxes as a last resort. This particular part of TeX was a source of several subtle bugs before the correct
      -- program logic was finally discovered; readers who seek to “improve” TeX should therefore think thrice before
      -- daring to make any changes here.
      if
         self.finalpass
         and self.minimumDemerits == awful_bad
         and self.r.next == self.activeListHead
         and self.prev_r == self.activeListHead
      then
         self.artificialDemerits = true -- Set demerits zero, this break is forced
      else
         if self.badness > self.threshold then
            self:deactivateR() -- goto deactivate = Calls (TeX82 860; PDFTeX 1036) and returns
            return
         end
         -- TeX has nodeStaysActive = false here, but we already have it false as initialized.
      end
      -- END (TeX82 854; PDFTeX 1030)
   else
      self.prev_r = self.r
      if self.badness > self.threshold then
         return
      end
      nodeStaysActive = true
   end

   self:recordFeasible(pi, breakType) -- Calls (TeX82 855: PDFTeX 1031) Record a new feasible break.
   if nodeStaysActive then
      return -- prev_r has been set to r
   end
   self:deactivateR() -- decativate: Calls (TeX82 860; PDFTeX 1036) Deactivate node r
end

--- Deactivate node `r`.
--
-- (TeX82 860; PDFTeX 1036).
--
-- When an active node disappears, we must delete an adjacent delta node if the active node was at the
-- beginning or the end of the active list, or if it was surrounded by delta nodes.
-- We also must preserve the property that `cur_active_width` represents the length of material from
-- `link(prev_r)` to `cur_p`.
--
function lineBreak:deactivateR ()
   self.prev_r.next = self.r.next
   if self.prev_r == self.activeListHead then
      -- BEGIN (TeX82 861, PDFTeX 1037)
      -- Update the active widths, since the first active node has been deleted.
      self.r = self.activeListHead.next
      if self.r.type == "delta" then
         self.activeWidth:___add(self.r.width) -- Update active
         self.curActiveWidth = SILE.types.length(self.activeWidth) -- Copy to current active
         self.activeListHead.next = self.r.next
      end
      -- END (TeX82 861, PDFTeX 1037)
   else
      if self.prev_r.type == "delta" then
         self.r = self.prev_r.next
         if self.r == self.activeListHead then
            self.curActiveWidth:___sub(self.prev_r.width) -- Downdate width
            self.prev_prev_r.next = self.activeListHead
            self.prev_r = self.prev_prev_r
         elseif self.r.type == "delta" then
            self.curActiveWidth:___add(self.r.width) -- Update width
            self.prev_r.width:___add(self.r.width) -- Combine two deltas
            self.prev_r.next = self.r.next
         end
      end
   end
end

--- Compute the demerits, `d`, from `r` to `cur_p`.
--
-- (TeX82 859; PDFTeX 1035).
--
-- @tparam number pi Penalty
-- @tparam string breakType ("hyphenated" or "unhyphenated")
function lineBreak:computeDemerits (pi, breakType)
   local demerit = param("linePenalty") + self.badness
   if math.abs(demerit) >= 10000 then
      demerit = 100000000
   else
      demerit = demerit * demerit
   end

   -- No demerit change when pi == 0 as per (TeX82 859, PDFTeX 1035)
   if pi > 0 then
      demerit = demerit + pi * pi
   elseif pi > ejectPenalty then
      demerit = demerit - pi * pi
   end
   if breakType == "hyphenated" and self.r.type == "hyphenated" then
      if self.nodes[self.place] then
         demerit = demerit + param("doubleHyphenDemerits")
      else
         demerit = demerit + param("finalHyphenDemerits")
      end
   end

   if math.abs(self.fitClass - self.r.fitness) > 1 then
      demerit = demerit + param("adjdemerits")
   end
   return demerit
end

--- Record a new feasible break.
--
-- (Tex82 855; PDFTeX 1031).
--
-- When we get to this part of the code, the line from `r` to `cur_p` is feasible, its badness is b, and
-- its fitness classification is fit_class.
-- We don’t want to make an active node for this break yet, but we will compute the total demerits
-- and record them in the minimal demerits array, if such a break is the current champion among all
-- ways to get to `cur_p` in a given line-number class and fitness class.
--
-- @tparam number pi Penalty
-- @tparam string breakType ("hyphenated" or "unhyphenated")
function lineBreak:recordFeasible (pi, breakType)
   local demerit = self.artificialDemerits
      and 0
      or self:computeDemerits(pi, breakType) -- Calls (TeX82 859; PDFTeX 1035).
   if debugging then
      -- Print a symbolic description of this feasible break = TeX82 856
      -- FIXME Should be a separate function
      if self.nodes[self.place] then
         SU.debug(
            "break",
            "@",
            self.nodes[self.place],
            "via @@",
            (self.r.serial or "0"),
            "badness =",
            self.badness,
            "demerit =",
            demerit
         )
      else
         SU.debug("break", "@ \\par via @@")
      end
      SU.debug("break", " fit class =", self.fitClass)
   end
   demerit = demerit + self.r.totalDemerits --  This is the minimum total demerits from the beginning to `cur_p` via r
   if demerit <= self.bestInClass[self.fitClass].minimalDemerits then
      self.bestInClass[self.fitClass] = {
         minimalDemerits = demerit,
         node = self.r.serial and self.r, -- (SILE) Serial check no in TeX. We probably want to avoid the sentinel here? Dubious?
         line = self.r.lineNumber,
      }

      -- FIXME NOT IMPLEMENTED YET
      -- if doLastLineFit then
      --   -- BEGIN (PDFTeX 1850)
      --   -- Store additional data for this feasible break
      --   -- For each feasible break we record the shortfall and glue stretch or shrink (or adjustment).
      --   best_pl_short[fit_class] ← shortfall;
      --   best_pl_glue[fit_class ] ← g;
      --   -- END (PDFTeX 1850)
      -- end

      if demerit < self.minimumDemerits then
         self.minimumDemerits = demerit
      end
   end
end

--- Create new active nodes for the best feasible breaks just found.
--
-- (TeX82 836; PDFTeX 1012).
--
-- It is not necessary to create new active nodes having minimal demerits greater than
-- `minimum_demerits` + abs(`adj_demerits`), since such active nodes will never be chosen in the final
-- paragraph breaks.
-- This observation allows us to omit a substantial number of feasible breakpoints from further
-- consideration.
--
-- @tparam string breakType ("hyphenated" or "unhyphenated")
function lineBreak:createNewActiveNodes (breakType)
   if self.no_break_yet then
      -- BEGIN (TeX82 837; PDFTeX 1013)
      -- Compute the values of break width
      -- TODO FIXME CHECK THIS 837/1013 section:  (SILE) does it differently...
      self.no_break_yet = false
      self.breakWidth = SILE.types.length(self.background) -- Set break width to background
      local place = self.place
      local node = self.nodes[place]
      if node and node.is_discretionary then
         self.breakWidth:___add(node:prebreakWidth())
         self.breakWidth:___add(node:postbreakWidth())
         self.breakWidth:___sub(node:replacementWidth())
      end
      while self.nodes[place] and not self.nodes[place].is_box do
         if self.nodes[place].width then -- We use the fact that (a) nodes know if they have width and (b) width subtraction is polymorphic
            self.breakWidth:___sub(self.nodes[place]:lineContribution())
         end
         place = place + 1
      end
      -- END (TeX82 837; PDFTeX 1013)
   end
   -- BEGIN (TeX82 843; PDFTeX 1019)
   -- Insert a delta node to prepare for breaks at `cur_p`.
   if self.prev_r.type == "delta" then -- Modify an existing delta node: Convert to breakWidth
      self.prev_r.width:___sub(self.curActiveWidth)
      self.prev_r.width:___add(self.breakWidth)
   elseif self.prev_r == self.activeListHead then -- No delta node needed at the beginning
      self.activeWidth = SILE.types.length(self.breakWidth) -- Store break width
   else
      local newDelta = {
         next = self.r,
         type = "delta",
         width = self.breakWidth - self.curActiveWidth -- new delta to break width
      }
      self.prev_r.next = newDelta
      self.prev_prev_r = self.prev_r
      self.prev_r = newDelta
   end
   -- END (TeX82 843; PDFTeX 1019)

   if math.abs(self.adjdemerits) >= (awful_bad - self.minimumDemerits) then
      self.minimumDemerits = awful_bad - 1
   else
      self.minimumDemerits = self.minimumDemerits + math.abs(self.adjdemerits)
   end

   for i = 1, #classes do
      local class = classes[i]
      local best = self.bestInClass[class]
      local value = best.minimalDemerits
      if value <= self.minimumDemerits then
         -- BEGIN (TeX82 845; PDFTeX 1021)
         -- Insert a new active node from best_place[fit_class] to `cur_p`.
         -- FIXME Knuth says "When we create an active node, we also create the corresponding passive node."
         -- Are we doing exactly that? Knuth's code is hard to read here, and (SILE) is not very clear either.
         passSerial = passSerial + 1
         local newActive = {
            type = breakType,
            next = self.r,
            curBreak = self.place,
            prevBreak = best.node,
            serial = passSerial,
            lineNumber = best.line + 1,
            fitness = class,
            totalDemerits = value,
         }

         -- FIXME NOT IMPLEMENTED YET
         -- if doLastLineFit then
         --   -- BEGIN (PDFTeX 1851)
         --   -- Store additional data in the new active node 1851.
         --   -- Here we save these data in the active node representing a potential line break.
         --   --    active_short (q) ← best_pl_short[fit_class];
         --   --    active_glue (q) ← best_pl_glue [fit class ];
         --   -- END (PDFTeX 1851)
         -- end

         self.prev_r.next = newActive
         self.prev_r = newActive
         self:dumpBreakNode(newActive)
         -- END (TeX82 845; PDFTeX 1021)
      end
      self.bestInClass[class] = { minimalDemerits = awful_bad }
   end
   self.minimumDemerits = awful_bad

   -- BEGIN (TeX82 844; PDFTeX 1020)
   -- Insert a delta node to prepare for the next active node.
   -- When the following code is performed, we will have just inserted at least one active node before r,
   -- so type(prev r_) != delta_node.
   if self.r ~= self.activeListHead then
      local newDelta = {
         next = self.r,
         type = "delta",
         width = self.curActiveWidth - self.breakWidth -- New delta from break width
      }
      self.prev_r.next = newDelta
      self.prev_prev_r = self.prev_r
      self.prev_r = newDelta
   end
   -- END (TeX82 844; PDFTeX 1020)
end

-- Print a symbolic description of the new break node.
--
-- (TeX82 856; PDFTeX 1022).
--
-- (SILE) does it its own way, it's a debugging function.
--
-- @tparam table node Break node
function lineBreak:dumpBreakNode (node)
   if not SU.debugging("break") then
      return
   end
   SU.debug("break", lineBreak:describeBreakNode(node))
end

function lineBreak:describeBreakNode (node)
   if node.sentinel then
      return node.sentinel
   end
   if node.type == "delta" then
      return "delta " .. node.width .. "pt"
   end
   local before = self.nodes[node.curBreak - 1]
   local after = self.nodes[node.curBreak + 1]
   local from = node.prevBreak and node.prevBreak.curBreak or 1
   local to = node.curBreak
   return ('b %s-%s "%s | %s" [%s, %s]'):format(
      from,
      to,
      before and before:toText() or "",
      after and after:toText() or "",
      node.totalDemerits,
      node.fitness
   )
end

--- Check for legal break at the current node.
--
-- Derived from (TeX82 866; PDFTeX 1042) TO CHECK FIXME
--
-- NOTE: this function is called many thousands of times even in single
-- page documents. Speed is more important than pretty code here.
--
-- @tparam table node Current node
function lineBreak:checkForLegalBreak (node)
   if debugging then
      SU.debug("break", "considering node " .. node)
   end
   local previous = self.nodes[self.place - 1]
   if node.is_box then
      self.activeWidth:___add(node:lineContribution())
   elseif node.is_glue then
      -- auto_breaking parameter not implemented
      if previous and previous.is_box then
         self:tryBreak()
      end
      self.activeWidth:___add(node.width)
   elseif node.is_kern then
      -- BEGIN RESILIENT
      -- TeXbook (ex. 14.8) allows breaking "at a kern, provided that this kern is immediately followed by glue,
      -- and that it is not part of a math formula."
      -- For now SILE doesn't support breaking in math formulas, so we only check for the glue after the kern.
      local nnext = self.nodes[self.place + 1]
      if nnext and nnext.is_glue then
         self:tryBreak()
      end
      self.activeWidth:___add(node.width)
      -- END RESILIENT
   elseif node.is_discretionary then
      self.activeWidth:___add(node:prebreakWidth())
      self:tryBreak()
      self.activeWidth:___sub(node:prebreakWidth())
      self.activeWidth:___add(node:replacementWidth())
   elseif node.is_penalty then
      self:tryBreak()
   end
end

--- Try the final line break at the end of the paragraph.
--
-- (TeX82 873; PDFTeX 1049).
--
-- @treturn boolean true if the desired breakpoints have been found
function lineBreak:tryFinalBreak ()
   -- XXX TeX has self:tryBreak() here. But this doesn't seem to work
   -- for us. If we call tryBreak(), we end up demoting all break points
   -- to veryLoose (possibly because the active width gets reset - why?).
   -- This means we end up doing unnecessary passes.
   -- However, there doesn't seem to be any downside to not calling it
   -- (how scary is that?) so I have removed it for now. With this
   -- "fix", we only perform hyphenation and emergency passes when necessary
   -- instead of every single time. If things go strange with the break
   -- algorithm in the future, this should be the first place to look!
   -- self:tryBreak()
   -- FIXME ?
   -- TEX82 873 has indeed: try_break(ejectPenalty, "hyphenated") ;

   if self.activeListHead.next == self.activeListHead then
      return false
   end

   -- BEGIN (TeX82 874; PDFTeX 1050)
   -- Find an active node with fewest demerits.
   self.r = self.activeListHead.next
   local fewestDemerits = awful_bad
   repeat
      if self.r.type ~= "delta" and self.r.totalDemerits < fewestDemerits then
         fewestDemerits = self.r.totalDemerits
         self.bestBet = self.r
      end
      self.r = self.r.next
   until self.r == self.activeListHead
   -- END (TeX82 874; PDFTeX 1050)

   local looseness = param("looseness")
   if looseness == 0 then
      return true
   end

   -- BEGIN (TeX82 875; PDFTeX 1021)
   -- Find the best active node for the desired looseness.
   -- The adjustment for a desired looseness is a slightly more complicated version of the loop just
   -- considered. Note that if a paragraph is broken into segments by displayed equations, each segment will be
   -- subject to the looseness calculation, independently of the other segments.
   self.r = self.activeListHead.next
   local actualLooseness = 0
   repeat
      if self.r.type ~= "delta" then
         local lineDiff = self.r.lineNumber - self.bestBet.lineNumber
         if (lineDiff < actualLooseness and looseness <= lineDiff)
            or (lineDiff > actualLooseness and looseness >= lineDiff)
         then
            self.bestBet = self.r
            actualLooseness = lineDiff
            fewestDemerits = self.r.totalDemerits
         elseif lineDiff == actualLooseness and self.r.totalDemerits < fewestDemerits then
            self.bestBet = self.r
            fewestDemerits = self.r.totalDemerits
         end
      end
      self.r = self.r.next
   until self.r == self.activeListHead
   -- END (TeX82 875; PDFTeX 1021)

   if actualLooseness == looseness or self.finalpass then
      return true
   end
end

--- Main line breaking procedure.
--
-- Derived from (TeX82 863; PDFTeX 1039) PARTIALLY CHECKED FIX%E
--
-- @tparam table nodes List of nodes representing the paragraph
-- @tparam SILE.length hsize Line width
-- @treturn table List of breakpoints
-- @treturn table Possibly modified list of nodes
function lineBreak:doBreak (nodes, hsize)
   passSerial = 1
   debugging = SU.debugging("break")
   self.nodes = nodes
   self.hsize = hsize
   self:init()
   self.adjdemerits = param("adjdemerits")

   -- BEGIN (TeX82 863; PDFTeX 1039) --- FIXME PARTIALLY CHECKED
   -- Find optimal breakpoints
   self.threshold = param("pretolerance")
   if self.threshold >= 0 then
      self.pass = "first"
      self.finalpass = false
   else
      self.threshold = param("tolerance")
      self.pass = "second"
      self.finalpass = param("emergencyStretch") <= 0
   end
   -- The ‘loop’ in the following code is performed at most thrice per call of line break, since it is actually
   -- a pass over the entire paragraph.
   while 1 do
      if self.threshold > inf_bad then
         self.threshold = inf_bad
      end
      if self.pass == "second" then
         -- BEGIN (PDFTeX 1068)
         -- Initialize for hyphenating a paragraph
         -- (SILE) Done differently than TeX
         self.nodes = SILE.hyphenate(self.nodes)
         -- BEGIN RESILIENT (remove side effect on SILE.typesetter.state.nodes)
         -- SILE.typesetter.state.nodes = self.nodes -- Horrible breaking of separation of concerns here. :-(
         -- END RESILIENT
      end

      -- Create an active breakpoint representing the beginning of the paragraph
      -- (SILE) does it differently than TeX here, with two sentinels
      self.activeListHead = {
         -- Maybe from (TeX82 820; PDFTeX 996)?
         sentinel = "START",
         type = "hyphenated",
         lineNumber = awful_bad, -- (SILE) TeX uses a different high value here?
         fitness = DECENT_FIT, -- Not needed if from (TeX82 820; PDFTeX 996)?
      }
      self.activeListHead.next = {
         sentinel = "END",
         type = "unhyphenated",
         fitness = DECENT_FIT,
         next = self.activeListHead,
         lineNumber = param("prevGraf") + 1,
         totalDemerits = 0,
      }

      -- FIXME NOT IMPLEMENTED YET
      -- if doLastLineFit then
      --    -- BEGIN (PDFTeX 1845)
      --    -- Initialize additional fields of the first active node
      --    active_short(q) ← 0;
      --    active_glue(q) ← 0;
      --    -- END (PDFTeX 1845)
      -- end

      self.activeWidth = SILE.types.length(self.background) -- store background
      -- END (TeX82 864; PDFTeX 1040)

      self.place = 1
      while self.nodes[self.place] and self.activeListHead.next ~= self.activeListHead do
         -- BEGIN PDFTeX 1042
         self:checkForLegalBreak(self.nodes[self.place])
         self.place = self.place + 1
      end
      if self.place > #self.nodes then
         -- Try the final line break at the end of the paragraph = Calls (TeX82 873; PDFTeX 1049).
         -- We are done if the desired breakpoints have been found.
         if self:tryFinalBreak() then
            break
         end
      end

      -- Not doing "Clean up the memory by removing the break nodes" (TeX82 865; PDFTeX 1041)

      if self.pass ~= "second" then
         self.pass = "second"
         self.threshold = param("tolerance")
      else
         self.pass = "emergency"
         self.background.stretch:___add(param("emergencyStretch"))
         self.finalpass = true
      end
   end

   -- if doLastLineFit then
   --    -- BEGIN (PDFTeX 1853)
   --    -- FIXME NOT IMPLEMENTED YET
   --    -- Adjust the final line of the paragraph
   --    -- Here we either reset do_last_line_fit or adjust the par_fill_skip glue.
   --    if active_short(best_bet) = 0 then do last_line_fit ← false
   --    else begin q ← new_spec (glue_ptr (last_line_fill)); delete glue_ref (glue_ptr (last_line_fill ));
   --       width (q) ← width (q) + active_short(best_bet) − active_glue(best_bet); stretch (q) ← 0;
   --       glue_ptr (last_line_fill) ← q;
   --    end
   --    -- END (PDFTeX 1853)
   -- end

   -- END (TeX82 863; PDFTeX 1039)

   -- RESILIENT (return breaks and also nodes, these may have been hyphenated)
   return self:postLineBreak(), self.nodes
end

--- Generate the list of line breaks after the best breakpoints have been found.
--
-- FIXME TODO CHECK in (TeX82; PDFTeX)
--
function lineBreak:postLineBreak ()
   local p = self.bestBet
   local breaks = {}
   local line = 1

   local nbLines = 0
   local p2 = p
   repeat
      nbLines = nbLines + 1
      p2 = p2.prevBreak
   until not p2

   repeat
      local left, _, right
      -- SILE handles the actual line width differently than TeX,
      -- so below always return a width of self.hsize. Would they
      -- be needed at some point, the exact width are commented out
      -- below.
      if self.parShaping then
         left, _, right = self:parShapeCache(nbLines + 1 - line)
      else
         if self.hangAfter == 0 then
            -- width = self.hsize
            left = 0
            right = 0
         else
            local indent
            if self.hangAfter > 0 then
               -- width = line > nbLines - self.hangAfter and self.firstWidth or self.secondWidth
               indent = line > nbLines - self.hangAfter and 0 or self.hangIndent
            else
               -- width = line > nbLines + self.hangAfter and self.firstWidth or self.secondWidth
               indent = line > nbLines + self.hangAfter and self.hangIndent or 0
            end
            if indent > 0 then
               left = indent
               right = 0
            else
               left = 0
               right = -indent
            end
         end
      end

      table.insert(breaks, 1, {
         position = p.curBreak,
         width = self.hsize,
         left = left,
         right = right,
      })

      p = p.prevBreak
      line = line + 1
   until not p
   self:parShapeCacheClear()
   return breaks
end

return lineBreak
