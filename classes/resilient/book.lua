--
-- A new advanced book class for SILE.
-- Following the resilient styling paradigm, and providing a more features.
--
-- 2021-2025, Didier Willis
-- License: MIT
--
local base = require("classes.resilient.base")
local class = pl.class(base)
class._name = "resilient.book"

local ast = require("silex.ast")
local createCommand, subContent, extractFromTree
        = ast.createCommand, ast.subContent, ast.extractFromTree

local layoutParser = require("resilient.layoutparser")

SILE.scratch.book = SILE.scratch.book or {}
SILE.scratch.book.headers = {
  novel = true,
  technical = true,
  none = true
}

local DIVISIONNAME = {
  "frontmatter",
  "mainmatter",
  "backmatter"
}

-- CLASS DEFINITION

function class:_init (options)
  base._init(self, options)
  self.resilientState = {}

  self:loadPackage("resilient.sectioning")
  self:loadPackage("masters")
  self:defineMaster({
    id = "right",
    firstContentFrame = self.firstContentFrame,
    frames = self.oddFrameset
  })
  self:defineMaster({
    id = "left",
    firstContentFrame = self.firstContentFrame,
    frames = self.evenFrameset
  })
  self:loadPackage("twoside", { oddPageMaster = "right", evenPageMaster = "left" })
  self:loadPackage("resilient.tableofcontents")
  if not SILE.scratch.headers then SILE.scratch.headers = {} end
  self:loadPackage("resilient.footnotes", {
    insertInto = "footnotes",
    stealFrom = { "content" }
  })

  self:loadPackage("labelrefs")
  self:loadPackage("struts")
  self:loadPackage("resilient.headers")

  self:loadPackage("markdown")
  self:loadPackage("djot")
  -- Once Djot is loaded, we can register custom pre-defined symbols
  self.packages["markdown.commands"]:registerSymbol("_BIBLIOGRAPHY_", true, function (opts)
    if not self.packages.bibtex then
      SU.warn("Bibliography support is not available")
      return {}
    end
    return {
      createCommand("printbibliography", opts)
    }
  end)

  -- Override document.parindent default to this author's taste
  SILE.settings:set("document.parindent", "1.25em")
  -- Override with saner defaults:
  -- Slightly prefer underfull lines over ugly overfull content
  -- I used a more drastic value before, but realize it can have bad effects
  -- too, so for a default value let's be cautious. It's still better then 0
  -- in my opinion for the general usage.
  SILE.settings:set("linebreak.emergencyStretch", "1em")
  -- This should never have been 1.2 by default:
  -- https://github.com/sile-typesetter/sile/issues/1371
  SILE.settings:set("shaper.spaceenlargementfactor", 1)

  -- Command override from loaded packages.
  -- TRICKY, TO REMEMBER: Such overrides cannot be done in registerCommands()
  -- as packages are not loaded yet.
  -- ASSUMPTION: The corresponding packages are already loaded.
  -- (Also, we must be sure that reloading them will not reset the hook...
  -- but our base class cancels the multiple instanciation from SILE 0.14,
  -- so we should be safe here)

  -- Override the standard foliostyle hook to rely on styles
  -- Package "folio" is loaded by the plain class.
  self:registerCommand("foliostyle", function (_, content)
    local styleName = SILE.documentState.documentClass:oddPage() and "folio-odd" or "folio-even"
    local division = self.resilientState.division or 2
    SILE.call("style:apply:paragraph", { name = styleName }, {
      -- Ensure proper baseline alignment with a strut rule.
      -- The baseline placement depends on the line output algorithm, and we cannot
      -- trust it if it just uses the line ascenders.
      -- Typically, if folios use "old-style" numbers, 16 and 17 facing pages shall have
      -- aligned folios, but the 1 is smaller than the 6 and 7, the former ascends above,
      -- and the latter descends below the baseline).
      createCommand("strut", { method = "rule"}),
      createCommand("style:apply:number", {
        name = "folio-" .. DIVISIONNAME[division],
        text = SU.ast.contentToString(content),
      })
    })
  end)

  -- Override the standard urlstyle hook to rely on styles
  -- Package "url" is loaded by the markdown package.
  self:registerCommand("urlstyle", function (_, content)
    SILE.call("style:apply", { name = "url" }, content)
  end)

  -- Override the standard math:numberingstyle hook to rely on styles,
  -- and also to subscribe for cross-references.
  -- Package "math" is loaded by the markdown package.
  self:registerCommand("math:numberingstyle", function (opts, _)
    local text
    local stylename = "eqno"
    if opts.counter then
      local altname = "eqno-" .. opts.counter
      local fnSty = self:resolveStyle(altname, true) -- discardable
      if not next(fnSty) then
        fnSty = self:resolveStyle(stylename) -- fallback
      else
        stylename = altname
      end

      local display = fnSty.numbering and fnSty.numbering.display or "arabic"
      -- Enforce the display style for the counter
      -- (which might be the default 'equation' counter, or a custom one)
      SILE.call("set-counter", { id = opts.counter, display = display })
      text = self.packages.counters:formatCounter(SILE.scratch.counters[opts.counter])
    elseif opts.number then
      text = opts.number
    else
      SU.error("No counter or number provided for math numbering")
    end
    -- Cross-ref support (from markdown, we can get an id, in most of our packages,
    -- we can get a marker, play fair with all)
    local mark = opts.id or opts.marker
    if mark then
      local labelRefs = self.packages.labelrefs
      labelRefs:pushLabelRef(text)
      SILE.call("style:apply:number", { name = stylename, text = text })
      SILE.call("label", { marker = mark })
      labelRefs:popLabelRef()
    else
      SILE.call("style:apply:number", { name = stylename, text = text })
    end
  end)
end

function class:declareOptions ()
  base.declareOptions(self)

  self:declareOption("layout", function(_, value)
    if value then
      self.layout = value
    end
    return self.layout
  end)

  self:declareOption("offset", function(_, value)
    if value then
      self.offset = value
    end
    return self.offset
  end)

  self:declareOption("headers", function(_, value)
    if value then
      if not SILE.scratch.book.headers[value] then
        SU.warn("Unknown headers type '".. value .. "', switching to 'technical'")
        value = "technical"
      end
      self.headers = value
    end
    return self.headers
  end)
end

function class:setOptions (options)
  options = options or {}
  options.layout = options.layout or "division"
  options.headers = options.headers or "technical"
  base.setOptions(self, options) -- so that papersize etc. get processed...

  local layout = layoutParser:match(options.layout)
  if not layout then
    SU.warn("Unknown page layout '".. options.layout .. "', switching to 'division'")
    layout = layoutParser:match("division")
  end

  local offset = SU.cast("measurement", options.offset or "0")
  layout:setOffset(offset)

  -- Kind of a hack dues to restrictions with frame parsers.
  layout:setPaperHack(SILE.documentState.paperSize[1], SILE.documentState.paperSize[2])

  -- TRICKY, TO REMEMBER:
  -- the default frameset has to be set *before* the completion of
  -- the base (plain) class init, or it isn't applied on the first
  -- page...
  self.oddFrameset, self.evenFrameset = layout:frameset()
  self.defaultFrameset = self.oddFrameset
end

function class:registerStyles ()
  base.registerStyles(self)

  -- Front, main, back matter
  local divisionFolio = {
    frontmatter = "roman",
  }
  for _, name in ipairs(DIVISIONNAME) do
    self:registerStyle("folio-" .. name, {}, {
      numbering = {
        display = divisionFolio[name] or "arabic"
      }
    })
  end

  -- Sectioning styles
  self:registerStyle("sectioning-base", {}, {
    paragraph = { before = { indent = false },
                  after = { indent = false } }
  })
  self:registerStyle("sectioning-part", { inherit = "sectioning-base" }, {
    font = { weight = 700, size = "1.6em" },
    paragraph = { before = { skip = "15%fh" },
                  align = "center",
                  after = { skip = "bigskip" } },
    sectioning = {  counter = { id ="parts", level = 1 },
                    settings = {
                      toclevel = 0,
                      open = "odd"
                    },
                    numberstyle= {
                      main = "sectioning-part-main-number",
                      header = "sectioning-part-head-number",
                      reference = "sectioning-part-ref-number"
                    },
                    hook = "sectioning:part:hook" },
  })
  self:registerStyle("sectioning-chapter", { inherit = "sectioning-base" }, {
    font = { weight = 700, size = "1.4em" },
    paragraph = {  align = "left",
                   after = { skip = "bigskip" } },
    sectioning = { counter = { id = "sections", level = 1 },
                    settings = {
                      toclevel = 1,
                      open = "odd"
                    },
                    numberstyle= {
                      main = "sectioning-chapter-main-number",
                      header = "sectioning-chapter-head-number",
                      reference = "sectioning-chapter-ref-number",
                    },
                    hook = "sectioning:chapter:hook" },
  })
  self:registerStyle("sectioning-section", { inherit = "sectioning-base" }, {
    font = { weight = 700, size = "1.2em" },
    paragraph = { before = { skip = "bigskip" },
                  after = { skip = "medskip", vbreak = false } },
    sectioning = {  counter = { id = "sections", level = 2 },
                    settings = {
                      toclevel = 2
                    },
                    numberstyle= {
                      main = "sectioning-other-number",
                      header = "sectioning-other-number",
                      reference = "sectioning-other-number",
                    },
                    hook = "sectioning:section:hook" },
  })
  self:registerStyle("sectioning-subsection", { inherit = "sectioning-base"}, {
    font = { weight = 700, size = "1.1em" },
    paragraph = { before = { skip = "medskip" },
                  after = { skip = "smallskip", vbreak = false } },
    sectioning = {  counter = { id = "sections", level = 3 },
                    settings = {
                      toclevel = 3
                    },
                    numberstyle= {
                      main = "sectioning-other-number",
                      header = "sectioning-other-number",
                      reference = "sectioning-other-number",
                    } },
  })
  self:registerStyle("sectioning-subsubsection", { inherit = "sectioning-base" }, {
    font = { weight = 700 },
    paragraph = { before = { skip = "smallskip" },
                  after = { vbreak = false } },
    sectioning = {  counter = { id = "sections", level = 4 },
                    settings = {
                      toclevel = 4
                    },
                    numberstyle= {
                      main = "sectioning-other-number",
                      header = "sectioning-other-number",
                      reference = "sectioning-other-number",
                    } },
  })
  self:registerStyle("sectioning-appendix", { inherit = "sectioning-chapter" }, {
    sectioning = { numberstyle= {
                      main = "sectioning-appendix-main-number",
                      header = "sectioning-appendix-head-number",
                      reference = "sectioning-appendix-ref-number",
                    },
                  },
  })

  self:registerStyle("sectioning-part-base-number", {}, {
    numbering = { display = "ROMAN" }
  })
  self:registerStyle("sectioning-part-main-number", { inherit = "sectioning-part-base-number" }, {
    font = { features = "+smcp" },
    numbering = { before = { text ="Part " },
                  standalone = true },
  })
  self:registerStyle("sectioning-part-head-number", { inherit = "sectioning-part-base-number" }, {
    numbering = { after = { text =".", kern = "iwsp" } },
  })

  self:registerStyle("sectioning-part-ref-number", { inherit = "sectioning-part-base-number" }, {
    numbering = { before = { text ="part " } },
  })

  self:registerStyle("sectioning-chapter-base-number", {}, {
  })
  self:registerStyle("sectioning-chapter-main-number", { inherit = "sectioning-chapter-base-number" }, {
    font = { size = "0.9em" },
    numbering = { before = { text = "Chapter "} ,
                  after = { text = "." },
                  standalone = true },
  })
  self:registerStyle("sectioning-chapter-head-number", { inherit = "sectioning-chapter-base-number" }, {
    numbering = { after = { text =".", kern = "iwsp" } },
  })
  self:registerStyle("sectioning-chapter-ref-number", { inherit = "sectioning-chapter-base-number" }, {
    numbering = { before = { text ="chap. " } },
  })

  self:registerStyle("sectioning-appendix-main-number", { inherit = "sectioning-chapter-main-number" }, {
    numbering = { before = { text = "Appendix "},
                  display = "ALPHA",
                },
  })
  self:registerStyle("sectioning-appendix-head-number", { inherit = "sectioning-chapter-head-number" }, {
  })
  self:registerStyle("sectioning-appendix-ref-number", { inherit = "sectioning-chapter-ref-number" }, {
    numbering = { before = { text ="app. " } },
  })

  self:registerStyle("sectioning-other-number", {}, {
    numbering = { after = { text = ".", kern = "iwsp" } }
  })

  -- folio styles
  self:registerStyle("folio-base", {}, {
    font = { features = "+onum" }
  })
  self:registerStyle("folio-even", { inherit = "folio-base" }, {
    paragraph = { align = "left" ,
                  before = { indent = false } }
  })
  self:registerStyle("folio-odd", { inherit = "folio-base" }, {
    paragraph = { align = "right" ,
                  before = { indent = false } }
  })

  -- header styles
  self:registerStyle("header-base", {}, {
    font = { size = "0.9em" },
    paragraph = { before = { indent = false },
                  after = { indent = false } }
  })
  self:registerStyle("header-even", { inherit = "header-base" }, {
  })
  self:registerStyle("header-odd", { inherit = "header-base" }, {
    font = { style = "italic" },
    paragraph = { align = "right" }
  })

  -- quotes
  SILE.scratch.styles.alignments["block"] = "blockindent"
  SILE.scratch.styles.alignments["quotation"] = "quoteindent"

  self:registerStyle("blockquote", {}, {
    font = { size = "0.95em" },
    paragraph = { before = { skip = "smallskip" },
                  align = "block",
                  after = { skip = "smallskip" } }
  })

  -- captioned elements
  self:registerStyle("figure", {}, {
    paragraph = { before = { skip = "smallskip", indent = false },
                  align = "center",
                  after = { vbreak = false } },
  })
  self:registerStyle("figure-caption", {}, {
    font = { size = "0.95em" },
    paragraph = { before = { skip = "medskip", indent = false, vbreak = false },
                  align = "center",
                  after = { skip = "medskip" } },
    sectioning = {  counter = { id = "figures", level = 1 },
                    settings = {
                      toclevel = 5,
                      bookmark = false,
                      goodbreak = false
                    },
                    numberstyle= {
                      main ="figure-caption-main-number",
                      reference ="figure-caption-ref-number"
                    } },
  })
  self:registerStyle("figure-caption-base-number", {}, {})
  self:registerStyle("figure-caption-main-number", { inherit = "figure-caption-base-number" }, {
    numbering = { before = { text = "Figure " },
                  after = { text = ".", kern = "iwsp" } },
    font = { features = "+smcp" },
  })
  self:registerStyle("figure-caption-ref-number", { inherit = "figure-caption-base-number" }, {
    numbering = { before = { text = "fig. " } }
  })

  self:registerStyle("table", {}, {
    paragraph = { align = "center",
                  before = { indent = false },
                  after = { vbreak = false } },
  })
  self:registerStyle("table-caption", {}, {
    font = { size = "0.95em" },
    paragraph = { before = { indent = false, vbreak = false },
                  align = "center",
                  after = { skip = "medskip" } },
    sectioning = {  counter = { id = "table", level = 1 },
                    settings = {
                      toclevel = 6,
                      bookmark = false,
                      goodbreak = false
                    },
                    numberstyle= {
                      main = "table-caption-main-number",
                      reference = "table-caption-ref-number",
                    } }
  })
  self:registerStyle("table-caption-base-number", {}, {})
  self:registerStyle("table-caption-main-number", { inherit = "table-caption-base-number" }, {
    numbering = { before = { text = "Table " },
                  after = { text = ".", kern = "iwsp" } },
    font = { features = "+smcp" },
  })
  self:registerStyle("table-caption-ref-number", { inherit = "table-caption-base-number" }, {
    numbering = { before = { text = "table " } }
  })

  self:registerStyle("listing", {}, {
    paragraph = { before = { skip = "smallskip", indent = false },
                  after = { vbreak = false } },
  })
  self:registerStyle("listing-caption", {}, {
    font = { size = "0.95em" },
    paragraph = { before = { skip = "smallskip", indent = false, vbreak = false },
                  align = "center",
                  after = { skip = "medskip" } },
    sectioning = {  counter = { id = "listings", level = 1 },
                    settings = {
                      toclevel = 7,
                      bookmark = false,
                      goodbreak = false
                    },
                    numberstyle= {
                      main ="listing-caption-main-number",
                      reference ="listing-caption-ref-number"
                    } },
  })
  self:registerStyle("listing-caption-base-number", {}, {})
  self:registerStyle("listing-caption-main-number", { inherit = "listing-caption-base-number" }, {
    numbering = { before = { text = "Listing " },
                  after = { text = ".", kern = "iwsp" } },
    font = { features = "+smcp" },
  })
  self:registerStyle("listing-caption-ref-number", { inherit = "listing-caption-base-number" }, {
    numbering = { before = { text = "listing " } }
  })


  -- code
  -- Default is similar to the original plain \code command, and quite as bad, but at
  -- least uses a font-relative size.
  self:registerStyle("code", {}, {
    font = {
      family = "Hack",
      size = "1.4ex"
    }
  })

  -- url style
  self:registerStyle("url", { inherit = "code"}, {
  })

  -- display math equation numberstyle
  self:registerStyle("eqno", {}, {
    numbering = {
      before = { text = "(" },
      display = "arabic",
      after = { text = ")" }
    }
  })

  -- Special non-standard style for dropcaps (for commands initial-joined and initial-unjoined)
  self:registerStyle("dropcap", {}, {
    font = { family = "Zallman Caps" },
    special = {
      lines = 2
    }
  })
end

function class:endPage ()
  if SILE.scratch.info.thispage.headerOdd then
    SILE.scratch.headers.odd = SILE.scratch.info.thispage.headerOdd[#SILE.scratch.info.thispage.headerOdd]
  end
  if SILE.scratch.info.thispage.headerEven then
    SILE.scratch.headers.even = SILE.scratch.info.thispage.headerEven[#SILE.scratch.info.thispage.headerEven]
  end
  if self:oddPage() then
    self.packages["resilient.headers"]:outputHeader(SILE.scratch.headers.odd)
  else
    self.packages["resilient.headers"]:outputHeader(SILE.scratch.headers.even)
  end
  return base.endPage(self)
end

function class:declareSettings ()
  base.declareSettings(self)

  SILE.settings:declare({
    parameter = "book.blockquote.margin",
    type = "measurement",
    default = SILE.types.measurement("2em"),
    help = "Margin (indentation) for block quotes"
  })
end

function class:registerCommands ()
  base.registerCommands(self)

  -- Running headers

  self:registerCommand("book-title", function (_, content)
    if self.headers == "novel" then
      SILE.call("even-running-header", {}, content)
    end
  end, "Book title low-level command (for running headers depending on headers type)")

  self:registerCommand("even-tracked-header", function (_, content)
    local headerContent = function ()
      SILE.call("style:apply:paragraph", { name = "header-even" }, {
        createCommand("strut", { method = "rule"}),
        subContent(content)
      })
    end
    SILE.call("info", {
      category = "headerEven",
      value = headerContent
    })
  end, "Text to appear on the top of even pages, tracked via info nodes.")

  self:registerCommand("odd-tracked-header", function (_, content)
    local headerContent = function ()
      SILE.call("style:apply:paragraph", { name = "header-odd" }, {
        createCommand("strut", { method = "rule"}),
        subContent(content)
      })
    end
    SILE.call("info", {
      category = "headerOdd",
      value = headerContent
    })
  end, "Text to appear on the top of odd pages, tracked via info node.")

  self:registerCommand("even-running-header", function (_, content)
    SILE.scratch.headers.even = function ()
      SILE.call("style:apply:paragraph", { name = "header-even" }, {
        createCommand("strut", { method = "rule"}),
        subContent(content)
      })
    end
  end, "Text to appear on the top of even pages.")

  self:registerCommand("odd-running-header", function (_, content)
    SILE.scratch.headers.odd = function ()
      SILE.call("style:apply:paragraph", { name = "header-odd" }, {
        createCommand("strut", { method = "rule"}),
        subContent(content)
      })
    end
  end, "Text to appear on the top odd pages.")

  -- front/main/back matter

  self:registerCommand("internal:division", function (options, _)
    local division = SU.required(options, "division", "internal:division")
    -- Always start on an odd page, so as to be consistent with the folio numbering
    -- in case it is reset.
    SILE.call("open-on-odd-page")
    self.resilientState.division = division
    -- Previous section titles (in technical mode) or chapter title (in novel mode)
    -- is no longer valid (and in none mode, it's not valid anyway).
    SILE.scratch.headers.odd = nil
    if self.headers == "technical" then
      -- In novel mode, the book title is in the even header, and is still valid
      -- So we don't reset it.
      -- But in technical mode, even headers contain the current chapter title,
      -- invalid upon a new part.
      SILE.scratch.headers.even = nil
    end
    -- Reset folio counter if needed (i.e. on display format change)
    local current = self:getCounter("folio")
    local folioSty = self:resolveStyle("folio-" .. DIVISIONNAME[division])
    local display = folioSty.numbering and folioSty.numbering.display or "arabic"
    if current.display ~= display then
      SILE.call("set-counter", { id = "folio", display = display, value = 1 })
    end
  end)

  for div, name in ipairs(DIVISIONNAME) do
    self:registerCommand(name, function (_, content)
      if self.resilientState.division and self.resilientState.division >= div then
        SU.error("\\" .. name .. " is not valid after a " .. DIVISIONNAME[self.resilientState.division])
      end
      SILE.call("internal:division", { division = div }, content)
    end, "Switch to " .. DIVISIONNAME[div] .. " division.")
  end

  -- Sectioning hooks and commands

  self:registerCommand("sectioning:part:hook", function (options, _)
    local before = SU.boolean(options.before, false)
    if before then
      -- Parts cancel headers and folios
      SILE.call("noheaderthispage")
      SILE.call("nofoliothispage")
      -- Previous section titles (in technical mode) or chapter title (in novel mode)
      -- is no longer valid (and in none mode, it's not valid anyway).
      SILE.scratch.headers.odd = nil
      if self.headers == "technical" then
        -- In novel mode, the book title is in the even header, and is still valid
        -- So we don't reset it.
        -- But in technical mode, even headers contain the current chapter title,
        -- invalid upon a new part.
        SILE.scratch.headers.even = nil
      end
      -- Parts reset footnotes and chapters
      SILE.call("set-counter", { id = "footnote", value = 1 })
      SILE.call("set-multilevel-counter", { id = "sections", level = 1, value = 0 })
    end
  end, "Apply part hooks (counter resets, footers and headers, etc.)")

  self:registerCommand("sectioning:chapter:hook", function (options, content)
    local before = SU.boolean(options.before, false)
    if before then
      -- Chapters re-enable folios, have no header, and reset the footnote counter.
      SILE.call("noheaderthispage")
      SILE.call("folios")
      SILE.call("set-counter", { id = "footnote", value = 1 })
    else
      if self.headers == "novel" then
        SILE.call("odd-tracked-header", {}, content)
      elseif self.headers == "technical" then
        SILE.call("even-tracked-header", {}, content)
        -- In technical mode, the odd header contains a section title, and is
        -- no longer valid upon a new chapter.
        SILE.scratch.headers.odd = nil
      end
    end
  end, "Apply chapter hooks (counter resets, footers and headers, etc.)")

  self:registerCommand("sectioning:section:hook", function (options, content)
    local before = SU.boolean(options.before, false)
    if not before then
      if self.headers == "technical" then
        SILE.call("odd-tracked-header", {}, content)
      end
    end
  end, "Applies section hooks (footers and headers, etc.)")

  self:registerCommand("appendix", function (_, _)
    if self.resilientState.appendix then
      SU.error("Already in the \\appendix subdivision")
    end
    if self.resilientState.division and self.resilientState.division < 2 then
      SU.error("\\appendix is not valid in " .. DIVISIONNAME[self.resilientState.division])
    end
    self.resilientState.appendix = true
    SILE.call("set-multilevel-counter", { id = "sections", level = 1, value = 0 })
  end, "Switch to appendix subdivision.")

  self:registerCommand("part", function (options, content)
    if self.resilientState.division and self.resilientState.division ~= 2 then
      -- By definition, parts are unnumbered in all divisions except the mainmatter
      options.numbering = false
    end
    options.style = "sectioning-part"
    -- Allow appendices again in a new part
    self.resilientState.appendix = false
    SILE.call("sectioning", options, content)
  end, "Begin a new part.")

  self:registerCommand("chapter", function (options, content)
    if not self.resilientState.appendix and self.resilientState.division and self.resilientState.division ~= 2 then
      -- By definition, chapters are unnumbered in all divisions except the mainmatter
      options.numbering = false
    end
    options.style = self.resilientState.appendix and "sectioning-appendix" or "sectioning-chapter"
    SILE.call("sectioning", options, content)
  end, "Begin a new chapter.")

  self:registerCommand("section", function (options, content)
    options.style = "sectioning-section"
    SILE.call("sectioning", options, content)
  end, "Begin a new section.")

  self:registerCommand("subsection", function (options, content)
    options.style = "sectioning-subsection"
    SILE.call("sectioning", options, content)
  end, "Begin a new subsection.")

  self:registerCommand("subsubsection", function (options, content)
    options.style = "sectioning-subsubsection"
    SILE.call("sectioning", options, content)
  end, "Begin a new subsubsection.")

  -- Quotes

  self:registerCommand("blockindent", function (_, content)
    SILE.settings:temporarily(function ()
      local indent = SILE.settings:get("book.blockquote.margin"):absolute()
      local lskip = SILE.settings:get("document.lskip") or SILE.types.node.glue()
      local rskip = SILE.settings:get("document.rskip") or SILE.types.node.glue()
      SILE.settings:set("document.lskip", SILE.types.node.glue(lskip.width:absolute() + indent))
      SILE.settings:set("document.rskip", SILE.types.node.glue(rskip.width:absolute() + indent))
      SILE.process(content)
      SILE.call("par")
    end)
  end, "Typeset its contents in a right and left indented block.")

  self:registerCommand("quoteindent", function (_, content)
    SILE.settings:temporarily(function ()
      local indent = SILE.settings:get("book.blockquote.margin"):absolute() * 0.875
      local lskip = SILE.settings:get("document.lskip") or SILE.types.node.glue()
      local rskip = SILE.settings:get("document.rskip") or SILE.types.node.glue()
      SILE.settings:set("document.lskip", SILE.types.node.glue(lskip.width:absolute() + indent))
      SILE.settings:set("document.rskip", SILE.types.node.glue(rskip.width:absolute() + indent * 0.5))
      SILE.process(content)
      SILE.call("par")
    end)
  end, "Typeset its contents in a right and left indented block (variant).")

  self:registerCommand("blockquote", function (options, content)
    local variant = options.variant and "blockquote-" .. options.variant or nil
    local style = variant and self.styles:hasStyle(variant) and variant or "blockquote"
    SILE.call("style:apply:paragraph", { name = style }, content)
  end, "Typeset its contents in a styled blockquote.")

  -- Captioned elements
  -- N.B. Despite the similar naming to LaTeX, these are not "floats"

  self:registerCommand("captioned-figure", function (options, content)
    if type(content) ~= "table" then SU.error("Expected a table content in figure environment") end
    local caption = extractFromTree(content, "caption")

    options.style = "figure-caption"
    SILE.call("style:apply:paragraph", { name = "figure" }, content)
    if caption then
      SILE.call("sectioning", options, caption)
    else
      -- It's bad to use the figure environment without caption, it's here for that.
      -- So I am not even going to use styles here.
      SILE.call("smallskip")
    end
  end, "Insert a captioned figure.")

  self:registerCommand("captioned-table", function (options, content)
    if type(content) ~= "table" then SU.error("Expected a table content in table environment") end
    local caption = extractFromTree(content, "caption")

    options.style = "table-caption"
    SILE.call("style:apply:paragraph", { name = "table" }, content)
    if caption then
      SILE.call("sectioning", options, caption)
    else
      -- It's bad to use the table environment without caption, it's here for that.
      -- So I am not even going to use styles here.
      SILE.call("smallskip")
    end
  end, "Insert a captioned table.")

  self:registerCommand("captioned-listing", function (options, content)
    if type(content) ~= "table" then SU.error("Expected a table content in listing environment") end
    local caption = extractFromTree(content, "caption")

    options.style = "listing-caption"
    SILE.call("style:apply:paragraph", { name = "listing" }, content)
    if caption then
      SILE.call("sectioning", options, caption)
    else
      -- It's bad to use the table environment without caption, it's here for that.
      -- So I am not even going to use styles here.
      SILE.call("smallskip")
    end
  end, "Insert a captioned table.")

  self:registerCommand("table", function (options, content)
    SILE.call("captioned-table", options, content)
  end, "Alias to captioned-table.")

  self:registerCommand("figure", function (options, content)
    SILE.call("captioned-figure", options, content)
  end, "Alias to captioned-figure.")

  self:registerCommand("listing", function (options, content)
    SILE.call("captioned-listing", options, content)
  end, "Alias to captioned-listing.")

  self:registerCommand("listoffigures", function (_, _)
    local figSty = self.styles:resolveStyle("figure-caption")
    local start = figSty.sectioning
      and figSty.sectioning.settings and figSty.sectioning.settings.toclevel
      or SU.error("Figure style does not specify a TOC level sectioning")

    SILE.call("tableofcontents", { start = start, depth = 0 })
  end, "Output the list of figures.")

  self:registerCommand("listoftables", function (_, _)
    local tabSty = self.styles:resolveStyle("table-caption")
    local start = tabSty.sectioning
      and tabSty.sectioning.settings and tabSty.sectioning.settings.toclevel
      or SU.error("Table style does not specify a TOC level sectioning")

    SILE.call("tableofcontents", { start = start, depth = 0 })
  end, "Output the list of tables.")

  self:registerCommand("listoflistings", function (_, _)
    local lstSty = self.styles:resolveStyle("listing-caption")
    local start = lstSty.sectioning
      and lstSty.sectioning.settings and lstSty.sectioning.settings.toclevel
      or SU.error("Listing style does not specify a TOC level sectioning")

    SILE.call("tableofcontents", { start = start, depth = 0 })
  end, "Output the list of listings.")

  -- Special dropcaps (provided as convenience)
  -- Also useful as pseudo custom style in Markdown or Djot.

  self:registerCommand("book:dropcap", function (options, content)
    local join = SU.boolean(options.join, true)
    local style = options.style or "dropcap"

    if type(content) ~= "table" then SU.error("Expected a table content in dropcap environment") end
    if #content ~= 1 then SU.error("Expected a single letter in dropcap environment") end
    local letter = content[1]

    local dropcapSty = self.styles:resolveStyle(style)
    local lines = dropcapSty.special and dropcapSty.special.lines
    if not lines then
      -- Fallback to regular style
      SILE.call('style:apply', { name = style }, { letter })
    else
      local color = dropcapSty.color
      local family = dropcapSty.font and dropcapSty.font.family
      if dropcapSty.properties or dropcapSty.decoration then
        -- I am not convinced the extra complexity is worth it for such an edge case.
        SU.warn("Dropcap style does not support properties and decoration")
      end
      SILE.call("use", { module = "packages.dropcaps" })
      SILE.call("dropcap", { family = family, lines = lines, join = join, color = color }, { letter })
    end
  end, "Style-aware initial capital letter (normally and internal command)")

  self:registerCommand("initial-joined", function (options, content)
    SILE.call("book:dropcap", { style = options.style, join = true }, content)
  end, "Style-aware initial capital letter, joined to the following text.")

  self:registerCommand("initial-unjoined", function (options, content)
    SILE.call("book:dropcap", { style = options.style, join = false }, content)
  end, "Style-aware initial capital letter, not joined to the following text.")

  -- Layouts

  self:registerCommand("showlayout", function (options, _)
    local spec = SU.required(options, "layout", "layout")
    local papersize = SU.required(options, "papersize", "layout")
    local offset = SU.cast("measurement", options.offset or "0")
    local layout = layoutParser:match(spec)
    if not layout then
      SU.error("Unrecognized layout '" .. spec .. "'")
    end
    local p = SILE.papersize(papersize)
    local W = p[1]
    local H = p[2]
    layout:setOffset(offset)
    layout:setPaperHack(W, H)
    layout:draw(W, H, { ratio = options.ratio, rough = options.rough })
  end, "Show a graphical representation of a page layout")

  self:registerCommand("layout", function (options, _)
    local spec = SU.required(options, "layout", "layout")
    local layout = layoutParser:match(spec)
    if not layout then
      SU.error("Unknown page layout '".. spec .. "'")
    end
    local offset = SU.cast("measurement", self.options["offset"])
    layout:setOffset(offset)
    -- Kind of a hack dues to restrictions with frame parsers.
    layout:setPaperHack(SILE.documentState.paperSize[1], SILE.documentState.paperSize[2])

    SILE.call("open-on-any-page")

    local oddFrameset, evenFrameset = layout:frameset()
    self:defineMaster({
      id = "right",
      firstContentFrame = self.firstContentFrame,
      frames = oddFrameset
    })
    self:defineMaster({
      id = "left",
      firstContentFrame = self.firstContentFrame,
      frames = evenFrameset
    })
    self:switchMaster(self:oddPage() and "right" or "left")
  end, "Set the page layout")

  -- Override inherited plain class commands with style-aware variants

  self:registerCommand('code', function(_, content)
    SILE.call('style:apply', { name = 'code' }, content)
  end, "Style the content as code")
end

return class
