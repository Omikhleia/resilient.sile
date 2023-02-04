--
-- A new book class for SILE
-- 2021, 2022, Didier Willis
-- License: MIT
--
local plain = require("classes.resilient.base")
local class = pl.class(plain)
class._name = "resilient.book"

-- PAGE LAYOUT MASTERS

local layouts = {
  -- Cannonical layout
  canonical = function ()
    local canonicalLayout = require("classes.resilient.layouts.canonical")
    -- FIXME
    -- https://github.com/sile-typesetter/sile/pull/1470 would define pageSize, maybe to
    -- revisit at some point.
    -- Also, passing the page dimensions is kind of a hack, see the function.
    return canonicalLayout(SILE.documentState.paperSize[1], SILE.documentState.paperSize[2])
  end,
  -- Layout by division method
  honnecourt = function ()
    local divisionLayout = require("classes.resilient.layouts.division")
    return divisionLayout(9, 2)
  end,
  vencentinus = function ()
    local divisionLayout = require("classes.resilient.layouts.division")
    return divisionLayout(6, 2)
  end,
  division = function ()
    local divisionLayout = require("classes.resilient.layouts.division")
    return divisionLayout(9)
  end,
  ['division:6'] = function ()
    local divisionLayout = require("classes.resilient.layouts.division")
    return divisionLayout(6)
  end,
  ['division:9'] = function ()
    local divisionLayout = require("classes.resilient.layouts.division")
    return divisionLayout(9)
  end,
  ['division:12'] = function ()
    local divisionLayout = require("classes.resilient.layouts.division")
    return divisionLayout(12)
  end,
  -- Legacy (Omikhleia)
  legacy = function ()
    return {
      content = {
        left = "10%pw", -- was 8.3%pw
        right = "87.7%pw", -- was 86%pw
        top = "11.6%ph",
        bottom = "top(footnotes)"
      },
      folio = {
        left = "left(content)",
        right = "right(content)",
        top = "bottom(footnotes)+3%ph",
        bottom = "bottom(footnotes)+5%ph"
      },
      header = {
        left = "left(content)",
        right = "right(content)",
        top = "top(content)-5%ph", -- was -8%ph
        bottom = "top(content)-2%ph" -- was -3%ph
      },
      footnotes = {
        left = "left(content)",
        right = "right(content)",
        height = "0",
        bottom = "86.3%ph" -- was 83.3%ph
      }
    }
  end,
}

for m, n in pairs({ ateliers = 1/4, demiluxe = 1/3, deluxe = 3/8 }) do
  layouts[m] = function ()
    local frLayout = require("classes.resilient.layouts.frenchcanon")
    return frLayout(n, 1)
  end
  for r = 1, 4 do
    layouts[m..":"..r] = function ()
      local frLayout = require("classes.resilient.layouts.frenchcanon")
      return frLayout(n, r)
    end
  end
end

-- CLASS DEFINITION

function class:_init (options)
  plain._init(self, options)

  self:loadPackage("resilient.sectioning")
  self:loadPackage("masters")
  self:defineMaster({
      id = "right",
      firstContentFrame = self.firstContentFrame,
      frames = self.defaultFrameset
    })
  self:loadPackage("twoside", { oddPageMaster = "right", evenPageMaster = "left" })
  self:mirrorMaster("right", "left")
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

  -- override document.parindent default
  SILE.settings:set("document.parindent", "1.25em")

  -- override the standard foliostyle hook to rely on styles
  -- TRICKY, TO REMEMBER: Such overrides cannot be done in registerCommands()
  self:registerCommand("foliostyle", function (_, content)
    SILE.call("noindent")
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
end

function class:declareOptions ()
  plain.declareOptions(self)

  self:declareOption("layout", function(_, value)
    if value then
      self.layout = value
    end
    return self.layout
  end)
end

function class:setOptions (options)
  options = options or {}
  options.layout = options.layout or "legacy"
  plain:setOptions(options) -- so that papersize etc. get processed...

  local layout = layouts[options.layout or "legacy"]
  if not layout then
    SU.warn("Unknown page layout '".. options.layout .. "', switching to legacy")
    layout = layout.legacy
  end
  -- TRICKY, TO REMEMBER:
  -- the default frameset has to be set before the completion of
  -- the base (plain) class init, or it isn't applied on the first
  -- page...
  self.defaultFrameset = layout(options)
end

function class:registerStyles ()
  -- Sectioning styles
  self:registerStyle("sectioning-base", {}, {
    paragraph = { indentbefore = false, indentafter = false }
  })
  self:registerStyle("sectioning-part", { inherit = "sectioning-base" }, {
    font = { weight = 800, size = "+6" },
    paragraph = { skipbefore = "15%fh", align = "center", skipafter = "bigskip" },
    sectioning = { counter = "parts", level = 1, display = "ROMAN",
                  toclevel = 0,
                  open = "odd", numberstyle="sectioning-part-number",
                  hook = "sectioning:part:hook" },
  })
  self:registerStyle("sectioning-chapter", { inherit = "sectioning-base" }, {
    font = { weight = 800, size = "+4" },
    paragraph = { skipafter = "bigskip", align = "left" },
    sectioning = { counter = "sections", level = 1, display = "arabic",
                  toclevel = 1,
                  open = "odd", numberstyle="sectioning-chapter-number",
                  hook = "sectioning:chapter:hook" },
  })
  self:registerStyle("sectioning-section", { inherit = "sectioning-base" }, {
    font = { weight = 800, size = "+2" },
    paragraph = { skipbefore = "bigskip", skipafter = "medskip", breakafter = false },
    sectioning = { counter = "sections", level = 2, display = "arabic",
                  toclevel = 2,
                  numberstyle="sectioning-other-number",
                  hook = "sectioning:section:hook" },
  })
  self:registerStyle("sectioning-subsection", { inherit = "sectioning-base"}, {
    font = { weight = 800, size = "+1" },
    paragraph = { skipbefore = "medskip", skipafter = "smallskip", breakafter = false },
    sectioning = { counter = "sections", level = 3, display = "arabic",
                  toclevel = 3,
                  numberstyle="sectioning-other-number" },
  })
  self:registerStyle("sectioning-subsubsection", { inherit = "sectioning-base" }, {
    font = { weight = 800 },
    paragraph = { skipbefore = "smallskip", breakafter = false },
    sectioning = { counter = "sections", level = 4, display = "arabic",
                  toclevel = 4,
                  numberstyle="sectioning-other-number" },
  })

  self:registerStyle("sectioning-part-number", {}, {
    font = { features = "+smcp" },
    numbering = { before = "Part ", standalone = true },
  })
  self:registerStyle("sectioning-chapter-number", {}, {
    font = { size = "-1" },
    numbering = { before = "Chapter ", after = ".", standalone = true },
  })
  self:registerStyle("sectioning-other-number", {}, {
    numbering = { after = "." }
  })

  -- folio styles
  self:registerStyle("folio-base", {}, {
    font = { size = "-0.5" }
  })
  self:registerStyle("folio-even", { inherit = "folio-base" }, {
  })
  self:registerStyle("folio-odd", { inherit = "folio-base" }, {
    paragraph = { align = "right" }
  })

  -- header styles
  self:registerStyle("header-base", {}, {
    font = { size = "-1" },
    paragraph = { indentbefore = false, indentafter = false }
  })
  self:registerStyle("header-even", { inherit = "header-base" }, {
  })
  self:registerStyle("header-odd", { inherit = "header-base" }, {
    font = { style = "italic" },
    paragraph = { align = "right" }
  })

  -- quotes
  SILE.scratch.styles.alignments["block"] = "blockindent"

  self:registerStyle("blockquote", {}, {
    font = { size = "-0.5" },
    paragraph = { skipbefore = "smallskip", skipafter = "smallskip",
                  align = "block" }
  })

  -- captioned elements
  self:registerStyle("figure", {}, {
    paragraph = { skipbefore = "smallskip",
                  align = "center", breakafter = false },
  })
  self:registerStyle("figure-caption", { inherit = "sectioning-base" }, {
    font = { size = "-0.5" },
    paragraph = { indentbefore = false, skipbefore = "medskip", breakbefore = false,
                  align = "center",
                  skipafter = "medskip" },
    sectioning = { counter = "figures", level = 1, display = "arabic",
                   toclevel = 5, bookmark = false,
                   goodbreak = false, numberstyle="figure-caption-number" },
  })
  self:registerStyle("figure-caption-number", {}, {
    numbering = { before = "Figure ", after = "." },
    font = { features = "+smcp" },
  })
  self:registerStyle("table", {}, {
    paragraph = { align = "center", breakafter = false },
  })
  self:registerStyle("table-caption", {}, {
    font = { size = "-0.5" },
    paragraph = { indentbefore = false, breakbefore = false,
                  align = "center",
                  skipafter = "medskip" },
    sectioning = { counter = "table", level = 1, display = "arabic",
                   toclevel = 6, bookmark = false,
                   goodbreak = false, numberstyle="table-caption-number" },
  })
  self:registerStyle("table-caption-number", {}, {
    numbering = { before = "Table ", after = "." },
    font = { features = "+smcp" },
  })
end

function class:endPage ()
  local headerContent = (self:oddPage() and SILE.scratch.headers.odd)
        or (not(self:oddPage()) and SILE.scratch.headers.even)
  if headerContent then
    self.packages["resilient.headers"]:outputHeader(headerContent)
  end
  return plain:endPage()
end

function class.declareSettings (_)
  plain:declareSettings()

  SILE.settings:declare({
    parameter = "book.blockquote.margin",
    type = "measurement",
    default = SILE.measurement("2em"),
    help = "Left margin (indentation) for enumerations"
  })
end

function class:registerCommands ()
  plain:registerCommands()

  -- Running headers

  self:registerCommand("even-running-header", function (_, content)
    local closure = SILE.settings:wrap()
    SILE.scratch.headers.even = function ()
      closure(function ()
        SILE.call("style:apply:paragraph", { name = "header-even" }, content)
      end)
    end
  end, "Text to appear on the top of the even page(s).")

  self:registerCommand("odd-running-header", function (_, content)
    local closure = SILE.settings:wrap()
    SILE.scratch.headers.odd = function ()
      closure(function ()
        SILE.call("style:apply:paragraph", { name = "header-odd" }, content)
      end)
    end
  end, "Text to appear on the top of the odd page(s).")

  -- Sectionning hooks and commands

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

  self:registerCommand("sectioning:chapter:hook", function (_, content)
    -- Chapters re-enable folios, have no header, and reset the footnote counter.
    SILE.call("noheaderthispage")
    SILE.call("folios")
    SILE.call("set-counter", { id = "footnote", value = 1 })

    -- Chapters, here, go in the even header.
    SILE.call("even-running-header", {}, content)
  end, "Apply chapter hooks (counter resets, footers and headers, etc.)")

  self:registerCommand("sectioning:section:hook", function (options, content)
    -- Sections, here, go in the odd header.
    SILE.call("odd-running-header", {}, function ()
      if SU.boolean(options.numbering, true) then
        SILE.call("show-multilevel-counter", {
          id = options.counter,
          level = options.level,
          noleadingzeros = true
        })
        SILE.typesetter:typeset(" ")
      end
      SILE.process(content)
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

  self:registerCommand("blockquote", function (_, content)
    SILE.call("style:apply:paragraph", { name = "blockquote" }, content)
  end, "Typeset its contents in a styled blockquote.")

  -- Captioned elements
  -- N.B. Despite the similar naming to LaTeX, these are not "floats"

  local extractFromTree = function (tree, command)
    for i=1, #tree do
      if type(tree[i]) == "table" and tree[i].command == command then
        return table.remove(tree, i)
      end
    end
  end

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

  self:registerCommand("table", function (options, content)
    SILE.call("captioned-table", options, content)
  end, "Alias to captioned-table.")

  self:registerCommand("figure", function (options, content)
    SILE.call("captioned-figure", options, content)
  end, "Alias to captioned-figure.")

  self:registerCommand("listoffigures", function (_, _)
    local figSty = self.styles:resolveStyle("figure-caption")
    local start = figSty.sectioning and figSty.sectioning.toclevel
      or SU.error("Figure style does not specify a TOC level sectioning")

    SILE.call("tableofcontents", { start = start, depth = 0 })
  end, "Output the list of figures.")

  self:registerCommand("listoftables", function (_, _)
    local figSty = self.styles:resolveStyle("table-caption")
    local start = figSty.sectioning and figSty.sectioning.toclevel
      or SU.error("Figure style does not specify a TOC level sectioning")

    SILE.call("tableofcontents", { start = start, depth = 0 })
  end, "Output the list of tables.")
end

return class
