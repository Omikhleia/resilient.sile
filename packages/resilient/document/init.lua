--- A document package for re·sil·ient.
--
-- It provides general-purpose commands and styles for document content, such as block quotes, drop caps, etc.
--
-- This package is meant to be loaded by more advanced document classes, such as `resilient.book` or `resilient.presentation`.
-- It abstracts common features that are not specific to a particular document type, but are still useful for most documents.
--
-- @license MIT
-- @copyright (c) 2026 Omikhleia / Didier Willis
-- @module packages.resilient.document

--- The "resilient.document" package.
--
-- Extends `packages.resilient.base`.
--
-- @type packages.resilient.document

local base = require("packages.resilient.base")
local package = pl.class(base)
package._name = "resilient.document"

--- (Constructor) Initialize the package.
-- @tparam table options Package options
function package:_init (options)
  base._init(self, options)

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
  
  self:loadPackage("counters")

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

  self:loadPackage("markdown")
  self:loadPackage("djot")
  -- Once Djot is loaded, we can register custom pre-defined symbols
  local mdc = self.class.packages["markdown.commands"]
  mdc:registerSymbol("_BIBLIOGRAPHY_", true, function (opts)
    -- Package dissilient.bibtex is loaded by the markdown package
    return {
      SU.ast.createCommand("printbibliography", opts)
    }
  end)
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

  -- Command override from loaded "standard" packages, to make them style-aware.
  -- TRICKY, TO REMEMBER: Such overrides cannot be done in registerCommands()
  -- as packages are not loaded yet at that time.

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
      text = self.class.packages.counters:formatCounter(SILE.scratch.counters[opts.counter])
    elseif opts.number then
      text = opts.number
    else
      SU.error("No counter or number provided for math numbering")
    end
    -- Cross-ref support (from markdown, we can get an id, in most of our packages,
    -- we can get a marker, play fair with all)
    local mark = opts.id or opts.marker
    if mark then
      local labelRefs = self.class.packages.labelrefs
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
  SILE.resilient.enforceContextualCommand("indexentry")
  SILE.resilient.enforceContextChangingCommand("indexer", "printindex")
  SILE.resilient.enforceContextualCommand("label")
  SILE.resilient.enforceContextChangingCommand("ref", "ref")
end

--- (Override) Register all styles provided by this package.
function package:registerStyles ()

  -- block quotes
  self:registerStyle("blockquote", {}, {
    font = { size = "0.95em" },
    paragraph = { before = { skip = "smallskip" },
                  margin = { left = "2em", right = "2em" },
                  after = { skip = "smallskip" } }
  })

  -- code
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

--- (Override) Register all commands provided by this package.
function package:registerCommands ()
  base.registerCommands(self)

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

  -- Special dropcaps (provided as convenience)
  -- Also useful as pseudo custom style in Markdown or Djot.

  self:registerCommand("resilient:internal:dropcap", function (options, content)
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
  end, "Style-aware initial capital letter (normally an internal command)")

  self:registerCommand("initial-joined", function (options, content)
    SILE.call("resilient:internal:dropcap", { style = options.style, join = true }, content)
  end, "Style-aware initial capital letter, joined to the following text.")

  self:registerCommand("initial-unjoined", function (options, content)
    SILE.call("resilient:internal:dropcap", { style = options.style, join = false }, content)
  end, "Style-aware initial capital letter, not joined to the following text.")

  self:registerCommand('code', function(_, content)
    SILE.call('style:apply', { name = 'code' }, content)
  end, "Style the content as code")
end

return package
