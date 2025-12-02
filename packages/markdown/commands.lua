--- Common commands for Markdown and Djot support in SILE, when there is no direct mapping
-- to existing commands or packages.
--
-- Derived from `packages.markdown.cmbase`.
--
-- Split in a standalone package so that it can be reused and
-- generalized somewhat independently from the underlying parsing code.
--
-- It implements high-level commands that are used by the markdown, djot and pandocat inputters.
--
-- It also exposes a method for classes or packages to register predefined Djot symbols.
--
-- @copyright License: MIT (c) 2022-2025 Omikhleia, Didier Willis
-- @classmod packages.markdown.commands
--
local utils = require("packages.markdown.utils")
local hasClass = utils.hasClass

local createCommand, createStructuredCommand,
      removeFromTree, subContent
        = SU.ast.createCommand, SU.ast.createStructuredCommand,
          SU.ast.removeFromTree, SU.ast.subContent

local base = require("packages.markdown.cmbase")

local package = pl.class(base)
package._name = "markdown.commands"

-- A small utility class that allows wrapping commands applied to a
-- content, avoiding a callback hell with conditionals where it is
-- used and providing a sequence-oriented presentation.
local CommandCascade = pl.class({
  _init = function (self)
    self.inner = {}
    self.outer = nil
  end,
  call = function (self, command, options)
    local out = self.outer and { self.outer } or self.inner
    self.outer = createStructuredCommand(command, options, out)
  end,
  tree = function (self, content)
    -- Return the cascaded AST without processing it
    for _, v in ipairs(content) do
      self.inner[#self.inner + 1] = v
    end
    local stacked = self.outer and { self.outer } or self.inner
    return stacked
  end,
  process = function (self, content)
    -- For convenience
    SILE.process(self:tree(content))
  end,
})

local function hasLinkContent(tree)
  if type(tree) == "table" then
    return #tree > 1 or hasLinkContent(tree[1])
  end
  if type(tree) == "string" and tree ~= "" then
    return true
  end
  return false
end

-- AST helper for the "implicit figure"
-- (tricky) This assumes a lot of knowledge about the AST...
local function implicitFigure (paracontent)
  local image, caption

  -- Does the paragraph content contain a single image element
  local command = type(paracontent) == "table" and #paracontent == 1 and paracontent[1].command
  if command == "markdown:internal:image" then
    image = paracontent[1]
    -- Does it have a non-empty caption...
    if (type(image[1]) == "string")
       or (type(image[1]) == "table" and #image[1] >= 1) then
      caption = image[1]
    end
  end
  return image, caption
end

-- Inputfilter callback for splitting strings at numbers and formatting
-- them as decimal numbers.
local function decimalFilter (input, _)
  local t = {}
  for token in SU.gtoke(input, "%d+%.?%d*") do
    if(token.string) then
      t[#t+1] = token.string
    else
      t[#t+1] = createCommand("markdown:internal:decimal", {}, token.separator)
    end
  end
  return t
end

local function wrapLinkContent (options, content)
  -- shallow copy before removing internal options
  -- (Content may be reused in pseudo-symbol macros or other means)
  local passedOptions = pl.tablex.copy(options)
  -- We already took care of these.
  passedOptions.src = nil
  passedOptions.id = nil
  -- We don't need an extra span if there are no other options.
  -- N.B. we don't remove cross-reference elements from the class option
  -- so we'll end up always wrapping a span in those cases.
  -- I deem it's acceptable.
  if next(passedOptions) ~= nil then
    -- Wrap a span into the AST directly, it plays better with styles when we
    -- do not invoke functions.
    content = { createCommand("markdown:internal:span", passedOptions, subContent(content)) }
  end
  return content
end

--- (Contructor) Package initialization.
-- @tparam table _ Package options (not used here).
function package:_init (_)
  base._init(self)
  if not SILE.scratch._markdown_commands then
    -- HACK NOTE:
    -- I don't like those scratch variables, but package reinstancing
    -- may occur in SILE. I never liked it, but it still occurs in SILE 0.15.13.
    -- Resilient classes override that behavior.
    -- But when a resilient class is not used, so we have to deal with it.
    -- For putative readers:
    --    load the djot package, cause you want to use Djot.
    --    load the markdown package, cause you want to use Markdown too.
    -- Both load the markdown.commands package.
    -- Guess what? The markdown.commands package is instantiated twice.
    -- It's supposed to be a SILE feature...
    SILE.scratch._markdown_commands = {}
  end
  self.predefinedSymbols = SILE.scratch._markdown_commands

  -- Only load low-level packages (= utilities)
  -- The class should be responsible for loading the appropriate higher-level
  -- constructs, see fallback commands further below for more details.
  self:loadPackage("bibtex")
  SILE.settings:set("bibtex.style", "csl") -- The future is CSL (active by default since SILE 0.15.10)
  self:loadPackage("color")
  self:loadPackage("embedders")
  self:loadPackage("highlighter")
  self:loadPackage("image")
  self:loadPackage("inputfilter")
  self:loadPackage("labelrefs")
  self:loadPackage("math")
  self:loadPackage("ptable")
  self:loadPackage("rules")
  self:loadPackage("smartquotes")
  self:loadPackage("svg")
  self:loadPackage("textsubsuper")
  self:loadPackage("url")

  -- Do those at the end so the resilient versions may possibly override things.
  self:loadAltPackage("resilient.lists", "lists")
  self:loadAltPackage("resilient.verbatim", "verbatim")

  -- Optional packages
  self:loadOptPackage("couyards")
  self:loadOptPackage("piecharts")

  -- Other conditional packages
  if self.isResilient then
    self:loadPackage("resilient.epigraph")
    self:loadPackage("resilient.defn")
  end

  -- Register some predefined symbols
  self:registerSymbol("_TOC_", true, function (options)
    return {
      createCommand("markdown:internal:toc", options),
    }
  end)
end

--- Register a predefined symbol for use in Djot (as of now).
--
-- A Djot symbol is a leaf inline node that will be expanded when encountered.
-- Our implementation allows to register custom symbols, that can be used
-- in Djot content, and expanded to something programmatic.
--
-- The rendering function takes the symbol options and content as arguments,
-- and must return a SILE AST (table).
--
-- Note that a span will also be created around an inline symbol if it has
-- attributes, so styling can be applied to the symbol.
--
-- @tparam string name Name of the symbol
-- @tparam boolean standalone If true, the symbol must be used alone at block-level
-- @tparam function render Function that will be called to render the symbo.
--   an AST (table or string).
function package:registerSymbol(name, standalone, render)
  -- Multiple package reinstancing is may occur in SILE, see comment above
  -- on scratch variables... So we do not warn if a symbol is already registered,
  -- and just overwrite it silently.
  self.predefinedSymbols[name] = { standalone = standalone, render = render }
end

local UsualSectioning = { "part", "chapter", "section", "subsection", "subsubsection" }
function package:_getSectioningCommand (level)
  local index = level + 1
  if index > 0 and index <= #UsualSectioning then
    -- Check we actually have those commands (e.g. some classes might not
    -- have subsubsections.)
    if self.hasCommandSupport[UsualSectioning[index]] then
      return UsualSectioning[index]
    end
    SU.warn("Unknown command \\"..UsualSectioning[index].." (fallback to a default generic header)")
    -- Default to something anyway.
    return "markdown:fallback:header"
  end
  -- Also default to something anyway, but different message
  SU.warn("No support found for heading level "..level.." (fallback to a default generic header)")
  return "markdown:fallback:header"
end

function package.declareSettings (_)
  SILE.settings:declare({
    parameter = "markdown.fixednbsp",
    type = "boolean",
    default = false,
    help = "Fixed-width non-breakable space."
  })
end

function package:registerCommands ()
  -- A. Commands (normally) intended to be used by this package only.

  self:registerCommand("markdown:internal:paragraph", function (_, content)
    -- Implicit figure: "An image with nonempty alt text, occurring by itself in a paragraph,
    -- will be rendered as a figure with a caption. The image’s alt text will be used as the
    -- caption."
    local image, caption = implicitFigure(content)
    if image and caption then
      -- (tricky) This assumes a lot of knowledge about the AST...
      -- We cannot make a functional call here, because captioned elements later
      -- work by "extracting" the caption from the AST... So we rebuild the
      -- expected AST.
      if image.options.id then
        -- We'll want the ID to apply to the captioning environment (to potentially
        -- use the caption numbering)
        local id = image.options.id
        local imgOptions = pl.tablex.copy(image.options)
        -- Shallow copy before removing internal options
        -- (Content may be reused in pseudo-symbol macros or other means)
        imgOptions.id = nil
        -- We also propagate image options to the englobing environment
        SILE.call("markdown:internal:captioned-figure", imgOptions, {
          image,
          createCommand("caption", {}, {
            createCommand("label", { marker = id }),
            caption,
          }),
        })
      else
        -- We also propagate image options to the englobing environment
        SILE.call("markdown:internal:captioned-figure", image.options, {
          image,
          createCommand("caption", {}, caption),
        })
      end
    else
      SILE.process(content)
      -- See comment on the lunamark writer layout option. With the default layout,
      -- this \par was not necessary... We switched to "compact" layout, to decide
      -- how to handle our own paragraphing.
      SILE.call("par")
    end
  end, "Paragraphing in Markdown (internal)")

  self:registerCommand("markdown:internal:thematicbreak", function (options, _)
    if hasClass(options, "asterism") then
      -- Asterism
      SILE.call("center", {}, { "⁂" })
    elseif hasClass(options, "dinkus") then
      -- Dinkus (with em-spaces)
      SILE.call("center", {}, { "* * *" })
    elseif hasClass(options, "bigrule") then
      -- 33% line
      SILE.call("center", {}, function ()
        SILE.call("raise", { height = "0.5ex" }, function ()
          SILE.call("hrule", { width = "33%lw", height = "0.4pt" })
        end)
      end)
    elseif hasClass(options, "fullrule") then
      -- Full line
      SILE.call("fullrule", { thickness = "0.4pt" })
    elseif hasClass(options, "pendant") and self.hasPackageSupport.couyards then
      -- Pendant, with more options available than in Markdown
      local opts = {
        type = SU.cast("integer", options.type or 6),
        height = options.height,
        width = not options.height and (options.width or "default")
      }
      SILE.call("smallskip")
      SILE.call("couyard", opts)
    elseif not hasClass(options, "none") then
      -- 20% line
      SILE.call("center", {}, function ()
        SILE.call("raise", { height = "0.5ex" }, function ()
          SILE.call("hrule", { width = "20%lw", height = "0.4pt" })
        end)
      end)
    end

    if hasClass(options, "pagebreak") then
      SILE.call("eject")
    end
  end, "Thematic break in Djot (internal)")

  self:registerCommand("markdown:internal:hrule", function (options, _)
    if options.separator == "***" then
      -- Asterism
      SILE.call("center", {}, { "⁂" })
    elseif options.separator == "* * *" then
      -- Dinkus (with em-spaces)
      SILE.call("center", {}, { "* * *" })
    elseif options.separator == "---" then
        -- 20% line
        SILE.call("center", {}, function ()
          SILE.call("raise", { height = "0.5ex" }, function ()
            SILE.call("hrule", { width = "20%lw", height = "0.4pt" })
        end)
      end)
    elseif options.separator == "----" then
      -- 33% line
      SILE.call("center", {}, function ()
        SILE.call("raise", { height = "0.5ex" }, function ()
          SILE.call("hrule", { width = "33%lw", height = "0.4pt" })
        end)
      end)
    elseif options.separator == "- - - -" and self.hasPackageSupport.couyards then
      -- Pendant (fixed choice = the one I regularly use)
      SILE.call("smallskip")
      SILE.call("couyard", { type = 6, width = "default" })
    elseif options.separator == "--------------" then -- Page break
      SILE.call("eject")
    else
      -- Full line
      SILE.call("fullrule", { thickness = "0.4pt" })
    end
  end, "Horizontal rule in Markdown (internal)")

  self:registerCommand("markdown:internal:header", function (options, content)
    local level = SU.required(options, "level", "header")
    local command = self:_getSectioningCommand(SU.cast("integer", level))
    -- Pass all attributes to underlying sectioning command, and interpret
    -- .unnumbered and .notoc pseudo-classes as alternatives to numbering=false
    -- and toc=false.
    local id = options.id
    options.id = nil -- cancel attribute here.
    if hasClass(options, "unnumbered") then
      options.numbering = false
    end
    if hasClass(options, "notoc") then
      options.toc = false
    end
    if self.isResilient then
      --Sectioning commands support the marker option.
      options.marker = id
      SILE.call(command, options, content)
    else
      -- We don't know if the marker option is supported.
      -- Presumably no, e.g. it's the SILE default book class...
      -- Things are somewhat messy then, as of how to insert the identifier label.
      -- If done before the sectioning, it could end on the previous page.
      -- Within the title content, it poses other problems to ToC entries, running headers...
      -- We are left with doing it after, but that's not perfect either vs.
      -- page breaks, paragraph indents and skips...
      SILE.call(command, options, content)
      if id then
        if not self.warnResilient then
          SU.warn([[You are not using a resilient class.
Sectioning command (]] .. command .. [[) with an identifier (]] .. id .. [[)
may sometimes introduce weird skips.
Please consider using a resilient-compatible class!]])
          self.warnResilient = true
        end
        SILE.call("label", { marker = id })
      end
    end
  end, "Header in Markdown (internal)")

  self:registerCommand("markdown:internal:div:id", function (options, content)
    local id = SU.required(options, "id", "div")
    SILE.call("label", { marker = id })
    SILE.process(content)
  end, "Add a cross reference marker before the div content (internal)")

  self:registerCommand("markdown:internal:div", function (options, content)
    local cascade = CommandCascade()
    if options.id then
      -- A bit tricky here in command cascading, so let's delegate.
      cascade:call("markdown:internal:div:id", { id = options.id})
    end
    if options.lang then
      cascade:call("language", { main = options.lang })
    end
    if options["custom-style"] then
      -- The style (or the hook) is responsible for paragraphing
      cascade:call("markdown:custom-style:hook", { name = options["custom-style"], scope = "block" })
    else
      cascade:call("markdown:internal:paragraph")
    end
    if hasClass(options, "poetry") then
      -- If the class or loaded packages provide a poetry environment and the div contains
      -- a lineblock structure only, then use the poetry environment instead.
      -- (tricky) This assumes a lot of knowledge about the AST...
      if self.hasCommandSupport.poetry and #content == 1 and content[1].command == "markdown:internal:lineblock" then
        content[1].command = "poetry"
        content[1].options = content[1].options or {}
        content[1].options.first = SU.boolean(options.first, false)
        if hasClass(options, "unnumbered") then
          content[1].options.numbering = false
        else
          content[1].options.numbering = SU.boolean(options.numbering, true)
        end
        content[1].options.step = options.step and SU.cast("integer", options.step)
        content[1].options.start = options.start and SU.cast("integer", options.start)
      end
    end
    cascade:process(content)
  end, "Div in Markdown (internal)")

  self:registerCommand("markdown:internal:decimal", function (_, content)
    SILE.typesetter:typeset(SU.formatNumber(content[1], { style = "decimal" }))
  end, "Formats a (number) content string as decimal (internal)")

  self:registerCommand("markdown:internal:span", function (options, content)
    if hasClass(options, "decimal") then
      content = self.class.packages.inputfilter:transformContent(content, decimalFilter)
    end

    if options.id then
      SILE.call("label", { marker = options.id })
    end

    local cascade = CommandCascade()
    if options.lang then
      cascade:call("language", { main = options.lang })
    end
    if hasClass(options, "smallcaps") then
      cascade:call("font", { features = "+smcp" })
    end
    if hasClass(options, "mark") then
      cascade:call("markdown:custom-style:hook", {
        name = "md-mark",
        alt = "markdown:fallback:mark",
        scope = "inline"
      })
    end
    if hasClass(options, "strike") then
      cascade:call("markdown:custom-style:hook", {
        name = "md-strikethrough",
        alt = "strikethrough",
        scope = "inline"
      })
    end
    if hasClass(options, "underline") then
      cascade:call("markdown:custom-style:hook", {
        name = "md-underline",
        alt = "underline",
        scope = "inline"
      })
    end
    if hasClass(options, "inserted") then
      cascade:call("markdown:custom-style:hook", {
        name = "md-insertion",
        alt = "underline",
        scope = "inline"
      })
    end
    if hasClass(options, "deleted") then
      cascade:call("markdown:custom-style:hook", {
        name = "md-deletion",
        alt = "strikethrough",
        scope = "inline"
      })
    end
    if options["custom-style"] then
      cascade:call("markdown:custom-style:hook", {
        name = options["custom-style"],
        scope = "inline"
      })
    end
    if hasClass(options, "nobreak") then
      cascade:call("hbox")
    end
    cascade:process(content)

    -- If the class enabled the indexer package, and if the span has an index:
    -- Call the indexentry command on the content.
    -- Due to how the indexer package works, the indexed term is the text generated
    -- from the content, loose most of the formatting and styling.
    -- At best, the language of the span might impact the key formatting (?).
    if options.index and self.hasPackageSupport.indexer then
      local indexes = pl.stringx.split(options.index, " ")
      for _, index in ipairs(indexes) do
        local label = options["indexed-" .. index]
        local indexing = CommandCascade()
        if options.lang then
          indexing:call("language", { main = options.lang })
        end
        indexing:call("indexentry", { index = index, label = label })
        indexing:process(content)
      end
    end
  end, "Span in Markdown (internal)")

  self:registerCommand("markdown:internal:image", function (options, _)
    local uri = SU.required(options, "src", "image")
    if options.id then
      SILE.call("label", { marker = options.id })
    end
    local ext = utils.getFileExtension(uri)
    if ext == "svg" then
      SILE.call("svg", options)
    elseif ext == "dot" then
      options.format = "dot"
      SILE.call("embed", options)
    elseif ext == "csv" then
      if not (self.hasPackageSupport.piecharts or self.hasPackageSupport.piechart) then -- HACK Some early versions of piecharts have the wrong internal name
        SU.error("No piecharts package available to render CSV data ".. uri)
      end
      -- Shallow copy before removing internal options
      -- (Content may be reused in pseudo-symbol macros or other means)
      options = pl.tablex.copy(options)
      options.src = nil
      options.csvfile = uri
      SILE.call("piechart", options)
    else
      SILE.call("img", options)
    end
  end, "Image in Markdown (internal)")

  self:registerCommand("markdown:internal:link", function (options, content)
    local uri = SU.required(options, "src", "link")
    if options.id then
      SILE.call("label", { marker = options.id })
    end
    if uri:sub(1,1) == "#" then
      -- local hash link
      local dest = uri:sub(2)
      if hasLinkContent(content) then
        content = wrapLinkContent(options, content)
        -- HACK. We use the target of a `\label`, knowing it is
        -- internally prefixed by "ref:" in the labelrefs package.
        -- That's not very nice to rely on internals...
        SILE.call("pdf:link", { dest = "ref:" .. dest }, content)
      else
        -- link with no textual content: we use them as a cross-references.
        local reftype
        if hasClass(options, "page") then reftype = "page"
        elseif hasClass(options, "section") then reftype = "section"
        elseif hasClass(options, "title") then reftype = "title"
        else reftype = "default" end
        SILE.call("ref", { marker = dest, type = reftype })
      end
    else
      if hasLinkContent(content) then
        content = wrapLinkContent(options, content)
        SILE.call("href", { src = uri }, content)
      else
        SU.warn("Ignored empty link to target "..uri)
      end
    end
  end, "Link in Markdown (internal)")

  self:registerCommand("markdown:internal:footnote", function (options, content)
    if not self.hasCommandSupport.footnote then
      -- The reasons for NOT loading a package for this high-level structure
      -- is that the class or other packages may provide their own implementation
      -- (e.g. formatted differently, changed to endnotes, etc.).
      -- So we only do it as a fallback if missing, to degrade gracefully.
      SU.warn("Trying to enforce fallback for unavailable \\footnote command")
      self:loadAltPackage("resilient.footnotes", "footnotes")
    end
    if options.id then
      content = {
        createCommand("label", { marker = options.id }),
        subContent(content)
      }
    end
    SILE.call("footnote", options, content)
  end, "Footnote in Markdown (internal)")

  self:registerCommand("markdown:internal:rawinline", function (options, content)
    local format = SU.required(options, "format", "rawcontent")
    local rawtext = content[1]
    if type(rawtext) ~= "string" then
      SU.error("Raw inline content shall be a string, something bad occurred in markdown processing")
    end
    if format == "sile" then
      rawtext = "\\document{"..rawtext.."}"
      SILE.processString(rawtext, "sil")
    elseif format == "sile-lua" then
      SILE.processString(rawtext, "lua")
    elseif format == "html" then
      if rawtext:match("^<br[>/%s]") then
        SILE.call("markdown:internal:hardbreak")
      elseif rawtext:match("^<wbr[>/%s]") then
        SILE.call("penalty", { penalty = 100 })
      end
    end
  end, "Raw native inline content in Markdown (internal)")

  self:registerCommand("markdown:internal:hardbreak", function (_, _)
    -- We don't want to use a cr here, because it would affect parindents,
    -- insert a parskip, and maybe other things.
    -- It's a bit tricky to handle a hardbreak depending on depending on the
    -- alignment of the paragraph:
    --    justified = we can't use a break, a cr (hfill+break) would work
    --    ragged left = we can't use a cr
    --    centered = we can't use a cr
    --    ragged right = we don't care, a break is sufficient
    -- Knowning the alignment is not obvious, neither guessing it from the skips.
    -- Using a parfillskip seems to do the trick, but it's maybe a bit hacky.
    -- This is nevertheless what would have occurred with a par in the same
    -- situation.
    SILE.typesetter:pushGlue(SILE.settings:get("typesetter.parfillskip"))
    SILE.call("break")
  end, "Hard break in Markdown (internal)")

  self:registerCommand("markdown:internal:rawblock", function (options, content)
    local format = SU.required(options, "format", "rawcontent")
    if format == "sile" or format == "sile-lua" then
      SILE.call("markdown:internal:paragraph", {}, function ()
        SILE.call("markdown:internal:rawinline", options, content)
      end)
    end
  end, "Raw native block in Markdown (internal)")

  self:registerCommand("markdown:internal:blockquote", function (options, content)
    -- SILE's plain class provides a "blockquote" since SILE 0.15.0.
    -- Resilient document classes also provide a blockquote environment.
    -- So we do not need to maintain our own fallback, and this is just
    -- a simple wrapper.
    SILE.call("blockquote", options, content)
  end, "Block quote in Markdown (internal)")

  self:registerCommand("markdown:internal:captioned-table", function (options, content)
    -- Makes it easier for class/packages to provide their own captioned-table
    -- environment if they want to do so (possibly with more features,
    -- e.g. managing list of tables, numbering and cross-references etc.),
    -- while minimally providing a default fallback solution.
    if not self.hasCommandSupport["captioned-table"] then
      SILE.call("markdown:fallback:captioned-table", {}, content)
    else
      local tableopts = {}
      if hasClass(options, "unnumbered") then
        tableopts.numbering = false
      end
      if hasClass(options, "notoc") then
        tableopts.toc = false
      end
      SILE.call("captioned-table", tableopts, content)
    end
  end, "Captioned table in Markdown (internal)")

  self:registerCommand("markdown:internal:captioned-figure", function (options, content)
    -- Makes it easier for class/packages to provide their own captioned-figure
    -- environment if they want to do so (possibly with more features,
    -- e.g. managing list of tables, numbering and cross-references etc.),
    -- while minimally providing a default fallback solution.
    if not self.hasCommandSupport["captioned-figure"] then
      SILE.call("markdown:fallback:captioned-figure", {}, content)
    else
      local figopts = {}
      if hasClass(options, "unnumbered") then
        figopts.numbering = false
      end
      if hasClass(options, "notoc") then
        figopts.toc = false
      end
      SILE.call("captioned-figure", figopts, content)
    end
  end, "Captioned figure in Markdown (internal)")

  -- Code blocks

  self:registerCommand("markdown:internal:codeblock", function (options, content)
    local render = SU.boolean(options.render, true)
    local processed = false
    local render_exceptions = hasClass(options, "lua") or hasClass(options, "sil") or hasClass(options, "xml")
    if render and not render_exceptions then
      -- If render is true, we try to to render the code block "natively":
      --  - With a raw handler if available
      --  - Or with an embed handler if available
      -- If none of those are available, the non-rendered logic is used.
      -- Lua, XML, SIL are exceptions, the proper way to execute code blocks
      -- is to use raw code blocks (=sile or sile-lua formats).
      local handler = utils.hasRawHandler(options)
      if handler then
        if options.id then
          -- This would introduce a line break in some case, so we don't do it.
          SU.warn("Ignoring id attribute in code block with raw handler (".. options.id ..")")
        end
        handler(options, content)
        processed = true
      else
        local format, embed = utils.hasEmbedHandler(options)
        if format then
          if options.id then
            -- Assuming embedders render an image, the label marker can be inlined with it.
            SILE.call("label", { marker = options.id })
          end
          options.format = format
          embed(options, content)
          processed = true
        end
      end
    end
    if not processed then
      -- Default case: just output the code block as verbatim,
      -- We pass to the highlighter handler for potential syntax highlighting.
      if options.id then
        -- As above, but this would be doable here, either in the highlighter
        -- or even in the verbatim environment.
        -- But as long as we can support both the standard and the resilient verbatim
        -- environments, we don't do it, the former wouldn't honor it...
        -- (Neither the resilient verbatim at this point but that would be in our control.)
        SU.warn("Ignoring id attribute in standard code block (".. options.id ..")")
      end
      local handler = SILE.rawHandlers.highlight
      handler(options, content)
    end
    SILE.call("par")
  end, "(Fenced) code block in Markdown (internal)")

  self:registerCommand("markdown:internal:lineblock", function (_, content)
    SILE.call("smallskip")
    for _, v in ipairs(content) do
      if v.command == "v" then
        SILE.call("markdown:internal:paragraph", {}, v)
      else -- stanza
        SILE.call("smallskip")
      end
    end
    SILE.call("smallskip")
  end, "Default line block in Markdown (internal)")

  self:registerCommand("markdown:internal:math", function (options, content)
    -- NOTE: The following didn't work: SILE.call("math", options, content)
    -- Let's go for a lower-level AST construct instead.
    SILE.process({
      createCommand("math", options, SU.ast.contentToString(content))
    })
  end)

  self:registerCommand("markdown:internal:nbsp", function (options, _)
    -- Normally an inter-word non-breakable space is stretchable/shrinkable, with
    -- the same rules as a regular space. That's good typography, but some people
    -- may complain about it, so let's have a setting for overrinding it.
    -- (And with Djot, we can attach attributes to any content, so why not have a
    -- pseudo-class attribute there too.)
    local fixed = hasClass(options, "fixed") or SILE.settings:get("markdown.fixednbsp")
    local widthsp = SILE.shaper:measureSpace(SILE.font.loadDefaults({}))
    if fixed then
      SILE.call("kern", { width = widthsp.length })
    else
      SILE.call("kern", { width = widthsp })
    end
  end, "Inserts a non-breakable inter-word space (internal)")

  self:registerCommand("markdown:internal:captioned-blockquote", function (options, content)
    if type(content) ~= "table" then
      SU.error("Expected a table AST content in captioned blockquote environment")
    end
    local title = removeFromTree(content, "caption")

    if self.hasCommandSupport.epigraph then -- assuming the implementation from resilient.epigraph.
      if title then
        -- Trick: Put the extract title back as "\source"
        title.command = "source"
        content[#content+1] = title
      end
      SILE.call("epigraph", options, content)
    else
      SU.warn([[Apparently, you are not using a resilient class.
Quotation captions are ignored.
Please consider using a resilient-compatible class!]])
      SILE.call("markdown:internal:blockquote", options, content)
    end
  end, "Captioned blockquote in Djot (internal)")

  self:registerCommand("markdown:internal:toc", function (options, _)
    if not self.hasCommandSupport.tableofcontents then
      SU.warn("No table of contents command available (skipped)")
      return
    end
    local tocHeaderCmd = self.hasCommandSupport["tableofcontents:header"]
    if tocHeaderCmd then
      -- HACK (opinionated)
      -- By design, resilient.tableofcontents does not output a header.
      -- In case the standard tableofcontents package from the SILE core
      -- distribution is used, then we temporarily cancel its header,
      -- so we get the same behavior in whatever case.
      SILE.Commands["tableofcontents:header"] = function () end
    end
    SILE.call("tableofcontents", options)
    SILE.Commands["tableofcontents:header"] = tocHeaderCmd
  end, "Table of contents in Djot (internal)")

  self:registerCommand("markdown:internal:defn", function (options, content)
    -- Makes it easier for class/packages to provide their own definition
    -- environment if they want to do so (possibly with more features),
    -- while minimally providing a default fallback solution.
    if not self.hasCommandSupport.defn then
      SILE.call("markdown:fallback:defn", {}, content)
    else
      SILE.call("defn", options, content)
    end
  end, "Definition item in Markdown (internal)")

  self:registerCommand("markdown:internal:symbol", function (options, _)
    local symbol = SU.required(options, "_symbol_", "symbol")
    local standalone = SU.boolean(options._standalone_, false)
    local content
    local predefined = self.predefinedSymbols[symbol]
    if predefined then
      if predefined.standalone and not standalone then
        SU.error("Cannot use " .. symbol .. " as inline content")
      end
      content = predefined.render(options)
    elseif symbol:match("^U%+[0-9A-F]+$") then
      content = {
        createCommand("use", { module = "packages.unichar" }),
        createCommand("unichar", {}, symbol)
      }
    else
      SU.warn("Symbol '" .. symbol .. "' was not expanded (no corresponding metadata found)")
      local text = ":" .. symbol .. ":"
      content = { text }
    end
    -- Shallow copy before removing internal options
    -- (Content may be reused in pseudo-symbol macros or other means)
    options = pl.tablex.copy(options)
    options._symbol_ = nil
    options._standalone_ = nil
    if next(options) and not standalone then
      -- Add a span for attributes
      SILE.call("markdown:internal:span", options, content);
    else
      SILE.process(content)
    end
  end, "Symbol in Djot (internal)")

  -- B. Fallback commands

  self:registerCommand("markdown:fallback:header", function (_, content)
    SILE.typesetter:leaveHmode(1)
    SILE.call("goodbreak")
    SILE.call("smallskip")
    SILE.call("noindent")
    SILE.call("font", { weight = 700 }, content)
    SILE.call("novbreak")
    SILE.call("par")
    SILE.call("novbreak")
  end, "A fallback default header if none exists for the requested sectioning level")

  self:registerCommand("markdown:fallback:captioned-table", function (_, content)
    if type(content) ~= "table" then
      SU.error("Expected a table AST content in captioned table environment")
    end
    local caption = removeFromTree(content, "caption")

    SILE.process(content)
    if caption then
      SILE.call("novbreak")
      SILE.call("font", {
        size = SILE.settings:get("font.size") * 0.95
      }, function ()
        SILE.call("center", {}, caption)
      end)
      SILE.call("smallskip")
    end
  end, "A fallback command for Markdown to insert a captioned table")

  self:registerCommand("markdown:fallback:defn", function (_, content)
    if type(content) ~= "table" then
      SU.error("Expected a table AST content in captioned table environment")
    end
    local term = removeFromTree(content, "term")
    local desc = removeFromTree(content, "desc")

    SILE.typesetter:leaveHmode()
    SILE.call("strong", {}, term)
    SILE.call("novbreak")
    SILE.settings:temporarily(function ()
      local indent = SILE.types.measurement("2em"):absolute()
      local lskip = SILE.settings:get("document.lskip") or SILE.types.node.glue()
      SILE.settings:set("document.lskip", SILE.types.node.glue(lskip.width + indent))
      SILE.process(desc)
      SILE.typesetter:leaveHmode()
    end)
    SILE.call("smallskip")
  end, "A fallback command for Markdown to insert a definition item (term, desc)")

  self:registerCommand("markdown:fallback:captioned-figure", function (_, content)
    if type(content) ~= "table" then
      SU.error("Expected a table AST content in captioned figure environment")
    end
    local caption = removeFromTree(content, "caption")

    SILE.call("smallskip")
    SILE.call("center", {}, function ()
      SILE.process(content)
      if caption then
        SILE.call("novbreak")
        SILE.call("font", {
          size = SILE.settings:get("font.size") * 0.95
        }, caption)
      end
    end)
    SILE.call("smallskip")
  end, "A fallback command for Markdown to insert a captioned figure")

  self:registerCommand("markdown:fallback:mark", function (_, content)
    local leading = SILE.types.measurement("1bs"):tonumber()
    local bsratio = utils.computeBaselineRatio()
    SILE.typesetter:liner("markdown:fallback:mark", content,
      function (box, typesetter, line)
        local outputWidth = SU.rationWidth(box.width, box.width, line.ratio)
        local H = SU.max(box.height:tonumber(), (1 - bsratio) * leading)
        local D = SU.max(box.depth:tonumber(), bsratio * leading)
        local X = typesetter.frame.state.cursorX
        SILE.outputter:pushColor(SILE.types.color("yellow"))
        SILE.outputter:drawRule(X, typesetter.frame.state.cursorY - H, outputWidth, H + D)
        SILE.outputter:popColor()
        box:outputContent(typesetter, line)
      end
    )
  end)

  -- C. Customizable hooks

  self:registerCommand("markdown:custom-style:hook", function (options, content)
    -- Default/standard implementation for the custom-style hook:
    -- 1. If we are in the context of a resilient-compatible class and there's
    -- an existing style going by that name, we apply it.
    -- 2. Otherwise, if there is a corresponding SILE command, going by the
    -- optional "alt" command name or if unspecified, the style name itself,
    -- we invoke it.
    -- 3. Otherwise, we just silently ignore the style and process the content.
    --
    -- It allows us to;
    --  - Use resilient styling paradigm if applicable
    --  - Use some alternate fallback command if provided
    --  - Use some interesting commands, such as "custom-style=raggedleft".
    -- Package or class designers MAY override this hook to support any other
    -- styling mechanism they may have or want.
    -- The available options are the custom-style "name", an optional "alt"
    -- command name, and a "scope" which can be "inline" (for inline
    -- character-level styling) or "block" (for block paragraph-level styling).
    local name = SU.required(options, "name", "markdown custom style hook")
    local scope = SU.required(options, "scope", "markdown custom style hook")
    local alt = options.alt or name

    if self.hasStyleSupport[name] then
      if scope == "block" then
        SILE.call("style:apply:paragraph", { name = name }, content)
      else
        SILE.call("style:apply", { name = name }, content)
      end
    elseif self.hasCommandSupport[alt] then
      SILE.call(alt, {}, content)
    else
      SU.debug("markdown.commands", "Feature detection: ignoring unknown custom style:", name)
      SILE.process(content)
      if scope == "block" then
        SILE.call("par")
      end
    end
  end, "Default hook for custom style support in Markdown")

end

package.documentation = [[\begin{document}
A helper package for Markdown and Djot processing, providing common hooks and fallback commands.

It is not intended to be used alone.

For class or package designers, it provides a method \code{registerSymbol} to define their own symbols, which can be used in the Djot syntax.
\end{document}]]

return package
