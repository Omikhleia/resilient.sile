--
-- A new advanced book class for SILE
-- 2021-2023, Didier Willis
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

  -- Override the standard foliostyle hook to rely on styles
  -- TRICKY, TO REMEMBER: Such overrides cannot be done in registerCommands()
  -- as packages are not loaded yet.
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
  })
  self:registerStyle("folio-odd", { inherit = "folio-base" }, {
    paragraph = { align = "right" }
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

  self:registerStyle("blockquote", {}, {
    font = { size = "0.95em" },
    paragraph = { before = { skip = "smallskip" },
                  align = "block",
                  after = { skip = "smallskip" } }
  })

  -- captioned elements
  self:registerStyle("figure", {}, {
    paragraph = { before = { skip = "smallskip" },
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
        local sty = self:resolveStyle("sectioning-section")
        local numsty = sty.sectioning and sty.sectioning.numberstyle
          and sty.sectioning.numberstyle.header
        if numsty and sty.sectioning.counter.id then
          local number = self.packages.counters:formatMultilevelCounter(
            self:getMultilevelCounter(sty.sectioning.counter.id), { noleadingzeros = true }
          )
          SILE.call("style:apply:number", { name = numsty, text = number })
        end
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
end

return class
