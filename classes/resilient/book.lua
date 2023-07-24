--
-- A new advanced book class for SILE
-- 2021-2023, Didier Willis
-- License: MIT
--
local base = require("classes.resilient.base")
local class = pl.class(base)
class._name = "resilient.book"

local utils = require("resilient.utils")
local layoutParser = require("resilient.layoutparser")

-- CLASS DEFINITION

function class:_init (options)
  base._init(self, options)

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
    SILE.call("style:apply:paragraph", { name = styleName }, function ()
      -- Ensure proper baseline alignment with a strut rule.
      -- The baseline placement depends on the line output algorithm, and we cannot
      -- trust it if it just uses the line ascenders.
      -- Typically, if folios use "old-style" numbers, 16 and 17 facing pages shall have
      -- aligned folios, but the 1 is smaller than the 6 and 7, the former ascends above,
      -- and the latter descends below the baseline).
      SILE.call("strut", { method = "rule"})
      SILE.process(content)
    end)
  end)

  -- Override the standard urlstyle hook to rely on styles
  -- Package "url" is loaded by the markdown package.
  self:registerCommand("urlstyle", function (_, content)
    SILE.call("style:apply", { name = "url" }, content)
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
end

function class:setOptions (options)
  options = options or {}
  options.layout = options.layout or "division"
  base.setOptions(self, options) -- so that papersize etc. get processed...

  local layout = layoutParser:match(options.layout)
  if not layout then
    SU.warn("Unknown page layout '".. options.layout .. "', switching to division")
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

  -- Sectioning styles
  self:registerStyle("sectioning-base", {}, {
    paragraph = { before = { indent = false },
                  after = { indent = false } }
  })
  self:registerStyle("sectioning-part", { inherit = "sectioning-base" }, {
    font = { weight = 800, size = "1.6em" },
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
    font = { weight = 800, size = "1.4em" },
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
    font = { weight = 800, size = "1.2em" },
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
    font = { weight = 800, size = "1.1em" },
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
    font = { weight = 800 },
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

  -- url style
  -- Default is similar to the plain \code command, and quite as bad, but at
  -- least uses a font-relative size.
  self:registerStyle("url", {}, {
    font = { family = "Hack", size = "1.4ex" }
  })
end

function class:endPage ()
  local headerContent = (self:oddPage() and SILE.scratch.headers.odd)
        or (not(self:oddPage()) and SILE.scratch.headers.even)
  if headerContent then
    self.packages["resilient.headers"]:outputHeader(headerContent)
  end
  return base.endPage(self)
end

function class:declareSettings ()
  base.declareSettings(self)

  SILE.settings:declare({
    parameter = "book.blockquote.margin",
    type = "measurement",
    default = SILE.measurement("2em"),
    help = "Left margin (indentation) for enumerations"
  })
end

function class:runningHeaderSectionReference (options, content)
  if SU.boolean(options.numbering, true) then
    local sty = self:resolveStyle(options.style)
    local numsty = sty.sectioning and sty.sectioning.numberstyle
      and sty.sectioning.numberstyle.header
    if numsty and sty.sectioning.counter.id then
      local number = self.packages.counters:formatMultilevelCounter(
        self:getMultilevelCounter(sty.sectioning.counter.id), {
          noleadingzeros = true,
          level = sty.sectioning.counter.level -- up to the sectioning level
        }
      )
      SILE.call("style:apply:number", { name = numsty, text = number })
    end
  end
  SILE.process(content)
end

function class:registerCommands ()
  base.registerCommands(self)

  -- Running headers

  self:registerCommand("even-running-header", function (_, content)
    local closure = SILE.settings:wrap()
    SILE.scratch.headers.even = function ()
      closure(function ()
        SILE.call("style:apply:paragraph", { name = "header-even" }, function ()
          SILE.call("strut", { method = "rule"})
          SILE.process(content)
        end)
      end)
    end
  end, "Text to appear on the top of the even page(s).")

  self:registerCommand("odd-running-header", function (_, content)
    local closure = SILE.settings:wrap()
    SILE.scratch.headers.odd = function ()
      closure(function ()
        SILE.call("style:apply:paragraph", { name = "header-odd" }, function ()
          SILE.call("strut", { method = "rule"})
          SILE.process(content)
        end)
      end)
    end
  end, "Text to appear on the top of the odd page(s).")

  -- Sectioning hooks and commands

  self:registerCommand("sectioning:part:hook", function (_, _)
    -- Parts cancel headers and folios
    SILE.call("noheaderthispage")
    SILE.call("nofoliothispage")
    SILE.scratch.headers.odd = nil
    SILE.scratch.headers.even = nil

    -- Parts reset footnotes and chapters
    SILE.call("set-counter", { id = "footnote", value = 1 })
    SILE.call("set-multilevel-counter", { id = "sections", level = 1, value = 0 })
  end, "Apply part hooks (counter resets, footers and headers, etc.)")

  self:registerCommand("sectioning:chapter:hook", function (options, content)
    -- Chapters re-enable folios, have no header, and reset the footnote counter.
    SILE.call("noheaderthispage")
    SILE.call("folios")
    SILE.call("set-counter", { id = "footnote", value = 1 })

    -- Chapters, here, go in the even header.
    SILE.call("even-running-header", {}, function ()
      self:runningHeaderSectionReference(options, content)
    end)
  end, "Apply chapter hooks (counter resets, footers and headers, etc.)")

  self:registerCommand("sectioning:section:hook", function (options, content)
    -- Sections, here, go in the odd header.
    SILE.call("odd-running-header", {}, function ()
      self:runningHeaderSectionReference(options, content)
    end)
  end, "Applies section hooks (footers and headers, etc.)")

  self:registerCommand("part", function (options, content)
    options.style = "sectioning-part"
    SILE.call("sectioning", options, content)
  end, "Begin a new part.")

  self:registerCommand("chapter", function (options, content)
    options.style = "sectioning-chapter"
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
      local lskip = SILE.settings:get("document.lskip") or SILE.nodefactory.glue()
      local rskip = SILE.settings:get("document.rskip") or SILE.nodefactory.glue()
      SILE.settings:set("document.lskip", SILE.nodefactory.glue(lskip.width + indent))
      SILE.settings:set("document.rskip", SILE.nodefactory.glue(rskip.width + indent))
      SILE.process(content)
      SILE.call("par")
    end)
  end, "Typeset its contents in a right and left indented block.")

  self:registerCommand("quoteindent", function (_, content)
    SILE.settings:temporarily(function ()
      local indent = SILE.settings:get("book.blockquote.margin"):absolute() * 0.875
      local lskip = SILE.settings:get("document.lskip") or SILE.nodefactory.glue()
      local rskip = SILE.settings:get("document.rskip") or SILE.nodefactory.glue()
      SILE.settings:set("document.lskip", SILE.nodefactory.glue(lskip.width + indent))
      SILE.settings:set("document.rskip", SILE.nodefactory.glue(rskip.width + indent * 0.5))
      SILE.process(content)
      SILE.call("par")
    end)
  end, "Typeset its contents in a right and left indented block (variant).")

  self:registerCommand("blockquote", function (_, content)
    SILE.call("style:apply:paragraph", { name = "blockquote" }, content)
  end, "Typeset its contents in a styled blockquote.")

  -- Captioned elements
  -- N.B. Despite the similar naming to LaTeX, these are not "floats"

  self:registerCommand("captioned-figure", function (options, content)
    if type(content) ~= "table" then SU.error("Expected a table content in figure environment") end
    local caption = utils.extractFromTree(content, "caption")

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
    local caption = utils.extractFromTree(content, "caption")

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

  self:registerCommand("table", function (options, content)
    SILE.call("captioned-table", options, content)
  end, "Alias to captioned-table.")

  self:registerCommand("figure", function (options, content)
    SILE.call("captioned-figure", options, content)
  end, "Alias to captioned-figure.")

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

    SILE.call("supereject")
    SILE.typesetter:leaveHmode()

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
