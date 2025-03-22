--
-- TEI bible format with critical apparatus as used for the Gothic Bible
-- from wulfila.be (TEI Gothica).
-- Following the resilient styling paradigm.
--
-- 2022, 2023, Didier Willis
-- License: MIT
--
-- HIGHLY EXPERIMENTAL
--
local luautf8 = require("lua-utf8")
local ast = require("silex.ast")
local createCommand,
      processAsStructure, trimSubContent,
      findInTree
        = ast.createCommand,
          ast.processAsStructure, ast.trimSubContent,
          ast.findInTree
local loadkit = require("loadkit")
local loader = loadkit.make_loader("png")

local base = require("packages.resilient.base")

local package = pl.class(base)
package._name = "resilient.bible.tei"

function package:_init (_)
  base._init(self)
  self:loadPackage("dropcaps")
  self:loadPackage("inputfilter")
  self:loadPackage("font-fallback")
  self.class:registerHook("endpage", function ()
    self:outputCollatedNotes()
  end)
end

function package.outputCollatedNotes (_)
  SILE.typesetNaturally(SILE.getFrame("margins"), function ()
    local refs = SILE.scratch.info.thispage.witnesses
    if not refs then return end

    SILE.settings:pushState()
    SILE.settings:toplevelState()
    SILE.settings:set("current.parindent", SILE.types.node.glue())
    SILE.settings:set("document.parindent", SILE.types.node.glue())
    SILE.settings:set("document.lskip", SILE.types.node.glue())
    SILE.settings:set("document.rskip", SILE.types.node.hfillglue())
    for _, v in ipairs({
      "current.hangAfter",
      "current.hangIndent",
      "linebreak.hangAfter",
      "linebreak.hangIndent" }) do
      SILE.settings:set(v, SILE.settings.defaults[v])
    end

    local resource
    local mainbook = refs[1].book and string.lower(refs[1].book)
    if mainbook == "mt" or mainbook == "jn" or mainbook == "lk" or mainbook == "mk" then
      resource = "packages.resilient.bible.tei.monograms."..mainbook
    else
      resource = "packages.resilient.bible.tei.monograms.default"
    end
    local imgsrc = loader(resource)
    if not imgsrc then
      SU.warning("Could not load monogram "..resource)
    else
      SILE.call("img", { width = "100%fw", src = imgsrc })
    end
    SILE.call("hbox")

    SILE.call("vfill")
    SILE.call("font", { size = "9pt" }, function ()
      SILE.call("color", { color = "black" }, function ()
        -- Color hack: When the content frame splits a color item, it propagates
        -- to other frames.
        -- We enforce black, but it is fragile (introducing hboxes for color switching)
        -- so output-collated-sources must be called last here and not leave horizontal
        -- mode...
        SILE.call("output-collated-variants")
        SILE.call("output-collated-notes")
        SILE.call("output-collated-sources")
      end)
      SILE.typesetter:leaveHmode() -- leave inside the font size change.
    end)
   -- SILE.call("skip", { height = "0.05bs"}) -- EMPIRICAL: around the descenders of main content...
    SILE.call("framebreak")
    SILE.settings:popState()
  end)
end

--
-- CONTEXT VARIABLES
--

-- Capitalization tracking:
-- In this "modern" rendering, we'll want to capitalize words after certain usual punctuations.
-- 3-state flags (nil, false, true)
-- When nil, we don't know and have to guess from context.
local caseNeeded = nil

-- In opener/closed blocks, we'll center the text and break it at periods.
-- Use a tracking variable for that... (There would be other ways, but this should be
-- sufficient for this simple case.)
local breakAtPeriod = false

-- Last (i.e. eventually current) reference tracking:
-- Eventually filled as { book=..., chapter=..., verse=... }
local lastRef = {}

local insideLinkingNote = false

-- Extracted book details from the front matter
local books = {}

-- Alternate book names in Gothic.
--
-- The XML source uses the head title from Streitberg's book (sometimes in German, etc.)
-- Let's have cool "reconstructed" forms instead.
local ALTBOOKNAMES = {
  Mt = "Matþaius",
  Jn = "Ïohannes",
  Lk = "Lukas",
  Mk = "Markus",
  Rom = "Rumoneis",
  ["1Cor"] = "Kaurinþaium ·a·",
  ["2Cor"] = "Kaurinþaium ·b·",
  Eph = "Aifaisius",
  Gal = "Galateis",
  Php = "Filippaium",
  Col = "Kaulaussaium",
  ["1Thess"] = "Þaissalauneikaium ·a·",
  ["2Thess"] = "Þaissalauneikaium ·b·",
  ["1Tim"] = "Teimauþaius ·a·",
  ["2Tim"] = "Teimauþaius ·b·",
  Tit = "Teitus",
  Phm = "Fileimaun",
  Neh = "Nehaimia",
  Sk = "Skeireins",
}

-- The XML source defines manuscript names in its front matter, but we want
-- simpler names sometimes, or French, etc.
local MSSNAMES = {
  CA = "Codex Argenteus",
  A = "Ambrosianus A",
  B = "Ambrosianus B",
  C = "Ambrosianus C",
  D = "Ambrosianus D",
  E = "Ambrosianus E",
  Car = "Carolinus",
  Taur = "Taurinensis",
  Lat5750 = "Vat. Lat. 5750",
  Speyer = "Frag. de Spire",
}

-- String trimming
local trimLeft = function (str)
  return str:gsub("^%s*", "")
end
local trimRight = function (str)
  return str:gsub("%s*$", "")
end
local trim = function (str)
  return trimRight(trimLeft(str))
end

-- The XML sources uses "_" for incomplete words, and "~"" for assimilation,
-- rather than some structured markup:
-- Replace them with ellipsis and regular dash for output.
-- Finally there's also a greek sampi encoded as "{90}", to replace too.
local function replaceSpecialChars (input, _)
  return input:gsub("_", "…"):gsub("~", "-"):gsub("{90}", "ϡ")
end

-- Check if a content tree contains commands, in which case it is
-- assumed to be a "structure"
-- FIXME LIKELY BROKEN BY DESIGN, CHECK WHERE USED FOR REFACTORING OR CLARIFYING
local function isStructure(content)
  for i = 1, #content do
    if type(content[i]) == "table" then
      if content[i].command then
        return true
      end
    end
  end
  return false
end

local function filterDifferences (rdg)
  return rdg.command == "seg"
    and rdg.options.subtype ~= "5"
    and rdg.options.subtype ~= "6"
    and rdg.options.subtype ~= "7"
end

local function postprocessReadings(content)
  local rdg1 = pl.tablex.filter(content[1], filterDifferences)
  local rdg2 = pl.tablex.filter(content[2], filterDifferences)

  local j = 1
  for _, v in ipairs(rdg1) do
    if j > #rdg2 then break end
    if not v.options.subtype and rdg2[j].options.subtype then
      j = j + 1
    elseif v.options.subtype ~= rdg2[j].options.subtype then
      j = j + 1
    end
    if j > #rdg2 then break end
    if v.options.subtype == rdg2[j].options.subtype then
      v.options._link_ = rdg2[j]
      j = j + 1
    end
  end
  processAsStructure(content)
end

-- Recursively walks through a content tree to find the first non-empty string
-- and capitalize it.
-- NOTE: Processes all the content.
local function processCapitalize(content)
  local mustcase = true
  for i = 1, #content do
    if mustcase then
      if type(content[i]) == "table" then
        processCapitalize(content[i])
        mustcase = false
      elseif content[i] ~= "" then
        local f = luautf8.sub(content[i], 1, 1)
        local r = luautf8.sub(content[i], 2)
        SILE.call("uppercase", {}, { f })
        SILE.typesetter:typeset(r)
        mustcase = false
      end
    else
      SILE.process({ content[i] })
    end
  end
end

-- Check if a content tree (assumed already trimmed) starts with
-- a punctuation element <c>.
-- (TEI Gotica-specific)
local function startsWithPunct(content)
  for i = 1, #content do
    if type(content[i]) == "table" then
      if content[i].command == "c" then
        return true
      end
      -- Non punctuation command
      return false
    elseif content[i] ~= "" then
      -- Nonempty text
      return false
    end
    -- So empty text is ignored and we loop.
  end
  return false
end

-- The lowest-level <seg> element can contain <unclear>, <add> and <del>
-- elements.s
-- The assuption is that these only contain a word parts (i.e. strings).
-- We extract the target word (incl. additions), the source word (incl.
-- deletions).
-- (TEI Gotica-specific)
local function trimAllSubContents(content)
  local subc = {}
  for _, n in ipairs(content) do
    subc[#subc+1] = trim(n)
  end
  return subc
end
local function parseEmendations(content)
  local targetText = {}
  local sourceText = {}
  local emended = false
  for _, node in ipairs (content) do
    if type(node) == "table" then
      if node.command == "add" then
        targetText[#targetText+1] = trimAllSubContents(node)
        emended = true
      elseif node.command == "del" then
        sourceText[#sourceText+1] = trimAllSubContents(node)
        emended = true
      else
        if node.command ~= "unclear" then
          -- Should not occur, but warn if it occurs...
          -- (In case we missed something here)
          SU.warn("Unexpected structure in emendation parsing "..node.command)
        end
        targetText[#targetText+1] = node
        sourceText[#sourceText+1] = node
      end
    else
      targetText[#targetText+1] = trim(node)
      sourceText[#sourceText+1] = trim(node)
    end
  end
  return emended, targetText, sourceText
end

-- Called for "measuring" a weight of a reading (<rdg>) so as to try picking
-- the best variant.
-- (TEI Gotica-specific)

-- Word weighting = nr of unclear parts, nr of emended word parts.
local function weightSeg(content)
  local unclear, emended = 0, 0
  for i = 1, #content do
    if type(content[i]) == "table" then
      if content[i].command == "unclear" then
        unclear = unclear + 1
      elseif content[i].command == "add" or content[i].command == "del" then
        emended = emended + 1
      else
        SU.warn("weightSeg unexpected "..content[i].command) -- What we may have forgotten?
      end
    end
  end
  return unclear, emended
end
local function weightDiff(content)
  -- Quite lame: just number of (<seg>) descendant
  -- FIXME Are there cases where we lose a lacunaEnd vs. a lacunaStart
  --   Yes, see Mark 16:12 for instance
  --         or Romans chapter 11:33
  -- But still it seems we are not doing too bad there.
  local unclear, emended, segs = 0, 0, 0
  for i = 1, #content do
    if type(content[i]) == "table" then
      if content[i].command == "seg" then
        local u, e = weightSeg(content[i])
        unclear = unclear + u
        emended = emended + e
        segs = segs + 1
      elseif content[i].command == "c" or content[i].command == "del"
        or content[i].command == "add" then -- luacheck: ignore 542
          -- Do not count punctuation for weighting.
          -- Do not count global emendations (additions or deletions) either.
      else
        SU.warn("weightDiff unexpected "..content[i].command) -- What we may have forgotten?
      end
    end
  end
  return unclear, emended, segs
end

local function weightReading(content)
  -- Quite lame: just number of (<seg>) descendant
  local unclear, segs = 0, 0
  for i = 1, #content do
    if type(content[i]) == "table" then
      if content[i].options.type == "diff" then
        if content[i].options.subtype == "5" or content[i].options.subtype == "6" then
          -- Diff subtype 5 is words present in mss. but not in another. FIXME EXPLAIN
          -- 6 lacuna complement
          local u, _, s = weightDiff(content[i])
          unclear = unclear + u
          segs = segs + s
        elseif content[i].options.subtype == "7" then -- luacheck: ignore 542
          -- ignore punctuation difference for weighting
        else
          -- Whatever the number of words, count as 1 for weighting other
          -- diffs, unless they have no word inside (e.g. deletions.)
          -- segs = segs + 1
          local u, _, s = weightDiff(content[i])
          segs = segs + ((s > 0) and 1 or 0)
          unclear = unclear + u
        end
      elseif content[i].command == "seg" then
        local u, _ = weightSeg(content[i])
        unclear = unclear + u
        segs = segs + 1
      elseif content[i].command == "c" or content[i].command == "del" or content[i].command == "gap"
        or content[i].command == "add" or content[i].command == "lacunaStart"  then -- luacheck: ignore 542
        -- ignore explain
      else
        SU.warn("weightReading unexpected "..content[i].command) -- What we may have forgotten?
      end
    end
    -- All text nodes in ignored in structure tags.
  end
  return unclear, segs
end

-- PICK MAIN READING

local function preprocessReading(content)
  local rdg = {}
  for key, value in pairs(content) do
    -- copy all key-value pairs
    if type(key)=="string" then
      rdg[key] = value
     end
  end
  for i = 1, #content do
    -- Ignore text nodes in in ignored in structure tags
    -- and record the presence of (seg) diff markup.
    if type(content[i]) == "table" then
      rdg[#rdg+1] = content[i]
      if (content[i].options.type == "diff") then
        content.options._diff_ = true
      end
    end
  end
  return rdg
end

-- <seg type="diff" subtype="6"> is used in the source document to mark
-- difference in one variant where the other has a lacuna.
-- (TEI Gotica-specific)

-- Handle the case where the first reading starts with a lacuna
local function handleStartsWithLacuna (rdgA, rdgB)
  if rdgA[1].command == "lacunaEnd" and rdgB[1].options.subtype == "6" then
    -- A starts with a lacuna and B complements it:
    --    "(...) xxx"  vs. "6a xxx" = we pick "6a xxx"
    -- Pick at least B
    rdgB.options._selected_primary_ = true
    if rdgA[#rdgA].options.subtype == "6" and rdgB[#rdgB].command == "lacunaStart" then
      -- If B end with a lacuna
      --    "(...) xxx 6b"  vs. "6a xxx (...)"
      -- Then we alos pick A
      -- Actually it could be
      --   "(...) xxx 6b"  vs. "6a xxx (...)" = we want "6a xxx 6b"
      --   "(...) 6b" vs. 6a (...) = we want "6a (...) 6b"
      rdgA.options._selected_secondary_ = true
      rdgA[1] = rdgA[#rdgA] -- pick the final part from reading A
      for k = #rdgA, 2, -1 do -- remove all the rest.
        rdgA[k] = nil
      end
      -- So now "6b" vs. "6a xxx (...)"
      if #rdgB > 2 then
        -- "6b" vs. "6a xxx
        rdgB[#rdgB] = nil
      end
      -- Inversion is important here
      postprocessReadings({ rdgB, rdgA })
    else
      -- B doesn't end with a lacuna
      postprocessReadings({ rdgB, rdgA })
    end
    return true
  end
  return false
end

-- Handle the case where the first reading ends with a lacuna
local function handleEndsWithLacuna(rdgA, rdgB)
  if rdgA[#rdgA].command == "lacunaStart" and rdgB[#rdgB].options.subtype == "6" then
    -- "xxx (...)" vs "xxx 6"
    -- We pick B.
    -- ASSUMPTION: Called after handleStartsWithLacuna so the case were both have
    -- a lacuna is already handled.
    rdgB.options._selected_primary_ = true
    postprocessReadings({ rdgB, rdgA })
    return true
  end
  return false
end

-- Handle best readings (recursing into them to compute a weight):
-- Pick the reading that has more words (longer), or less unclear forms.
local function handleByWeight(rdgA, rdgB)
  local unclearA, segsA = weightReading(rdgA)
  local unclearB, segsB = weightReading(rdgB)
  if segsA > segsB then
    rdgA.options._selected_primary_ = true
  elseif segsB > segsA then
    rdgB.options._selected_primary_ = true
  else
    if unclearA <= unclearB then
      rdgA.options._selected_primary_ = true
    else
      rdgB.options._selected_primary_ = true
    end
  end
  if rdgA.options._selected_primary_ then
    postprocessReadings({ rdgA, rdgB })
  else
    postprocessReadings({ rdgB, rdgA })
  end
end

-- Walk an apparatus (<app>) content tree to weight and select readings (<rdg>)
-- (TEI Gotica-specific)
local function weightStructure(content)
  -- Collect readings
  local readings = {}
  for i = 1, #content do
    if type(content[i]) == "table" then
      readings[#readings+1] = content[i]
    end
  end
  -- Pick readings
  if #readings == 1 then
    -- Only one choice, easy.
    local picked = readings[1]
    picked.options._selected_primary_ = true
    processAsStructure({ picked })
  elseif #readings == 2 then
    -- Two choices:
    -- Walk through the readings and annotate them
    local a = preprocessReading(readings[1])
    local b = preprocessReading(readings[2])
    -- Delegate choice to a cascade of dedicated handlers
    -- Pretty lame, sot the order is quite important.
    if not handleStartsWithLacuna(a, b) then
      if not handleStartsWithLacuna(b, a) then
        if not handleEndsWithLacuna(a, b) then
          if not handleEndsWithLacuna(b, a) then
            handleByWeight(a, b)
          end
        end
      end
    end
  else
    -- Hopefully, we do not have more than two readings in the
    -- Gotica sources, so let's not bother how to do it.
    SU.error("Unimplemented: " ..#readings.. " readings to pick from")
  end
end

--
-- PACKAGE COMMANDS
--
function package:registerCommands ()

  self:registerCommand("running-headers", function (_, content)
    SILE.call("odd-running-header", {}, content)
    SILE.call("even-running-header", {}, content)
  end, "Text to appear on the top of the both page.")

  self:registerCommand("output-collated-notes", function (_, _)
    local notes = SILE.scratch.info.thispage.collated
    if not notes or #notes == 0 then
      return
    end

    local prec
    local oldCaseNeeded = caseNeeded -- FIXME EXPLAIN NO SIDE EFFECT ON PAGE CONTENT
    SILE.typesetter:leaveHmode()
    for _, note in ipairs(notes) do
      if prec and note.ref == prec then
        SILE.typesetter:typeset(" ")
      else
        SILE.typesetter:leaveHmode()
        SILE.call("color", { color = "#74101c" }, function ()
          SILE.typesetter:typeset(note.ref.." ")
        end)
      end
      caseNeeded = note.caseNeeded
      SILE.process(note.material)
      prec = note.ref
    end
    caseNeeded = oldCaseNeeded
    SILE.call("skip", { height = "1ex"})
  end, "Ouputs the collated notes for the current page (should be called at end of a page)")

  self:registerCommand("output-collated-variants", function (_, _)
    local variants = SILE.scratch.info.thispage.variants
    if not variants or #variants == 0 then
      return
    end

    local prec
    local oldCaseNeeded = caseNeeded -- FIXME EXPLAIN NO SIDE EFFECT ON PAGE CONTENT
    SILE.typesetter:leaveHmode()
    for _, variant in ipairs(variants) do
      if prec and variant.ref == prec then
        SILE.typesetter:typeset(" ")
      else
        SILE.typesetter:leaveHmode()
        SILE.call("color", { color = "#74101c" }, function ()
          SILE.typesetter:typeset(variant.ref.." ")
        end)
      end
      caseNeeded = variant.caseNeeded
      SILE.process(variant.material)
      prec = variant.ref
    end
    caseNeeded = oldCaseNeeded
    SILE.call("skip", { height = "1ex"})
  end, "Ouputs the collated notes for the current page (should be called at end of a page)")

  self:registerCommand("output-collated-sources", function (_, _)
    local sources = SILE.scratch.info.thispage.witnesses
    if not sources or #sources == 0 then
      return
    end

    local collated = pl.tablex.reduce(function (acc, elem)
      if acc and acc[#acc] and acc[#acc].witness == elem.witness then
        acc[#acc].last = elem
      else
        acc[#acc+1] = { first = elem, witness = elem.witness }
      end
      return acc
    end, sources, {})

    if #collated == 1 then
      SILE.typesetter:leaveHmode()
      SILE.call("strut")
      SILE.typesetter:typeset(MSSNAMES[collated[1].witness])
    else
      for _, v in ipairs(collated) do
        local first, last = v.first, v.last
        local ref
        if not last then
          ref = first.chapter .. ", "
              .. first.verse .. " "
        elseif first.book == last.book then
          if first.chapter == last.chapter then
              ref = first.chapter .. ", "
                  .. first.verse .. "–" .. last.verse .. " "
          else
            ref = first.chapter .. ", " .. first.verse
                  .. " – " .. last.chapter .. ", " .. last.verse .. " "
          end
        else
          ref = first.book
                .. " " .. first.chapter .. ", " .. first.verse
                .. ' – ' .. last.book
                .. " " .. last.chapter .. ", " .. last.verse .. " "
        end
        SILE.typesetter:leaveHmode()
        SILE.typesetter:typeset(ref)
        SILE.typesetter:leaveHmode()
        SILE.call("strut")
        SILE.typesetter:typeset(MSSNAMES[v.witness])
      end
    end
  end, "Ouputs the collated sources for the current page (should be called at end of a page)")

  self:registerCommand("collated-variant", function (options, content)
    SILE.call("info", { category = "variants", value = { ref = options.ref, caseNeeded = caseNeeded, material = content } })
  end, "Registers a collated (by reference) note")

  self:registerCommand("collated-note", function (options, content)
     SILE.call("info", { category = "collated", value = { ref = options.ref, caseNeeded = caseNeeded, material = content } })
  end, "Registers a collated (by reference) note")

  self:registerCommand("save-book-title", function (_, content)
    lastRef = { book = content[1] }
  end)

  self:registerCommand("save-chapter-number", function (_, content)
    lastRef = { book = lastRef.book, chapter = content[1] }
  end)

  self:registerCommand("save-verse-number", function (_, content)
    lastRef = { book = lastRef.book, chapter = lastRef.chapter, verse = content[1] }
    SILE.call("info", { category = "references", value = lastRef })
  end)

  self:registerCommand("save-verse-witness", function (_, content)
    if lastRef.book and lastRef.chapter and lastRef.verse then
      lastRef = { book = lastRef.book, chapter = lastRef.chapter, verse = lastRef.verse, witness = content[1] }
      SILE.call("info", { category = "witnesses", value = lastRef })
    end
  end)

  self:registerCommand("range-reference", function (_, _)
    local refs = SILE.scratch.info.thispage.references
    if refs and #refs > 0 then
      local first = refs[1]
      local last = refs[#refs]
      local ref
      if first.book == last.book then
        if first.chapter == last.chapter then
          ref = ALTBOOKNAMES[first.book]
                .. " " .. first.chapter .. ", "
                .. first.verse .. "–" .. last.verse
        else
          ref = ALTBOOKNAMES[first.book]
                .. " " .. first.chapter .. ", " .. first.verse
                .. " – " .. last.chapter .. ", " .. last.verse
        end
      else
        ref = ALTBOOKNAMES[first.book]
        .. " " .. first.chapter .. ", " .. first.verse
        .. ' – ' .. ALTBOOKNAMES[last.book]
        .. " " .. last.chapter .. ", " .. last.verse
      end
      SILE.call("uppercase", {}, { ref })
    end
  end)

  -- TEI TAGS - SUBSET AS USED IN THE GOTHIC BIBLE ("GOTICA") FROM WULFILA.BE

  self:registerCommand("TEI.2", function (_, content)
    processAsStructure(content)
  end)

  self:registerCommand("text", function (_, content)
    processAsStructure(content)
  end)

  self:registerCommand("teiHeader", function (_, _)
    -- Skip: header ignored for now
  end)

  self:registerCommand("front", function (_, content)
    local div = findInTree(content, "div") or {}
    for i = 1, #div do
      if type(div[i]) == "table" then
        if div[i].command == "div" and div[i].options.id == "books" then
          -- Extract book references from:
          -- <div id="books">
          --   <list>
          --     <item corresp="B1"><expan abbr="Mt">Matthew</expan></item>
          -- ...
          local list = findInTree(div[i], "list") or {}
          for _, item in ipairs(list) do
            if type(item) == "table" and item.command == "item" then
              local corresp = item.options.corresp
              local expan = findInTree(item, "expan")
              local abbr = expan.options.abbr
              local full = expan[1]
              books[corresp] = { abbr = abbr, title = full }
            end
          end
        end
      end
    end
  end)

  self:registerCommand("text", function (_, content)
    SILE.settings:temporarily(function ()
      SILE.call("language", { main = "en" }) -- HACK Quite random, but heh...
      SILE.call("font", { family = "Ulfilas", features = "+liga" })
      SILE.call("font:add-fallback", { family = "Libertinus Serif" })

      SILE.settings:set("linebreak.emergencyStretch", SILE.types.measurement("1em"))

      processAsStructure(content)
    end)
  end)

  self:registerCommand("body", function (_, content)
    -- Ensure headers and folios are enabled.
    -- They might have been cancelled by some external front material.
    SILE.call("headers")
    SILE.call("folios")
    -- Register our own headers
    SILE.call("running-headers", {}, {
      createCommand("font", { family = "Ulfilas" }), {
        createCommand("range-reference")
      }
    })
    processAsStructure(content)
  end)

  -- Typical structure in the TEI XML Gotica body:
  -- <div type="book" id="B1" n="1">
  --   <head>Matthaeus</head>
  --   <div type="chapter" n="5">
  --    <ab type="verse" n="15">
  --     <app>
  --      <rdg id="S1" wit="CA">
  --       <lacunaEnd/>
  --       <seg id="T1">ak</seg>
  -- (...)
  --       &p.period;
  --      </rdg>
  --     </app>
  --    </ab>
  -- (...)

  self:registerCommand("div", function (options, content)
    if options.type == "book" and tonumber(options.n) >= 20 then
      -- In this "modern" rendering, we do not include B20 (Signatures) and B21 (Calendars)
      return
    end

    if options.type == "book" then
      local book = books[options.id]
      local title = ALTBOOKNAMES[book.abbr] -- Ignore book.title, use our own
      --SILE.call("bigskip")
      --SILE.call("par") -- EEK??? FIXME
      print("<"..title..">") -- This doesnt display at right page number, FIXME REMOVE cool for debug but all broken
      SILE.call("open-on-any-page")
      SILE.call("noindent")
      SILE.call("save-book-title", {}, { book.abbr })
      SILE.call("color", { color = "#74101c" }, function () -- CHECK FIXME WAS 58101c
        SILE.call("font", { size = 14, weight = 700 } , { title })
        SILE.call("novbreak")
        SILE.call("par")
        SILE.call("novbreak")
      end)
      processAsStructure(content)
    elseif options.type == "chapter" or options.type == "leaf" then
      caseNeeded = true -- EXPLAIN FIXME
      SILE.call("smallskip")
      SILE.call("goodbreak")
      SILE.call("dropcap", { lines = 2, family = "Libertinus Serif", features = "+pnum",
        color = "#74101c", join = false }, function ()
          SILE.call("save-chapter-number", {}, { options.n })
          SILE.typesetter:typeset(options.n)
          SILE.call("kern", { width = "0.1em" })
      end)
      processAsStructure(content)
      SILE.call("par")
    else
      SU.error("Unexpected division type "..tostring(options.type)) -- SHALL NOT OCCUR
    end
  end)

  self:registerCommand("head", function (_, _)
    -- Ignore Streitberg's heading.
  end)

  self:registerCommand("app", function (_, content)
    SILE.call("set-counter", { id = "emendation", value = 0, display = "alpha" })
    SILE.call("set-counter", { id = "variant", value = 0, display = "greek" })
    weightStructure(content)
  end)

  self:registerCommand("ab", function (options, content)
    if options._pos_  and options._pos_  > 1 then
      SILE.typesetter:typeset(" ")
    end
    if caseNeeded == nil then
      -- Previous verse likely ended in with a lacuna.
      caseNeeded = true
    end
    if lastRef.verse and tonumber(lastRef.verse) + 1 ~= tonumber(options.n) then
      -- Obvious gap in numbering, so the ending punctuation of previous verse
      -- cannot be trusted.
      caseNeeded = true
    end

    SILE.call("save-verse-number", {}, { options.n })
    if tonumber(options.n) ~= 1 then
      SILE.call("color", { color = "#74101c" }, function ()
        SILE.call("textsuperscript", { fake = true }, { options.n })
      end)
      SILE.call("kern", { width = "1spc" })
    end
    processAsStructure(content)
  end)

  self:registerCommand("rdg", function (options, content)
    if options._selected_primary_ or options._selected_secondary_ then
      --if caseNeeded then SILE.typesetter:typeset("¤") end
      SILE.call("save-verse-witness", {}, { options.wit })
      if options._selected_secondary_ then
        SILE.call("color", { color = "#4682B4" },  function ()
          SILE.call("font", { family = "Symbola" }, { " ⸆" }) -- FIXME EXPLAIN + Absent from Libertinus
        end)
      end
      processAsStructure(content)
    end
    -- if not selected, skipped
  end)

  self:registerCommand("num", function (options, content)
    if options._pos_  and options._pos_  > 1 then
      SILE.typesetter:typeset(" ")
    end
    processAsStructure(content)
  end)


  self:registerCommand("seg", function (options, content)
    -- First trim trailing spaces from (potentially structured) content:
    -- We want to handle spacing on our own...
    local trimmed = trimSubContent(content)
    if options.type == "diff" then -- Variations
      -- Variations <seg type="diff"> are structured, containing other <seg>
      -- We do not mark the variations, just process the content...
      if options._pos_  and options._pos_  > 1 then
        -- Getting messy: we need to add an initial space UNLESS the variations
        -- starts with a punctuation
        if not startsWithPunct(trimmed) then
          SILE.typesetter:typeset(" ")
        end
      end
      -- Now process the content.
      if options.subtype == "5" then
        -- Supplemental content vs. other mss.
        SILE.call("color", { color = "#4682B4" }, { "⸄" }) -- U+2E04
        processAsStructure(trimmed)
        SILE.call("color", { color = "#4682B4" }, { "⸅" }) -- U+2E05
      elseif options.subtype == "6" then
        -- Supplemental content vs. lacuna/gap in other mss.
        -- Don't mark these
        processAsStructure(trimmed)
      elseif options.subtype == "7" then
        -- Supplemental punctuation vs. other mss.
        -- Don't mark these
        processAsStructure(trimmed)
      else
        SILE.call("color", { color = "#4682B4" }, { "⸂" }) -- U+2E02
        processAsStructure(trimmed)
        SILE.call("color", { color = "#4682B4" }, { "⸃" }) -- U+2E03
        if options._link_ then
          SILE.call("increment-counter", { id = "variant" })
          local count = self.class.packages.counters:formatCounter(SILE.scratch.counters.variant)
          SILE.call("color", { color = "#4682B4" }, function ()
            SILE.call("font", { family = "Libertinus Serif" }, function ()
              SILE.call("textsuperscript", { fake = true }, { count })
            end)
          end)
          local ref
          if lastRef.chapter then
            ref = lastRef.chapter .. ", " .. (lastRef.verse or "@")
          else
            ref = "¤"
          end
          SILE.call("collated-variant", { ref = ref }, function ()
            SILE.call("color", { color = "#4682B4" }, function ()
              SILE.call("font", { family = "Libertinus Serif" }, function ()
                SILE.call("textsuperscript", { fake = true }, { count })
                SILE.call("kern", { width = "0.5en" })
              end)
            end)
            SILE.call("font", { family = "Ulfilas", features = "+liga" }, function ()
              insideLinkingNote = true
              processAsStructure(options._link_)
              insideLinkingNote = false
            end)
          end)
        -- else
        --   SILE.typesetter:typeset("@@@") -- FIXME
        end
      end
    else
      -- Normal <seg>, i.e. words
      -- Supplement spacing
      if options._pos_  and options._pos_  > 1 then
        SILE.typesetter:typeset(" ")
      end
      -- Transform "_" and "~" (marking uncomplete words and assimilations)
      local text = self.class.packages.inputfilter:transformContent(trimmed, replaceSpecialChars)
      -- FIXME explain
      local emended, targetText, sourceText = parseEmendations(text)
      local count
      if emended and not insideLinkingNote then
        SILE.call("increment-counter", { id = "emendation" })
        count = self.class.packages.counters:formatCounter(SILE.scratch.counters.emendation)
        SILE.call("color", { color = "#4682B4" }, function ()
          SILE.call("font", { family = "Libertinus Serif", style = "italic" }, function ()
            SILE.call("textsuperscript", { fake = true }, { count })
            SILE.call("kern", { width = "0.1em" }) -- pseudo italic correction
          end)
        end)
      end
      if caseNeeded then
        -- Handle capitalization
        processCapitalize(targetText)
        caseNeeded = false
      else
        SILE.process(targetText)
      end
      if emended then
        if insideLinkingNote then
          SILE.call("font", { family = "Libertinus Serif" }, { " <"})
          -- SILE.typesetter:typeset(" <")
          SILE.call("kern", { width="0.5en"})
          SILE.process(sourceText)
        else
          local ref
          if lastRef.chapter then
            ref = lastRef.chapter .. ", " .. (lastRef.verse or "@")
          else
            ref = "¤"
          end
          SILE.call("collated-note", { ref = ref }, function ()
            SILE.call("color", { color = "#4682B4" }, function ()
              SILE.call("font", { family = "Libertinus Serif", style = "italic" }, function ()
                SILE.call("textsuperscript", { fake = true }, { count })
                SILE.call("kern", { width = "0.5en" })
              end)
            end)
            SILE.call("font", { family = "Ulfilas", features = "+liga" }, sourceText)
          end)
        end
      end
    end
  end)

  --
  -- LACUNA
  ---
  self:registerCommand("lacunaStart", function (options, _)
    if options._pos_  and options._pos_  > 1 then
      SILE.typesetter:typeset(" ")
    end
    SILE.typesetter:typeset("(. . .)")
    -- Quite fragile assymption here:
    -- (I had it to true at one point, but really we don't know.)
    -- A lacuna started. We probably don't know if the last seen punctuation
    -- is applicable...
    caseNeeded = nil
  end)
  self:registerCommand("lacunaEnd", function (options, _)
    if options._pos_  and options._pos_  > 1 then
      SILE.typesetter:typeset(" ")
    end
    SILE.typesetter:typeset("(. . .)")
    -- A lacuna ended. We don't know if the last seen punctuation is
    -- applicable.
    caseNeeded = nil
  end)
  self:registerCommand("gap", function (options, _)
    if options._pos_  and options._pos_  > 1 then
      SILE.typesetter:typeset(" ")
    end
    SILE.call("color", { color = "130" }, { ". . ." })
  end)

  --
  -- PUNCTUATION
  --
  self:registerCommand("c", function (options, content)
    if options.type ~= "punct" then
      return SU.warn("Unexpected <c> element (not of punct type)")
    end
    if content[1] ~= "—" then
      -- Check punctuation that require uppercasing of next word:
      -- anything but comma and semi-column.
      caseNeeded = content[1] ~= "," and content[1] ~= ";"
    else
      -- The emdashes do not count for altering case
      -- but need a space before, which is not encoded in the XML source.
      SILE.typesetter:typeset(" ")
    end
    SILE.process(content)
    if breakAtPeriod and not options._last_ and content[1] == "." then
      SILE.typesetter:leaveHmode() end
  end)

  --
  -- LEGIBILTY, EMENDATIONS, &c.
  --
  self:registerCommand("unclear", function (_, content)
    SILE.call("color", { color = "130" }, content)
  end)

  -- <del> tags occur at two different level in the TEI XML Gotica:
  --  - As structure elements, encapsulating sequences of <seg> etc. = This are
  --    the one we are dealing with here.
  --  - Inside <seg>, encapsulated world-level emendations = Those are caught
  --    in the seg processing, so we won't be called here.
  self:registerCommand("del", function (options, content)
    if options._pos_  and options._pos_  > 1 then
      SILE.typesetter:typeset(" ")
    end
    SILE.call("increment-counter", { id = "emendation" })
    local count = self.class.packages.counters:formatCounter(SILE.scratch.counters.emendation)
    SILE.call("color", { color = "#4682B4" }, function ()
      SILE.call("font", { family = "Libertinus Serif", style = "italic" }, function ()
        SILE.call("textsuperscript", { fake = true }, { "□"..count })
        SILE.call("kern", { width = "0.1em" }) -- pseudo italic correction
      end)
    end)
    local ref = lastRef.chapter .. ", " .. lastRef.verse
    SILE.call("collated-note", { ref = ref }, function ()
      SILE.call("color", { color = "#4682B4" }, function ()
        SILE.call("font", { family = "Libertinus Serif", style = "italic" }, function ()
          SILE.call("textsuperscript", { fake = true }, { count })
          SILE.call("kern", { width = "0.5en" })
        end)
      end)
      SILE.call("font", { family = "Ulfilas", features = "+liga" }, function ()
        if isStructure(content) then
          processAsStructure(content)
        else
          SILE.process(trimSubContent(content))
        end
      end)
    end)
  end)

  -- <add> tags too occur at two different level in the TEI XML Gotica:
  -- General comments on <del> apply here also.
  self:registerCommand("add", function (options, content)
    if options._pos_  and options._pos_  > 1 then
      SILE.typesetter:typeset(" ")
    end
    SILE.call("color", { color = "#4682B4" }, function ()
      SILE.call("font", { family = "Libertinus Serif" }, { "⸉" })
    end)
    if isStructure(content) then
      processAsStructure(content)
    else
      SILE.process(trimSubContent(content))
    end
    SILE.call("color", { color = "#4682B4" }, function ()
      SILE.call("font", { family = "Libertinus Serif" }, { "⸊" })
    end)
  end)

  --
  -- BOOK OPENER/CLOSER
  --

  self:registerCommand("centered-text-block", function (_, content)
    caseNeeded = true
    breakAtPeriod = true
    -- Block indented centering
    SILE.settings:temporarily(function ()
      SILE.settings:set("document.lskip", SILE.types.node.hfillglue("0.5cm"))
      SILE.settings:set("document.rskip", SILE.types.node.hfillglue("0.5cm"))
      SILE.settings:set("typesetter.parfillskip", SILE.types.node.glue())
      SILE.settings:set("document.parindent", SILE.types.node.glue())
      SILE.settings:set("document.spaceskip", SILE.types.length("1spc", 0, 0))
      SILE.process(content)
      SILE.call("par")
    end)
    breakAtPeriod = false
  end)

  self:registerCommand("opener", function (_, content)
    SILE.call("par")
    SILE.call("centered-text-block", {}, function ()
      SILE.call("color", { color = "#74101c" }, function ()
        SILE.call("font", { size = 13 }, function ()
          -- FIXME tracking opener/closer witness is broken
          SILE.call("save-chapter-number", {}, {})
          -- SILE.call("save-verse-number", {}, { "*" })
          processAsStructure(content)
        end)
      end)
    end)
    SILE.call("novbreak")
  end)

  self:registerCommand("closer", function (_, content)
    SILE.call("novbreak")
    SILE.call("medskip")
    SILE.call("novbreak")
    SILE.call("centered-text-block", {}, function ()
      SILE.call("novbreak")
      SILE.call("color", { color = "#74101c" }, function ()
        SILE.call("font", { size = 13 }, function ()
          -- FIXME tracking opener/closer witness is broken
          SILE.call("save-chapter-number", {}, {})
          -- SILE.call("save-verse-number", {}, { "*" })
          processAsStructure(content)
        end)
      end)
    end)
    SILE.call("par")
  end)

  --
  -- QUOTATIONS
  --
  -- In the XML TEI source, it seems <quote> is used around sentences (containing several <seg>s)
  -- and <q> around single words (one <seg>).
  -- We handle them identically, and opt for German-like quotation marks in our "modern" rendering.
  --
  self:registerCommand("quote", function (options, content)
    if options._pos_  and options._pos_  > 1 then
      SILE.typesetter:typeset(" ")
    end
    SILE.typesetter:typeset("„")
    processAsStructure(content)
    SILE.typesetter:typeset("“")
  end)

  self:registerCommand("q", function (options, content)
    if options._pos_  and options._pos_  > 1 then
      SILE.typesetter:typeset(" ")
    end
    SILE.typesetter:typeset("„")
    processAsStructure(content)
    SILE.typesetter:typeset("“")
  end)

end

function package:registerStyles ()
  base.registerStyles(self)

  -- FIXME TODO
end

package.documentation = [[
\begin{document}

\end{document}]]

return package
