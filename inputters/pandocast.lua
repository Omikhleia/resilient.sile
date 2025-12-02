--- Pandoc JSON AST native inputter for SILE
--
-- Focussed on Markdown needs (things such as table support is therefore
-- limited to that scope).
--
-- AST conversion relies on the Pandoc types specification:
-- https://hackage.haskell.org/package/pandoc-types
--
-- Using the luajson (LPEG-based) or lunajson (pure Lua) library for parsing.
-- Reusing the common commands initially made for the "markdown" inputter/package.
--
-- @copyright License: MIT (c) 2022-2024 Omikhleia, Didier Willis
-- @module inputters.pandocast
--
local utils = require("packages.markdown.utils")
local createCommand, createStructuredCommand
        = SU.ast.createCommand, SU.ast.createStructuredCommand

local Pandoc = {
   MIN_API_VERSION = { 1, 22, 0 }, -- Minimal supported API version (semver)
   CUR_API_VERSION = { 1, 23, 0 }  -- Current supported API version (semver)
}

local function checkAstSemver(version)
  -- IMPLEMENTATION NOTE: Kept simple for now, and naive.
  -- We shouldn't care the patch level.
  -- The Pandoc AST may change upon "minor" updates, though.
  -- We assume min and current versions have the same major version.
  local major, minor = table.unpack(version)
  local min_major, min_minor = table.unpack(Pandoc.MIN_API_VERSION)
  local _, cur_minor = table.unpack(Pandoc.CUR_API_VERSION)
  if not major or major ~= min_major then
    SU.error("Unsupported Pandoc AST major version " .. major
      .. ", only version " .. min_major.. " is supported")
  end
  if not minor or minor < min_minor then
    SU.error("Unsupported Pandoc AST version " .. table.concat(version, ".")
      .. ", needing at least " ..  table.concat(Pandoc.MIN_API_VERSION, "."))
  end
  if minor > cur_minor then
    -- Warn and pray.
    -- When this occurs, we may check to properly handle version updates
  SU.warn("Pandoc AST version " .. table.concat(version, ".")
    .. ", is more recent than supported " ..  table.concat(Pandoc.CUR_API_VERSION, ".")
    .. ", there could be issues.")
  end
end

local Renderer = pl.class()

function Renderer:_init(options)
  self.shift_headings = SU.cast("integer", options.shift_headings or 0)
  self.parentmetadata = {}
  for key, val in pairs(options) do
    local meta = key:match("^meta:(.*)")
    if meta then
      if meta:match("[%w_+-]+") then
        -- We don't use them in this renderer, but we can pass them through
        -- to embedded djot documents.
        self.parentmetadata[key] = val
      else
        SU.warn("Invalid metadata key is skipped: "..meta)
      end
    end
  end
end

-- Allows unpacking tables on some Pandoc AST nodes so as to map them to methods
-- with a simpler and friendly interface.
local HasMultipleArgs = {
  Cite = true,
  Code = true,
  CodeBlock = true,
  Div = true,
  Header = true,
  Image = true,
  Link = true,
  Math = true,
  Span = true,
  OrderedList = true,
  Quoted = true,
  RawInline = true,
  RawBlock = true,
  Table = true,
  Figure = true,
}

-- Parser AST-walking logic.

local function addNodes(out, elements)
  -- Simplify outputs by collating strings
  if type(elements) == "string" and type(out[#out]) == "string" then
    out[#out] = out[#out] .. elements
  else
    -- Simplify out by removing empty elements
    if type(elements) ~= "table" or elements.command or #elements > 0 then
      out[#out+1] = elements
    end
  end
end

function Renderer:render(element)
  local out
  if type(element) == 'string' then
    out = element
  end
  if type(element) == 'table' then
    out = {}
    if element.t then
      if self[element.t] then
        if HasMultipleArgs[element.t] then
          addNodes(out, self[element.t](self, table.unpack(element.c)))
        else
          addNodes(out, self[element.t](self, element.c))
        end
      else
        SU.warn("Unrecognized Pandoc AST element "..element.t)
      end
    end
    for _, b in ipairs(element) do
      addNodes(out, self:render(b))
    end
  end
  --  Simplify output by removing useless grouping
  if type(out) == "table" and #out == 1 and not out.command then
    out = out[1]
  end
  return out
end

-- type Attr = (Text, [Text], [(Text, Text)])
--   That is: identifier, classes, key-value pairs
--   We map it to something easier to manipulate, similar to what a Pandoc
--   Lua custom writer would expose, and which also looks like regular SILE
--   options.
local function pandocAttributes(attributes)
  local id, class, keyvals = table.unpack(attributes)
  local options = {
    id = id and id ~= "" and id or nil,
    class = table.concat(class, " "),
  }
  for _, keyval in ipairs(keyvals) do
    local key = keyval[1]
    local value = keyval[2]
    options[key] = value
  end
  return options
end

local function extractLineBlockLevel (inlines)
  -- The indentation of line blocks is not really a first-class citizen in
  -- the Pandoc AST: Pandoc replaces the indentation spaces with U+00A0
  -- and stacks them in the first "Str" Inline (adding it if necessary)
  -- We remove them, and return the count.
  local f = inlines[1]
  local level = 0
  if f and f.t == "Str" then
    -- N.B. f is nil if there is no content (empty line).
    -- Otherwise, it shall can be a string, with the leading spaces.
    -- Or any other inline content if there are not leading spaces.
    local line = f.c
    line = line:gsub("^[ ]+", function (match) -- Warning, U+00A0 here.
      level = luautf8.len(match)
      return ""
    end)
    f.c = line -- replace
  end
  return level, inlines
end

local function extractTaskListBullet (blocks)
  -- Task lists are not really first-class citizens in the Pandoc AST. Pandoc
  -- replaces the Markdown [ ], [x] or [X] by Unicode ballot boxes, but leaves
  -- them as the first inline in the first block, as:
  --   Plain > Str > "☐" or "☒"
  -- We extract them for appropriate processing.
  local plain = blocks[1] and blocks[1].c -- Plain content
  local str = plain and plain[1] and plain[1].c -- Str content
  if (str == "☐" or str == "☒") then
    table.remove(blocks[1].c, 1)
    return str
  end
  -- return nil
end

-- PANDOC AST BLOCKS

-- Plain [Inline]
-- (not a paragraph)
function Renderer:Plain (inlines)
  return self:render(inlines)
end

-- Para [Inline]
function Renderer:Para (inlines)
  local content = self:render(inlines)
  return createCommand("markdown:internal:paragraph", {}, content)
end

-- LineBlock [[Inline]]
function Renderer:LineBlock (lines)
  local buffer = {}
  for _, inlines in ipairs(lines) do
    local level, currated_inlines = extractLineBlockLevel(inlines)
    -- Let's be typographically sound and use quad kerns rather than spaces for indentation
    local contents = (level > 0) and {
      createCommand("kern", { width = level.."em" }),
      self:render(currated_inlines)
    } or self:render(currated_inlines)
    if #contents == 0 then
      buffer[#buffer+1] = createCommand("stanza", {})
    else
      buffer[#buffer+1] = createCommand("v", {}, contents)
    end
  end
  return createStructuredCommand("markdown:internal:lineblock", {}, buffer)
end

-- CodeBlock Attr Text
-- Code block (literal) with attributes
function Renderer:CodeBlock (attributes, text)
  local options = pandocAttributes(attributes)
  if utils.hasClass(options, "djot") or utils.hasClass(options, "markdown") then
    options = pl.tablex.union(self.parentmetadata, options)
    options.shift_headings = self.shift_headings
  end
  return createCommand("markdown:internal:codeblock", options, text)
end

-- RawBlock Format Text
function Renderer.RawBlock (_, format, text)
  return createCommand("markdown:internal:rawblock", { format = format }, text)
end

-- BlockQuote [Block]
function Renderer:BlockQuote (blocks)
  local content = self:render(blocks)
  return createCommand("markdown:internal:blockquote", {}, content)
end

-- OrderedList ListAttributes [[Block]]
local pandocListNumberStyleTags = {
  -- DefaultStyle
  Example = "arabic",
  Decimal = "arabic",
  UpperRoman = "Roman",
  LowerRoman = "roman",
  UpperAlpha = "Alpha",
  LowerAlpha = "alpha",
}
local pandocListNumberDelimTags = {
  -- DefaultDelim
  OneParen = { after = ")" },
  Period = { after ="." },
  TwoParens = { before = "(", after = ")" }
}
function Renderer:OrderedList (listattrs, itemblocks)
  -- ListAttributes = (Int, ListNumberStyle, ListNumberDelim)
  --   Where ListNumberStyle, ListNumberDelim) are tags
  local start, style, delim = table.unpack(listattrs)
  local display = pandocListNumberStyleTags[style.t]
  local delimiters = pandocListNumberDelimTags[delim.t]
  local options = {
    start = start,
    display = display,
  }
  if delimiters then
    options.before = delimiters.before
    options.after= delimiters.after
  end

  local contents = {}
  for i = 1, #itemblocks do
    contents[i] = createCommand("item", {}, self:render(itemblocks[i]))
  end
  return createStructuredCommand("enumerate", options, contents)
end

-- BulletList [[Block]]
-- Bullet list (list of items, each a list of blocks)
function Renderer:BulletList (itemblocks)
  local contents = {}
  for i = 1, #itemblocks do
    local blocks = itemblocks[i]
    local options = { bullet = extractTaskListBullet(blocks) }
    contents[i] = createCommand("item", options, self:render(blocks))
  end
  return createStructuredCommand("itemize", {}, contents)
end

-- DefinitionList [([Inline], [[Block]])]
function Renderer:DefinitionList (items)
  local buffer = {}
  for _, item in ipairs(items) do
    local term = self:render(item[1])
    local definition = self:render(item[2])
    buffer[#buffer + 1] = createStructuredCommand("markdown:internal:defn", {}, {
      createCommand("term", {}, term),
      createStructuredCommand("desc", {}, definition)
    })
  end
  return createStructuredCommand("markdown:internal:paragraph", {}, buffer)
end

-- Header Int Attr [Inline]
function Renderer:Header (level, attributes, inlines)
  local options = pandocAttributes(attributes)
  local content = self:render(inlines)
  options.level = level + self.shift_headings
  return createCommand("markdown:internal:header", options, content)
end

-- HorizontalRule
-- Horizontal rule
function Renderer.HorizontalRule (_)
  return createCommand("fullrule") -- No way to customize it.
end

-- Div Attr [Block]
-- Generic block container with attributes
function Renderer:Div (attributes, blocks)
  local options = pandocAttributes(attributes)
  local content = self:render(blocks)
  return createCommand("markdown:internal:div" , options, content)
end

local pandocAlignmentTags = {
  AlignDefault = "default",
  AlignLeft = "left",
  AlignRight = "right",
  AlignCenter = "center",
}

-- Cell Attr Alignment RowSpan:Int ColSpan:Int [Block]
function Renderer:pandocCell (cell, colalign)
  local _, align, rowspan, colspan, blocks = table.unpack(cell)
  if rowspan ~= 1 then
    -- Not doable without pain, ptable has cell splitting but no row spanning.
    -- We'd have to handle this very differently.
    SU.error("Pandoc AST tables with row spanning cells are not supported yet")
  end
  local cellalign = pandocAlignmentTags[align.t]
  local halign = cellalign ~= "default" and cellalign or colalign
  return createCommand("cell", { valign="middle", halign = halign, span = colspan }, self:render(blocks))
end

-- Row Attr [Cell]
function Renderer:pandocRow (row, colaligns, options)
  local cells = row[2]
  local cols = {}
  for i, cell in ipairs(cells) do
    local col = self:pandocCell(cell, colaligns[i])
    cols[#cols+1] = col
  end
  return createStructuredCommand("row", options or {}, cols)
end

-- Table Attr Caption [ColSpec] TableHead [TableBody] TableFoot
function Renderer:Table (_, caption, colspecs, thead, tbodies, tfoot)
  -- CAVEAT: This goes far beyond what Markdown needs (quite logically, Pandoc
  -- supporting  other formats) and can be hard to map to SILE's ptable package.
  local aligns = {}
  for _, colspec in ipairs(colspecs) do
    -- ColSpec Alignment ColWidth
    -- For now ignore the weird colwidth...
    aligns[#aligns+1] = pandocAlignmentTags[colspec[1].t]
  end
  local numberOfCols = #colspecs
  local ptableRows = {}

  -- TableHead Attr [Row]
  local hasHeader = false
  for _, row in ipairs(thead[2]) do
    hasHeader = true
    ptableRows[#ptableRows+1] = self:pandocRow(row, aligns, { background = "#eee"})
  end

  -- TableBody Attr RowHeadColumns [Row] [Row]
  --   with an "intermediate" head row... (we skip this!)
  --   RowHeadColumns Int
  for _, tbody in ipairs(tbodies) do
    if tbody[2] ~= 0 then SU.error("Pandoc AST tables with several head columns are not sup ported") end
    for _, row in ipairs(tbody[4]) do
      ptableRows[#ptableRows+1] = self:pandocRow(row, aligns)
    end
  end

  -- TableFoot Attr [Row]
  for _, row in ipairs(tfoot[2]) do
    ptableRows[#ptableRows+1] = self:pandocRow(row, aligns)
  end

  local cWidth = {}
  for i = 1, numberOfCols do
    -- Currently we make all columns the same width, with the table taking
    -- a full line width. Well, nearly full: 99.9% to avoid 100% which
    -- causes issues in SILE flushed/centered environments, but this is
    -- deemed acceptable (hardly visible, and in most case we have some
    -- rounding anyway with the number format, so we aren't really making
    -- things worse).
    cWidth[i] = string.format("%.5f%%lw", 99.9 / numberOfCols)
  end
  local ptable = createStructuredCommand("ptable", {
    cols = table.concat(cWidth, " "),
    header = hasHeader,
  }, ptableRows)

  -- Caption (Maybe ShortCaption) [Block]
  -- No block or empty block = no caption..
  local hasCaption = caption and #caption[#caption] > 0
  local wrapped = hasCaption and {
    ptable,
    createCommand("caption", {}, self:render(caption[#caption]))
  } or { ptable }
  return createStructuredCommand("markdown:internal:captioned-table", {}, wrapped)
end

-- Figure Attr Caption [Block]
-- Added in Pandoc types 1.23, and now used when "implicit_figures" is enabled.
-- (This is the case by default in Pandoc >= 3.1)
function Renderer:Figure (attributes, caption, blocks)
  local options = pandocAttributes(attributes)
  -- Caption (Maybe ShortCaption) [Block]
  -- ShortCaption is either null or [Inline]
  local captionContent = self:render(caption[#caption])
  local content = self:render(blocks)

  -- More weirdness than expected? Can't say, but it's surely an "ad-hoc" choice:
  -- Considering Markdown: ![caption](image){#id .class key=value}
  --  - The id is promulgated to the Figure
  --  - Other classes and key-values are left on the Image
  --  - The Image is wrapped in a Plain (so indeed into a block)
  -- (Checked with Pandoc 3.4 on ![caption](image){#fig .doh width="1cm"})
  -- It's hard to tell how our logic below would behave with non-Markdown
  -- input, but let's say it's out of scope for now.
  if options.id then
    -- In our case, we move the id to the caption, which may be be the numbered
    -- element for use in cross-references...
    local id = options.id
    options.id = nil
    return createStructuredCommand("markdown:internal:captioned-figure", options, {
      content,
      createCommand("caption", {}, {
        createCommand("label", { marker = id }),
        captionContent
      })
    })
  end
  return createStructuredCommand("markdown:internal:captioned-figure", options, {
    content,
    createCommand("caption", {}, captionContent)
  })
end

-- PANDOC AST INLINES

-- Str Text
function Renderer.Str (_, text)
  return utils.nbspFilter(text)
end

-- Emph [Inline]
function Renderer:Emph (inlines)
  local content = self:render(inlines)
  return createCommand("em", {}, content)
end

-- Strong [Inline]
function Renderer:Strong (inlines)
  local content = self:render(inlines)
  return createCommand("strong", {}, content)
end

-- Underline [Inline]
function Renderer:Underline (inlines)
  local content = self:render(inlines)
  return createCommand("markdown:internal:span", { class = "underline" }, content)
end

-- Strikeout [Inline]
function Renderer:Strikeout (inlines)
  local content = self:render(inlines)
  return createCommand("markdown:internal:span" , { class = "strike" }, content)
end

-- Superscript [Inline]
function Renderer:Superscript (inlines)
  local content = self:render(inlines)
  return createCommand("textsuperscript", {}, content)
end

-- Subscript [Inline]
function Renderer:Subscript (inlines)
  local content = self:render(inlines)
  return createCommand("textsubscript", {}, content)
end

-- SmallCaps [Inline]
function Renderer:SmallCaps (inlines)
  local content = self:render(inlines)
  return createCommand("markdown:internal:span", { class = "smallcaps" }, content)
end

-- Quoted QuoteType [Inline]
--   Where QuoteType is a tag DoubleQuote or SingleQuote
function Renderer:Quoted (quotetype, inlines)
  local content = self:render(inlines)
  if quotetype.t == "DoubleQuote" then
    return createCommand("doublequoted", {}, content)
  end
  return createCommand("singlequoted", {}, content)
end

local function _inlinesToStr (inlines)
  local buffer = {}
  for _, inline in ipairs(inlines) do
    if inline.t == "Str" then
      buffer[#buffer + 1] = inline.c
    elseif inline.t == "Space" or inline.t == "SoftBreak" or inline.t == "LineBreak" then
      buffer[#buffer + 1] = " "
    else
      SU.warn("Skipped inline element in Cite: " .. inline.t)
    end
  end
  return table.concat(buffer)
end

-- Cite [Citation] [Inline]
--   Where a Citation is a dictionary:
--     { citationId: Text, citationPrefix: [Inline], citationSuffix: [Inline],
--       citationMode: CitationMode, citationNoteNum: Int, citationHash: Int }
--   and CitationMode is a tag AuthorInText, SuppressAuthor or NormalCitation.
-- We do not use the parse Citation, but rather the inlines directly,
-- re-serializing them to string, so we can be aligned with what we do in
-- the Markdown and Djot inputters.
function Renderer:Cite (_, inlines)
  local rawcites = _inlinesToStr(inlines)
  -- Remove leading and trailing brackets (if any)
  rawcites = rawcites:gsub("^%[", ""):gsub("%]$", "")
  return utils.naiveCitations(rawcites)
end

-- Code Attr Text
function Renderer.Code (_, attributes, text)
  local options = pandocAttributes(attributes)
  return createCommand("code", options, text)
end

-- Space
function Renderer.Space (_)
  return " "
end

-- SoftBreak
function Renderer.SoftBreak (_)
  return " " -- Yup.
end

-- LineBreak
-- Hard line break
function Renderer.LineBreak (_)
  return createCommand("markdown:internal:hardbreak")
end

-- Math MathType Text
-- TeX math (literal)
function Renderer.Math (_, mathtype, text)
  local mode = (mathtype.t and mathtype.t == "DisplayMath") and "display" or "text"
  return createCommand("markdown:internal:math" , { mode = mode }, { text })
end

-- RawInline Format Text
function Renderer.RawInline (_, format, text)
  return createCommand("markdown:internal:rawinline", { format = format }, text)
end

-- Link Attr [Inline] Target
function Renderer:Link (attributes, inlines, target) -- attributes, inlines, target
  local options = pandocAttributes(attributes)
  -- Target = (Url : Text, Title : Text)
  local uri, _ = table.unpack(target) -- uri, title (unused too?)
  options.src = uri
  local content = self:render(inlines)
  return createCommand("markdown:internal:link", options, content)
end

-- Image Attr [Inline] Target
function Renderer:Image (attributes, inlines, target) -- attributes, inlines, target
  local options = pandocAttributes(attributes)
  local content = self:render(inlines)
  -- Target = (Url : Text, Title : Text)
  local uri, _ = table.unpack(target)
  options.src = uri
  return createCommand("markdown:internal:image", options, content)
end

-- Note [Block]
function Renderer:Note (blocks)
  local content = self:render(blocks)
  return createCommand("markdown:internal:footnote", {}, content)
end

-- Span Attr [Inline]
function Renderer:Span (attributes, inlines)
  local options = pandocAttributes(attributes)
  local content = self:render(inlines)
  return createCommand("markdown:internal:span" , options, content)
end

local base = require("inputters.base")

local inputter = pl.class(base)
inputter._name = "pandocast"
inputter.order = 2

function inputter.appropriate (round, filename, doc)
  if round == 1 then
    return filename:match("pandoc$")
  elseif round == 2 then
    -- round 2 would be sniffing some initial file content, which is quite
    -- impossible in the general case for JSON (which may have been pretty-printed
    -- or whatever, so apart of an initial "{" there's probably not much we can
    -- say)
    return false
  elseif round == 3 then
    -- round 3 is an attempt at parsing...
    local has_json, json = pcall(require, "json.decode")
    if not has_json then
      -- we don't have json.decode, but other inputter might appropriate, so
      -- we can't decently error here.
      return false
    end
    local status, jsast = pcall(function () return json.decode(doc) end)
    -- JSON must have succeeded AND the resulting object must be a Pandoc AST,
    -- which we just check as having the 'pandoc-api-version' key.
    return status and type(jsast) == "table" and jsast['pandoc-api-version']
  end
  return false
end

function inputter:parse (doc)
  -- Load JSON parser:
  -- Luajson is LPEG-based, and lunajson is pure Lua without other
  -- dependencies. Prioritize the former for if available, otherwise
  -- fallback to lunajson, which we'll have in our dependencies.
  local has_json, json = pcall(require, "json.decode")
  if not has_json then
    has_json, json = pcall(require, "lunajson")
    if not has_json then
      SU.error("The pandocast inputter requires either luajson or lunajson to be available.")
    end
  end

  local jsast = json.decode(doc)

  local PANDOC_API_VERSION = jsast['pandoc-api-version']
  checkAstSemver(PANDOC_API_VERSION)

  local renderer = Renderer(self.options)
  local tree = renderer:render(jsast.blocks)

  -- The Markdown parsing returns a SILE AST.
  -- Wrap it in a document structure so we can just process it, and if at
  -- root level, load a default support class.
  tree = createCommand("document", { class = "markdown" }, tree)
  return { tree }
end

return inputter
