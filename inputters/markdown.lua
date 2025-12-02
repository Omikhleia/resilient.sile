--- Markdown native support for SILE
--
-- Using the lunamark Lua library for parsing.
--
-- @copyright License: MIT (c) 2022-2024 Omikhleia, Didier Willis
-- @module inputters.markdown
--
local utils = require("packages.markdown.utils")
local createCommand, createStructuredCommand
        = SU.ast.createCommand, SU.ast.createStructuredCommand

local function simpleCommandWrapper (name)
  -- Simple wrapper argound a SILE command
  return function (content)
    return createCommand(name, {}, content)
  end
end

-- A few mappings functions and tables

local listStyle = {
  Decimal = "arabic",
  UpperRoman = "Roman",
  LowerRoman = "roman",
  UpperAlpha = "Alpha",
  LowerAlpha = "alpha",
}
local listDelim = {
  OneParen = ")",
  Period = ".",
}

local function tableCellAlign (align)
  if align == 'l' then
    return 'left'
  elseif align == 'r' then
    return 'right'
  elseif align == 'c' then
    return 'center'
  else
    return 'default'
  end
end

local function extractLineBlockLevel (inlines)
  -- The indentation of line blocks is not really a first-class citizen:
  -- lunamark replaces the indentation spaces with U+00A0 (nbsp)
  -- and stacks them in the first inline.
  -- We remove them, and return the count.
  local f = inlines[1]
  local level = 0
  if f and type(f) == "string" then
    local line = f
    line = line:gsub("^[ ]+", function (match) -- Warning, U+00A0 here.
      level = luautf8.len(match)
      return ""
    end)
    if line == "" then -- and #inlines == 1 then
      inlines = table.remove(inlines, 1)
    else
      inlines[1] = line -- replace
    end
  end
  return level, inlines
end

-- Lunamark writer for SILE
-- Yay, direct lunamark AST ("ropes") conversion to SILE AST

local function SileAstWriter (writerOps, renderOps)
  local generic = require("lunamark.writer.generic")
  local writer = generic.new(writerOps or {})
  local shift_headings = SU.cast("integer", renderOps.shift_headings or 0)
  local parentmetadata = {}
  for key, val in pairs(renderOps) do
    local meta = key:match("^meta:(.*)")
    if meta then
      if meta:match("[%w_+-]+") then
        -- We don't use them in this renderer, but we can pass them through
        -- to embedded djot documents.
        parentmetadata[key] = val
      else
        SU.warn("Invalid metadata key is skipped: "..meta)
      end
    end
  end

  -- Simple one-to-one mappings between lunamark AST and SILE

  writer.note = simpleCommandWrapper("markdown:internal:footnote")
  writer.strong = simpleCommandWrapper("strong")
  writer.paragraph = simpleCommandWrapper("markdown:internal:paragraph")
  writer.code = simpleCommandWrapper("code")
  writer.emphasis = simpleCommandWrapper("em")
  writer.subscript = simpleCommandWrapper("textsubscript")
  writer.superscript = simpleCommandWrapper("textsuperscript")
  writer.blockquote = simpleCommandWrapper("markdown:internal:blockquote")
  writer.verbatim = simpleCommandWrapper("verbatim")
  writer.listitem = simpleCommandWrapper("item")
  writer.linebreak = simpleCommandWrapper("markdown:internal:hardbreak")
  writer.singlequoted = simpleCommandWrapper("singlequoted")
  writer.doublequoted = simpleCommandWrapper("doublequoted")

  -- More complex mapping cases

  writer.header = function (s, level, attr)
    local opts = attr or {} -- passthru (class and key-value pairs)
    opts.level = level + shift_headings
    return createCommand("markdown:internal:header", opts, s)
  end

  writer.hrule = function (separator)
    -- The argument is the (right-)trimmed hrule separator
    return createCommand("markdown:internal:hrule", { separator = separator })
  end

  writer.bulletlist = function (items)
    local contents = {}
    for i = 1, #items do contents[i] = writer.listitem(items[i]) end
    return createStructuredCommand("itemize", {}, contents)
  end

  writer.tasklist = function (items)
    local contents = {}
    for i = 1, #items do
      local bullet = (items[i][1] == "[X]") and "☑" or "☐"
      contents[i] = createCommand("item", { bullet = bullet }, items[i][2])
     end
    return createStructuredCommand("itemize", {}, contents)
  end

  writer.orderedlist = function (items, _, startnum, numstyle, numdelim) -- items, tight, ...
    local display = numstyle and listStyle[numstyle]
    local after = numdelim and listDelim[numdelim]
    local contents = {}
    for i= 1, #items do contents[i] = writer.listitem(items[i]) end
    return createStructuredCommand("enumerate", { start = startnum or 1, display = display, after = after }, contents)
  end

  writer.link = function (label, uri, _, attr) -- label, uri, title, attr
    local opts = attr or {} -- passthru (class and key-value pairs)
    opts.src = uri
    return createCommand("markdown:internal:link", opts, { label })
  end

  writer.image = function (label, src, _, attr) -- label, src, title, attr
    local opts = attr or {} -- passthru (class and key-value pairs)
    opts.src = src
    return createCommand("markdown:internal:image" , opts, label)
  end

  writer.span = function (content, attr)
    return createCommand("markdown:internal:span" , attr, content)
  end

  writer.strikeout = function (content)
    return createCommand("markdown:internal:span" , { class = "strike" }, content)
  end

  writer.div = function (content, attr)
    return createCommand("markdown:internal:div" , attr, content)
  end

  writer.fenced_code = function (content, infostring, attr)
    local opts = attr or { class = infostring }
    if utils.hasClass(opts, "djot") or utils.hasClass(opts, "markdown") then
      opts = pl.tablex.union(parentmetadata, opts)
      opts.shift_headings = shift_headings
    end
    return createCommand("markdown:internal:codeblock", opts, content)
  end

  writer.rawinline = function (content, format, _) -- content, format, attr
    return createCommand("markdown:internal:rawinline", { format = format }, content)
  end

  writer.rawblock = function (content, format, _) -- content, format, attr
    return createCommand("markdown:internal:rawblock", { format = format }, content)
  end

  writer.table = function (rows, caption) -- rows, caption
    -- caption is a text Str
    -- rows[1] has the headers
    -- rows[2] has the alignments (I know, it's weird...)
    -- then other rows follow
    local aligns = rows[2]
    local numberOfCols = #aligns
    local ptableRows = {}

    local headerCols = {}
    for j, column in ipairs(rows[1]) do
      local col = createCommand("cell", { valign="middle", halign = tableCellAlign(aligns[j]) }, column)
      headerCols[#headerCols+1] = col
    end
    ptableRows[#ptableRows+1] = createStructuredCommand("row", { background = "#eee" }, headerCols)

    for i = 3, #rows do
      local row = rows[i]
      local ptableCols = {}
      for j, column in ipairs(row) do
        local col = createCommand("cell", { valign = "middle", halign = tableCellAlign(aligns[j]) }, column)
        ptableCols[#ptableCols+1] = col
      end
      ptableRows[#ptableRows+1] = createStructuredCommand("row", {}, ptableCols)
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
    local ptable = createStructuredCommand("ptable", { header = true, cols = table.concat(cWidth, " ") }, ptableRows)

    local wrapped = caption and {
      ptable,
      createCommand("caption", {}, caption)
    } or { ptable }
    return createStructuredCommand("markdown:internal:captioned-table", {}, wrapped)
  end

  writer.definitionlist = function (items, _) -- items, tight
    local buffer = {}
    for _, item in ipairs(items) do
      buffer[#buffer + 1] = createStructuredCommand("markdown:internal:defn", {}, {
        createCommand("term", {}, item.term),
        createStructuredCommand("desc", {}, item.definitions)
      })
    end
    return createStructuredCommand("markdown:internal:paragraph", {}, buffer)
  end

  writer.lineblock = function (lines)
    local buffer = {}
    for _, inlines in ipairs(lines) do
      local level, currated_inlines = extractLineBlockLevel(inlines)
      -- Let's be typographically sound and use quad kerns rather than spaces for indentation
      local contents =  (level > 0) and {
       createCommand("kern", { width = level.."em" }),
        currated_inlines
      } or currated_inlines
      if #contents == 0 then
        buffer[#buffer+1] = createCommand("stanza", {})
      else
        buffer[#buffer+1] = createCommand("v", {}, contents)
      end
    end
    return createStructuredCommand("markdown:internal:lineblock", {}, buffer)
  end

  writer.inline_html = function (inlinehtml)
    return createCommand("markdown:internal:rawinline", { format = "html" }, inlinehtml)
  end

  writer.math = function (mathtype, text) -- first arg is "InlineMath" or "DisplayMath"
    local mode = mathtype == "DisplayMath" and "display" or "text"
    return createCommand("markdown:internal:math" , { mode = mode }, { text })
  end

  writer.naive_citations = function (rawcites)
    return utils.naiveCitations(rawcites)
  end

  -- Final AST conversion logic.
  --   The lunamark "AST" is made of "ropes":
  --     "A rope is an array whose elements may be ropes, strings, numbers,
  --     or functions."
  --   The default implementation flattens that to a string, so we override it,
  --   in order to extract the AST and convert it to the SILE AST.
  --
  --   The methods that were overridden above actually started to introduce SILE
  --   AST command structures in place of some ropes. Therefore, we now walk
  --   these "extended" ropes merge the output, flattened to some degree, into
  --   a final SILE AST that we can process.

  function writer.rope_to_output (rope)
    local function walk(node)
      local out
      local ropeType = type(node)

      if ropeType == "string" then
        -- We call the nbsp filtering very late: we cannot do it by overriding
        -- the writer.string() method, as some other enclosing nodes _expect_
        -- unprocessed U+00A0 characters (e.g. line blocks); other cannot
        -- contain structured commands (e.g. infostrings in code blocks).
        out = utils.nbspFilter(node)
      elseif ropeType == "table" then
        local elements = {}
        -- Recursively expand and the the node list
        for i = 1, #node do
          local child = walk(node[i])
          if type(child) == "string" then
            -- Assemble consecutive strings
            if type(elements[#elements]) == "string" then
              elements[#elements] = elements[#elements] .. child
            elseif #child > 0 then
              elements[#elements+1] = child
            end
            -- Empty strings are skipped
          else
            elements[#elements+1] = child
          end
        end
        -- Copy the key-value pairs, i.e. in our case a potential SILE command
        -- (with "command", "options", etc. fields)
        for key, value in pairs(node) do
          if type(key)=="string" then
            elements[key] = value
           end
        end
        out = elements
      elseif ropeType == "function" then
        out = walk(node())
      else
        -- Not sure when it actually occurs (not observed on some sample
        -- Markdown files), but the lunamark original util.rope_to_string()
        -- says it can.
        out = tonumber(node)
      end

      -- Pure array nestings can be simplified without impact,
      -- generating a smaller resulting AST (and usually with more string
      -- elements being reassembled)
      if type(out) == "table" and #out == 1 and not out.command then
        out = out[1]
      end
      return out
    end
    return walk(rope)
  end

  return writer
end

-- Custom syntax extension:
--   HorizontalRule extension: extracts the pattern (passes it to the writer).
--      There's quite a bit of boilerplate here for such a simple change,
--      the mere addition of a capture in lineof(), but we don't want to bother
--      the Lunamark folks with a non-standard interpretation.
--   Smart typography extension: Add prime and double prime recognition
--      after digits.
local lpeg = require("lpeg")
local parsers = {}
parsers.asterisk       = lpeg.P("*")
parsers.dash           = lpeg.P("-")
parsers.underscore     = lpeg.P("_")
parsers.spacechar      = lpeg.S("\t ")
parsers.space          = lpeg.P(" ")
parsers.optionalspace  = parsers.spacechar^0
parsers.leader         = parsers.space^-3
parsers.newline        = lpeg.P("\n")
parsers.blankline      = parsers.optionalspace
                       * parsers.newline / "\n"
parsers.digit          = lpeg.R("09")
parsers.lineof = function (c)
                   return (parsers.leader * lpeg.C((lpeg.P(c) * parsers.optionalspace)^3)
                          * parsers.newline * parsers.blankline^1)
                          / function(s) return s:gsub("%s*$", "") end
                 end

local function customSyntax (writer, options)
  return function (syntax)
    -- Re-create the horizontal rule syntax to use our modified lineof
    -- with a capture.
    syntax.HorizontalRule = (parsers.lineof(parsers.asterisk)
                            + parsers.lineof(parsers.dash)
                            + parsers.lineof(parsers.underscore)
                            ) / writer.hrule

    -- Extend the smart typography syntax to recognize primes and double primes
    -- after digits.
    if options.smart_primes then
      syntax.Smart = lpeg.P("\"") * lpeg.B(parsers.digit*1) / function ()
                        return "″" -- double primes
                      end
                   + lpeg.P("'") * lpeg.B(parsers.digit*1) / function ()
                        return "′" -- single prime
                      end
                   + syntax.Smart
    end
    -- Override the citation syntax to use our own raw citations writer
    syntax.Citations = lpeg.P("[")
                     * lpeg.C(lpeg.P("@") *(lpeg.P(1) - lpeg.P("]"))^1)
                     * lpeg.P("]")  / writer.naive_citations
    return syntax
  end
end

-- Now we have everything needed to implement a SILE inputter.

local base = require("inputters.base")

local inputter = pl.class(base)
inputter._name = "markdown"
inputter.order = 2

function inputter.appropriate (round, filename, _)
  if round == 1 then
    return filename:match("md$") or filename:match("markdown$")
  end
  -- round 2 would be sniffing some initial file content, which is quite
  -- impossible in the general case for markdown
  -- round 3 would be attempt at parsing, which we don't want to even do,
  -- as lunamark may certainly process any raw text file without complaining,
  -- though it won't meet expectations!
end

function inputter:parse (doc)
  local extensions = {
    smart = true,
    smart_primes = true,
    strikeout = true,
    subscript = true,
    superscript = true,
    definition_lists = true,
    notes = true,
    inline_notes = true,
    fenced_code_blocks = true,
    fenced_code_attributes = true,
    bracketed_spans = true,
    fenced_divs = true,
    raw_attribute = true,
    link_attributes = true,
    mark = true,
    startnum = true,
    fancy_lists = true,
    task_list = true,
    hash_enumerators = true,
    table_captions = true,
    pipe_tables = true,
    header_attributes = true,
    line_blocks = true,
    escaped_line_breaks = true,
    tex_math_dollars = true,
    citations = true,
  }
  for k, v in pairs(self.options) do
    -- Allow overriding known options
    -- (Lunamark has more options than that, but I haven't test disabling anything else,
    -- so let's be safer by not having them here for now.)
    if extensions[k] then
      extensions[k] = SU.boolean(v, true)
    end
  end

  local lunamark = require("lunamark")
  local reader = lunamark.reader.markdown
  local writer = SileAstWriter({
    layout = "minimize" -- The default layout is to output \n\n as inter-block separator
                        -- Let's cancel it completely, and insert our own \par where needed.
  }, self.options)

  extensions.alter_syntax = customSyntax(writer, extensions)

  local parse = reader.new(writer, extensions)
  local tree = parse(doc)
  -- The Markdown parsing returns a string or a SILE AST table.
  -- Wrap it in some document structure so we can just process it, and if at
  -- root level, load a default support class.
  tree = createCommand("document", { class = "markdown" }, tree)
  return { tree }
end

return inputter
