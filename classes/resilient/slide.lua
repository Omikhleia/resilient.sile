--- The re·sil·ient slide document class.
--
-- Following the re·sil·ient styling paradigm.
--
-- @license MIT
-- @copyright (c) 2025 Omikhleia / Didier Willis
-- @module classes.resilient.slide

local layoutParser = require("resilient.layoutparser")

-- FIXME MOVED FROM BOOKMATTERS = MAKE IT UTILS

local Color = require("grail.color")
local getGradient = require("grail.gradient").getGradient

--- Compute a weighted color distance in 3D space.
--
-- @tparam Color color Input color (RGB only for now)
local function weightedColorDistanceIn3D (color)
  -- Source: https://www.nbdtech.com/Blog/archive/2008/04/27/Calculating-the-Perceived-Brightness-of-a-Color.aspx
  return math.sqrt(
    (color.r * 255)^2 * 0.241
    + (color.g * 255)^2 * 0.691
    + (color.b * 255)^2 * 0.068
  )
end

--- Compute the average color around the midpoint of a linear gradient.
--
-- We just pick the 2 or 3 stops around the midpoint, and average their RGB values.
--
-- @tparam string gradname Name of the gradient
-- @treturn Color Average color around the midpoint of the gradient
local function averageLinearGradientMidpointColors (gradname)
  local grad = getGradient(gradname)
  if not grad then
    SU.error("Gradient '" .. gradname .. "' not found for average color computation")
  end
  local mid = math.ceil(#grad.stops / 2)
  local prevstopindex = mid > 1 and (mid - 1) or mid
  local nextstopindex = mid < #grad.stops and mid + 1 or mid
  local r = 0
  local g = 0
  local b = 0
  for k = prevstopindex, nextstopindex do
    local stop = grad.stops[k]
    r = r + stop.r
    g = g + stop.g
    b = b + stop.b
  end
  local n = nextstopindex - prevstopindex + 1
  return { r = r / n, g = g / n, b = b / n } -- no need to cast as a Color object
end

--- Compute the average color around the midpoint of a linear gradient.
--
-- We just pick the 2 or 3 stops around the midpoint, and average their RGB values.
--
-- @tparam string gradname Name of the gradient
-- @treturn Color Average color around the midpoint of the gradient
local function averageLinearGradientMidpointColors (gradname)
  local grad = getGradient(gradname)
  if not grad then
    SU.error("Gradient '" .. gradname .. "' not found for average color computation")
  end
  local mid = math.ceil(#grad.stops / 2)
  local prevstopindex = mid > 1 and (mid - 1) or mid
  local nextstopindex = mid < #grad.stops and mid + 1 or mid
  local r = 0
  local g = 0
  local b = 0
  for k = prevstopindex, nextstopindex do
    local stop = grad.stops[k]
    r = r + stop.r
    g = g + stop.g
    b = b + stop.b
  end
  local n = nextstopindex - prevstopindex + 1
  return { r = r / n, g = g / n, b = b / n } -- no need to cast as a Color object
end

--- Compute the best contrast color (black or white) for a given background color.
--
-- If the background color is a gradient, there is no perfect solution, and we can compute an average color
-- around the midpoint of the gradient.
-- The implicit assumption is that the gradient is reasonably smooth, and that the midpoint is representative
-- of the overall gradient for use with text content.
-- This is certainly not perfect, but it seems to be a reasonable heuristic for most cases.
--
-- @tparam Color color Input color (RGB only for now)
-- @treturn string "black" or "white"
local function contrastColor(color)
  if color.G then
    color = averageLinearGradientMidpointColors(color.G)
  end
  if not color.r then
    -- Not going to bother with other color schemes for now...
    SU.error([[Background color for back cover must be in RGB.
Feel free to propose a PR to the maintainer if you want it otherwise]])
  end
  print("weighted color distance for contrast color computation:", weightedColorDistanceIn3D(color))
  return weightedColorDistanceIn3D(color) < 130 and "white" or "black"
end

SILE.scratch.slide = SILE.scratch.slide or {}
SILE.scratch.slide.headers = {
  novel = true,
  technical = true,
  none = true
}

local DIVISIONNAME = {
  "frontmatter",
  "mainmatter",
  "backmatter"
}

-- HACK Just 'cause we don't want a warning when the frame isn't found.
local getFrame = function (id)
   if type(id) == "table" then
      SU.error("Passed a table, expected a string", true)
   end
   local frame, last_attempt
   while not frame do
      frame = SILE.frames[id]
      id = id:gsub("_$", "")
      if id == last_attempt then
         break
      end
      last_attempt = id
   end
   return frame -- or SU.warn("Couldn't find frame ID " .. id, true)
end

--- The resilient slide class.
--
-- Extends `classes.resilient.base`.
--
-- @type classes.resilient.slide

local base = require("classes.resilient.base")
local class = pl.class(base)
class._name = "resilient.slide"
class.firstContentFrame = "content"
-- class.defaultFrameset = {
--   content = {
--     left = "left(page) + 5%pw",
--     right = "right(page) - 5%pw",
--     top = "top(page) + 15%ph",
--     bottom = "top(footnotes)"
--   },
--   folio = { -- same as footer for now
--     left = "left(page)",
--     right = "right(page)",
--     top = "bottom(page) - 15%ph",
--     bottom = "bottom(page)",
    
--   },
--   footnotes = {
--     left = "left(content)",
--     right = "right(content)",
--     bottom = "bottom(page) - 15%ph",
--     height = "0"
--   }
-- }

class.h2Frameset = {
  content = {
    left = "left(page) + 5%pw",
    right = "right(page) - 5%pw",
    top = "top(page) + 15%ph",
    bottom = "top(footnotes)",
  },
  folio = { -- same as footer for now
    left = "left(page)",
    right = "right(page)",
    bottom = "bottom(page)",
    height = "height(header)"
  },
  header = {
    left = "left(page)",
    right = "right(page)",
    top = "top(page)",
    bottom = "top(content)-5%ph"
  },
  footer = {
    left = "left(page)",
    right = "right(page)",
    bottom = "bottom(page)",
    height = "height(header)"
  },
  footnotes = {
    left = "left(content)",
    right = "right(content)",
    bottom = "bottom(page) - 15%ph",
    height = "0"
  }
}

class.h1Frameset = {
  title = {
    left = "left(page) + 5%pw",
    right = "right(page) - 30%pw",
    top = "top(page) + 20%ph",
    bottom = "top(page) + 50%ph"
  },
  content = {
    left = "left(page) + 10%pw",
    right = "right(page) - 5%pw",
    top = "bottom(title) + 1%ph",
    bottom = "top(footnotes)"
  },
  folio = { -- same as footer for now
    left = "left(page)",
    right = "right(page)",
    bottom = "bottom(page)",
    height = "15%ph"
  },
  footnotes = {
    left = "left(content)",
    right = "right(content)",
    bottom = "bottom(page) - 15%ph",
    height = "0"
  }
}

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

  self:_enableSlideEffects()

  -- Basic low-level packages

  self:loadPackage("struts")

  -- Book-related packages

  self:loadPackage("resilient.tableofcontents")
  self:loadPackage("labelrefs") -- Warning: must be loaded after resilient.tableofcontents
                                -- and before any other packages that would load it too.
  self:loadPackage("resilient.sectioning")
  self:loadPackage("indexer", {
    -- TODO: For now we go for default package options:
    --   ["page-range-format"] = "expanded",
    --   ["page-range-delimiter"] = "–",
    --   ["page-delimiter"] = ", ",
    --   filler = "dotfill"
    -- Eventually we might want to customize them.
    -- Should it be a special style or some other mechanism?
  })

  -- Page-related packages

  self:loadPackage("folio")
  self:loadPackage("masters")
  self:defineMaster({
    id = "slide-h1",
    firstContentFrame = self.firstContentFrame,
    frames = self.h1Frameset
  })
  self:defineMaster({
    id = "slide-h2",
    firstContentFrame = self.firstContentFrame,
    frames = self.h2Frameset
  })

  self:loadPackage("resilient.footnotes", {
    insertInto = "footnotes",
    stealFrom = { "content" }
  })
  self:loadPackage("resilient.headers")

  -- Advanced formating packages

  self:loadPackage("markdown")
  self:loadPackage("djot")
  -- Once Djot is loaded, we can register custom pre-defined symbols
  local mdc = self.packages["markdown.commands"]
  mdc:registerSymbol("_BIBLIOGRAPHY_", true, function (opts)
    if not self.packages.bibtex and not self.packages["dissilient.bibtex"] then
      SU.warn("Bibliography support is not available")
      return {}
    end
    return {
      SU.ast.createCommand("printbibliography", opts)
    }
  end)
  -- Our Djot/Markdown support already provides a _TOC_ symbol.
  -- Here we can also provide _LISTOFFIGURES_, _LISTOFTABLES_, _LISTOFLISTINGS_.
  -- And for the sake of consistency, we can also provide _TABLEOFCONTENTS_.
  -- It is not exactly the same as _TOC_, which does additional things when used
  -- outside resilient, with fallback to to SILE's default implementation, but it
  -- is doesn't hurt to provide it here.
  local extras = { "listoffigures", "listoftables", "listoflistings", "tableofcontents" }
  for _, sym in ipairs(extras) do
    mdc:registerSymbol("_" .. sym:upper() .. "_", true, function (opts)
      return {
        SU.ast.createCommand(sym, opts)
      }
    end)
  end
  mdc:registerSymbol("_FANCYTOC_", true, function (opts)
    return {
      SU.ast.createCommand("use", { module = "packages.resilient.fancytoc" }),
      SU.ast.createCommand("fancytableofcontents", opts),
    }
  end)
  mdc:registerSymbol("_INDEX_", true, function (opts)
    return {
      SU.ast.createCommand("printindex", opts),
    }
  end)

  -- Override document.parindent default to this author's taste
  SILE.settings:set("document.parindent", "1.25em", true)
  -- Override with saner defaults:
  -- Slightly prefer underfull lines over ugly overfull content
  -- I used a more drastic value before, but realize it can have bad effects
  -- too, so for a default value let's be cautious. It's still better then 0
  -- in my opinion for the general usage.
  SILE.settings:set("linebreak.emergencyStretch", "1em", true)
  -- This should never have been 1.2 by default:
  -- https://github.com/sile-typesetter/sile/issues/1371
  -- Fixed in recent versions of SILE, but nothing prevents us to set it here
  -- as well.
  SILE.settings:set("shaper.spaceenlargementfactor", 1, true)

  -- Command override from loaded packages.
  -- TRICKY, TO REMEMBER: Such overrides cannot be done in registerCommands()
  -- as packages are not loaded yet at that time.

  -- Override the standard foliostyle hook to rely on styles
  self:registerCommand("foliostyle", function (_, content)
    local styleName = "folio-odd" 
    local division = self.resilientState.division or 2
    --SILE.call("background", { frame = "footer", allpages = false, color= "omissible 90" }) -- FIXME
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

  -- Override the standard urlstyle hook to rely on styles
  -- N.B. Package "url" is loaded by the markdown package.
  self:registerCommand("urlstyle", function (_, content)
    SILE.call("style:apply", { name = "url" }, content)
  end)

  -- Override the standard math:numberingstyle hook to rely on styles,
  -- and also to subscribe for cross-references.
  -- N.B. Package "math" is loaded by the markdown package.
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

  -- Override the indexer style hooks to rely on styles
  self:registerCommand("index:entry:style", function (opts, content)
    local name = "index-entry-" .. opts.index
    local styleName = self:hasStyle(name) and name or "index-entry-main"
    SILE.call("style:apply", { name = styleName }, content)
  end)
  self:registerCommand("index:pages:style", function (opts, content)
    local name = "index-pages-" .. opts.index
    local styleName = self:hasStyle(name) and name or "index-pages-main"
    SILE.call("style:apply", { name = styleName }, content)
  end)

  -- TRANSITIONAL:
  -- These packages should do it themselves eventually, with a proper interface
  -- to declare commands as contextual.
  -- Here, there's also a strong reason that packages are not "reloaded" (and their
  -- commands reset).
  -- We cancel reloading  in our override superclass, so we are safe.
  SILE.resilient.enforceContextualCommand("footnote")
  SILE.resilient.enforceContextualCommand("label")
  SILE.resilient.enforceContextualCommand("indexentry")
  SILE.resilient.enforceContextChangingCommand("ref", "ref")
  SILE.resilient.enforceContextChangingCommand("indexer", "printindex")

  -- FIXME NOT HERE
  SILE.call("font", { size = "4.5%ph", family = "Lato" })
  SILE.settings:set("document.parindent", nil)
  SILE.settings:set("document.parskip", "0.5ex")
  SILE.settings:set("document.baselineskip", "1.2em")
  SILE.settings:set("document.lineskip", "0")
  SILE.settings:set("lists.parskip", "0.5ex")
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
      if not SILE.scratch.slide.headers[value] then
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
  options.landscape = SU.boolean(options.landscape, true) -- Switch to landscape by default
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
  --self.oddFrameset, self.evenFrameset = layout:frameset()
  self.defaultFrameset = self.h1Frameset -- just to be sure, it will be overridden by the masters anyway
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

  -- quotes
  self:registerStyle("blockquote", {}, {
    font = { size = "0.95em" },
    paragraph = { before = { skip = "smallskip" },
                  margin = { left = "2em", right = "2em" },
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

  -- code
  -- Default is similar to the original plain \code command, and quite as bad, but at
  -- least uses a font-relative size.
  self:registerStyle("code", {}, {
    font = {
      family = "Hack",
      adjust = "ex-height",
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

  -- index styles
  self:registerStyle("index-entry-main", {}, {
  })
  self:registerStyle("index-pages-main", {}, {
    font = { features = "+onum" }
  })
end

--- Output the header content in the specified frame.
--
-- @tparam table headerContent AST content to be processed in the header
-- @tparam[opt] string frame Target frame name (defaults to "header")
function class:_outputHeader (headerContent, frame)
  print("Outputting header content in frame '" .. (frame or "header") .. "'")
  if not frame then frame = "header" end
  local headerFrame = getFrame(frame)
  if headerFrame then
    SILE.typesetNaturally(headerFrame, function ()
--        SILE.typesetter:typeset("frame " .. (self:currentMaster() or "none"))
        print("Current master in header output:", self:currentMaster() or "none", headerContent)
        if headerContent then
        SILE.settings:pushState()
        -- Restore the settings to the top of the queue, which should be the document
        SILE.settings:toplevelState()
        SILE.settings:set("current.parindent", SILE.types.node.glue())
        SILE.settings:set("document.lskip", SILE.types.node.glue())
        SILE.settings:set("document.rskip", SILE.types.node.glue())

        -- Process the header content in a context where fragile commands are ignored.
        SILE.resilient.cancelContextualCommands("header", function ()
          SILE.process(headerContent)
        end)

        SILE.typesetter:leaveHmode()
        SILE.settings:popState()
      end
    end)
  end
end

function class:newPage (content)
  print("--- New page", getFrame("header"), getFrame("footer"))
  local x = base.newPage(self, content)

  print("Current master in newPage:", self:currentMaster() or "none")
  
  
  return x
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
    self:_outputHeader(SILE.scratch.headers.odd)
    self:_outputHeader(SILE.scratch.headers.odd, "title")
  --else
    --self:_outputHeader(SILE.scratch.headers.even)
  --end
  local pdf = require("justenoughlibtexpdf")
  local pageLabels = pdf.lookup_dictionary(pdf.get_dictionary("Catalog"), "PageLabels")
  if not pageLabels then
    SU.debug("omipagelabeltest", "Creating /PageLabels dictionary in Catalog")
    pageLabels = pdf.parse("<< >>")
    pdf.add_dict(pdf.get_dictionary("Catalog"), pdf.parse("/PageLabels"), pageLabels)
    end
  local nums = pdf.lookup_dictionary(pageLabels, "Nums")
  if not nums then
    SU.debug("omipagelabeltest", "Creating /Nums array in /PageLabels")
    nums = pdf.parse("[]")
    pdf.add_dict(pageLabels, pdf.parse("/Nums"), nums)
  end
  local pageLabel = self.packages.counters:formatCounter(SILE.scratch.counters.folio)
  self._pageindex = self._pageindex or 0
  pdf.push_array(nums, pdf.parse(self._pageindex))
  pdf.push_array(nums, pdf.parse(string.format([[<< /P (%s) >>]], pageLabel))) -- DIRTY
  self._pageindex = self._pageindex + 1


  return base.endPage(self)
end

--- (Override) Declare class settings.
--
-- Declares the settings specific to the resilient slide class.
--
function class:declareSettings ()
  base.declareSettings(self)

end

--- (Override) Register class commands.
--
-- Registers the commands specific to the resilient slide class.
--
function class:registerCommands ()
  base.registerCommands(self)
--  SILE.typesetNaturally(SILE.frames[options.frame], function ()
--          SILE.process(content)
--       end)
  -- Running headers

  self:registerCommand("book-title", function (_, content)
    if self.headers == "novel" then
      SILE.call("even-running-header", {}, content)
    end
  end, "Book title low-level command (for running headers depending on headers type)")

  self:registerCommand("odd-tracked-header", function (_, content)
    local headerContent = function ()
      SILE.typesetter:leaveHmode()
      SILE.process({
        SU.ast.createCommand("font", { size= "5%ph" }), -- FIXME THEME
        SU.ast.createCommand("strut", { method = "rule"}),
        SU.ast.createCommand("color", { color = contrastColor(Color("omissiblebronze")) }, -- FIXME THEME
          SU.ast.subContent(content)
        )
      })
    end
    SILE.call("info", {
      category = "headerOdd",
      value = headerContent
    })
  end, "Text to appear on the top of odd pages, tracked via info node.")

  self:registerCommand("odd-running-header", function (_, content)
      SILE.scratch.headers.odd = function ()
        SILE.typesetter:leaveHmode()
        SILE.process({
          SU.ast.createCommand("font", { size= "5%ph" }), -- FIXME THEME
          SU.ast.createCommand("strut", { method = "rule"}),
          SU.ast.createCommand("color", { color = contrastColor(Color("omissiblebronze")) }, -- FIXME THEME
            SU.ast.subContent(content)
          )
        })
    end
  end, "Text to appear on the top odd pages.")


  self:registerCommand("part", function (options, content)
    -- FIXME TODO
    -- if self.resilientState.division and self.resilientState.division ~= 2 then
    --   -- By definition, parts are unnumbered in all divisions except the mainmatter
    --   options.numbering = false
    -- end
    -- options.style = "sectioning-part"
    -- -- Allow appendices again in a new part
    -- self.resilientState.appendix = false
    -- SILE.call("sectioning", options, content)
  end, "Begin a new part.")


  self:registerCommand("chapter", function (options, content)
    SILE.typesetter:registerFrameBreakHook(function (_self, xx)
      print("-----------Frame break:", self:currentMaster() or "none")
      -- print("@@@@@@@@@@@ Frame break hook called", getFrame("header") ~= nil, getFrame("footer") ~= nil)
      if not getFrame("header") and not getFrame("footer") then
        SILE.call("background", { frame = "page", color = "omissiblesapphire", allpages = false }) -- FIXME
      end
      return xx
      end)
    SILE.typesetter:registerNewFrameHook(function ()
        print("-----------New frame:", self:currentMaster() or "none")
        print("@@@@@@@@@@@ New frame hook called", getFrame("header") ~= nil, getFrame("footer") ~= nil)
        if not getFrame("header") and not getFrame("footer") then
          --SILE.call("background", { frame = "page", color = "omissiblebronze", allpages = false }) -- FIXME
        end
        end)
        SILE.typesetter:registerPageEndHook(function ()
        print("Current master in page end ts hook:", self:currentMaster() or "none")
        if getFrame("header") then
        SILE.call("background", { frame = "header", allpages = false, color= "omissiblebronze" }) -- FIXME
        end
        if getFrame("footer") then
         SILE.call("background", { frame = "footer", allpages = false, color= "omissible" }) -- FIXME
        end
        if not getFrame("header") and not getFrame("footer") then
          --SILE.call("background", { frame = "page", color = "omissiblebronze", allpages = false }) -- FIXME
        end
        end)
    SILE.typesetter:leaveHmode()
    SILE.call("goodbreak")
    SILE.call("open-on-any-page")
    self:switchMaster("slide-h1")
    
    --SILE.call("odd-tracked-header", {}, content)
    SILE.call("odd-running-header", {}, content)
    SILE.typesetNaturally(SILE.getFrame("title"), function ()
      SILE.process(content)
    end)
  end, "Begin a new chapter.")

  self:registerCommand("section", function (options, content)
    SILE.typesetter:leaveHmode()
    SILE.call("goodbreak")  
    SILE.call("open-on-any-page")
    self:switchMaster("slide-h2")

    --SILE.call("odd-tracked-header", {}, {
    SILE.call("odd-running-header", {}, {
      SU.ast.createCommand("center", {}, SU.ast.subContent(content))
    })
    SILE.typesetter:leaveHmode()
  end, "Begin a new section.")

  self:registerCommand("subsection", function (options, content)
    -- FIXME TODO
    -- options.style = "sectioning-subsection"
    -- SILE.call("sectioning", options, content)
  end, "Begin a new subsection.")

  self:registerCommand("subsubsection", function (options, content)
    -- FIXME TODO
    -- options.style = "sectioning-subsubsection"
    -- SILE.call("sectioning", options, content)
  end, "Begin a new subsubsection.")

  -- Quotes

  self:registerCommand("blockquote", function (options, content)
    local variant = options.variant and "blockquote-" .. options.variant or nil
    local style = variant and self.styles:hasStyle(variant) and variant or "blockquote"
    SILE.call("style:apply:paragraph", { name = style }, content)
  end, "Typeset its contents in a styled blockquote.")

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

  self:registerCommand('code', function(_, content)
    SILE.call('style:apply', { name = 'code' }, content)
  end, "Style the content as code")
end

--- (Private) Enable slide presentation effects.
--
-- Set fullscreen mode by default, and add a fade-in transition to each page.
--
function class:_enableSlideEffects ()
  if SILE.outputter._name ~= "libtexpdf" then
    SU.warn("Slide effects are only supported with the libtexpdf PDF outputter")
    return
  end
  local pdf = require("justenoughlibtexpdf")

  -- Set the PDF to open in fullscreen mode by default.
  SILE.outputter:registerHook("prefinish", function ()
    local catalog = pdf.get_dictionary("Catalog")
    pdf.add_dict(catalog, pdf.parse("/PageMode"), pdf.parse("/FullScreen"))
  end)

  -- Add a fade-in transition to each page.
  self:registerHook("newpage", function ()
    local page = pdf.get_dictionary("@THISPAGE")
    local fadeInDict = pdf.parse("<< /S /Fade /D 0.5 >>")
    pdf.add_dict(page, pdf.parse("/Trans"), fadeInDict)
  end)
end

return class
