--- The re·sil·ient book document class.
--
-- Following the re·sil·ient styling paradigm, and providing way more features
-- then SILE's default "book" class.
--
-- @license MIT
-- @copyright (c) 2021-2026 Omikhleia / Didier Willis
-- @module classes.resilient.book

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

--- The resilient book class.
--
-- Extends `classes.resilient.base`.
--
-- @type classes.resilient.book

local base = require("classes.resilient.base")
local class = pl.class(base)
class._name = "resilient.book"
class.firstContentFrame = "content" -- We'll define framesets later
                                    -- but this remains true.

--- (Constructor) Initialize the book class.
--
-- Besides initializing the parent class and loading all needed packages,
-- it also sets some sane defaults for certain settings,
-- overrides some commands from standard SILE packages to make them
-- style-aware, registers some Djot pre-defined symbols, etc.
--
-- @tparam table options Class options
function class:_init (options)
  base._init(self, options)
  self.resilientState = {}

  -- Basic low-level packages used in this class

  self:loadPackage("struts")

  -- Document-related packages

  self:loadPackage("resilient.document")

  -- Page-related packages

  self:loadPackage("folio")
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
  self:loadPackage("resilient.footnotes", {
    insertInto = "footnotes",
    stealFrom = { "content" }
  })
  self:loadPackage("resilient.headers")

  -- Command override from loaded packages.
  -- TRICKY, TO REMEMBER: Such overrides cannot be done in registerCommands()
  -- as packages are not loaded yet at that time.

  -- Override the standard foliostyle hook to rely on styles
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
      SU.ast.createCommand("strut", { method = "rule"}),
      SU.ast.createCommand("style:apply:number", {
        name = "folio-" .. DIVISIONNAME[division],
        text = SU.ast.contentToString(content),
      })
    })
  end)

  -- TRANSITIONAL:
  -- These packages should do it themselves eventually, with a proper interface
  -- to declare commands as contextual.
  -- Here, there's also a strong reason that packages are not "reloaded" (and their
  -- commands reset).
  -- We cancel reloading  in our override superclass, so we are safe.
  SILE.resilient.enforceContextualCommand("footnote")
end

--- (Override) Declare class options.
--
-- The options specific to the resilient book class are:
--
--  - layout: page layout
--  - offset: binding offset
--  - headers: type of headers (novel, technical, none)
--
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

--- (Override) Set class options.
--
-- Sets the default options (layout to "division", no binding offset, and "technical" headers).
-- All other options are processed by the base class.
--
-- The framesets are then defined according to the layout and offset.
--
-- @tparam table options Class options
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

--- (Override) Register class styles.
--
-- Registers the styles specific to the resilient book class.
--
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
                    pagestyle = {
                      open = "odd"
                    },
                    settings = {
                      toclevel = 0,
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
                    pagestyle = {
                      open = "odd",
                    },
                    settings = {
                      toclevel = 1,
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
  self:registerStyle("figure-caption-legend", { inherit = "figure-caption" }, {
    -- Caption when there's also a legend:
    -- Kill the skip, but forbid the break, to keep the caption and legend together.
    paragraph = { after = { skip = "0", vbreak = false } }
  })
  self:registerStyle("figure-legend", {}, {
    font = { size = "0.95em" },
    paragraph = { before = { indent = false, vbreak = false },
                  align = "center",
                  after = { skip = "medskip" } },
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
  self:registerStyle("table-caption-legend", { inherit = "table-caption" }, {
    -- Caption when there's also a legend:
    -- Kill the skip, but forbid the break, to keep the caption and legend together.
    paragraph = { after = { skip = "0", vbreak = false } }
  })
  self:registerStyle("table-legend", {}, {
    font = { size = "0.95em" },
    paragraph = { before = { indent = false, vbreak = false },
                  align = "center",
                  after = { skip = "medskip" } },
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
  self:registerStyle("listing-caption-legend", { inherit = "listing-caption" }, {
    -- Caption when there's also a legend:
    -- Kill the skip, but forbid the break, to keep the caption and legend together.
    paragraph = { after = { skip = "0", vbreak = false } }
  })
  self:registerStyle("listing-legend", {}, {
    font = { size = "0.95em" },
    paragraph = { before = { indent = false, vbreak = false },
                  align = "center",
                  after = { skip = "medskip" } },
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

end

--- (Override) End-of-page custom hook.
--
-- Outputs the running header according to the page type (odd or even).
--
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

--- (Override) Declare class settings.
--
-- Declares the settings specific to the resilient book class.
--
function class:declareSettings ()
  base.declareSettings(self)

end

--- (Override) Register class commands.
--
-- Registers the commands specific to the resilient book class.
--
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
        SU.ast.createCommand("strut", { method = "rule"}),
        SU.ast.subContent(content)
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
        SU.ast.createCommand("strut", { method = "rule"}),
        SU.ast.subContent(content)
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
        SU.ast.createCommand("strut", { method = "rule"}),
        SU.ast.subContent(content)
      })
    end
  end, "Text to appear on the top of even pages.")

  self:registerCommand("odd-running-header", function (_, content)
    SILE.scratch.headers.odd = function ()
      SILE.call("style:apply:paragraph", { name = "header-odd" }, {
        SU.ast.createCommand("strut", { method = "rule"}),
        SU.ast.subContent(content)
      })
    end
  end, "Text to appear on the top odd pages.")

  -- front/main/back matter

  self:registerCommand("internal:division", function (options, _)
    local division = SU.required(options, "division", "internal:division")
    -- Always start on an odd page, so as to be consistent with the folio numbering
    -- in case it is reset.
    SILE.call("open-on-odd-page")
    local previous = self.resilientState.division
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
      -- Normally, pages preceding the first division should not have a folio
      -- (e.g. cover, title page, etc.) but count in the numbering.
      -- So in that case, we do not reset the counter, but just change the
      -- numbering display.
      -- That will work with resilient master documents, and we aren't going
      -- to do anything smarter for users not using a master document, but
      -- having a few numbered pages before the first division...
      SILE.call("set-counter", { id = "folio", display = display, value = previous and 1 or nil })
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

  -- Captioned elements
  -- N.B. Despite the similar naming to LaTeX, these are not "floats"

  self:registerCommand("captioned-figure", function (options, content)
    if type(content) ~= "table" then SU.error("Expected a table content in figure environment") end
    local caption = SU.ast.removeFromTree(content, "caption")
    local legend = SU.ast.removeFromTree(content, "legend")

    SILE.call("style:apply:paragraph", { name = "figure" }, content)
    if caption and legend then
      options.style = "figure-caption-legend"
      SILE.call("sectioning", options, caption)
      if legend then
        SILE.call("style:apply:paragraph", { name = "figure-legend" }, legend)
      end
    elseif caption then
      options.style = "figure-caption"
      SILE.call("sectioning", options, caption)
    else
      -- It's bad to use the figure environment without caption, it's here for that.
      -- So I am not even going to use styles here.
      SILE.call("smallskip")
    end
  end, "Insert a captioned figure.")

  self:registerCommand("captioned-table", function (options, content)
    if type(content) ~= "table" then SU.error("Expected a table content in table environment") end
    local caption = SU.ast.removeFromTree(content, "caption")
    local legend = SU.ast.removeFromTree(content, "legend")

    SILE.call("style:apply:paragraph", { name = "table" }, content)
    if caption and legend then
      options.style = "table-caption-legend"
      SILE.call("sectioning", options, caption)
      if legend then
        SILE.call("style:apply:paragraph", { name = "table-legend" }, legend)
      end
    elseif caption then
      options.style = "table-caption"
      SILE.call("sectioning", options, caption)
    else
      -- It's bad to use the table environment without caption, it's here for that.
      -- So I am not even going to use styles here.
      SILE.call("smallskip")
    end
  end, "Insert a captioned table.")

  self:registerCommand("captioned-listing", function (options, content)
    if type(content) ~= "table" then SU.error("Expected a table content in listing environment") end
    local caption = SU.ast.removeFromTree(content, "caption")
    local legend = SU.ast.removeFromTree(content, "legend")

    SILE.call("style:apply:paragraph", { name = "listing" }, content)
    if caption and legend then
      options.style = "listing-caption-legend"
      SILE.call("sectioning", options, caption)
      if legend then
        SILE.call("style:apply:paragraph", { name = "listing-legend" }, legend)
      end
    elseif caption then
      options.style = "listing-caption"
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

end

return class
