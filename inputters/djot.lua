--- Djot native inputter for SILE
--
-- Using the djot Lua library for parsing.
-- Reusing the common commands initially made for the "markdown" inputter/package.
--
-- @copyright License: MIT (c) 2023-2025 Omikhleia, Didier Willis
-- @module inputters.djot
--
local utils = require("packages.markdown.utils")
local createCommand, createStructuredCommand
        = SU.ast.createCommand, SU.ast.createStructuredCommand

local function node_pos (node)
  if not node._sp_ then
    local p = node.pos and node.pos[1]
    if not p then
      return nil
    end
    local lno, col, pos = p:match("^(%d+):(%d+):(%d+)$")
    node._sp_ = { lno = tonumber(lno), col = tonumber(col), pos = tonumber(pos) }
  end
  return node._sp_
end

-- Extend SILE's trace stack system
local djotFrame = pl.class(SILE.traceStack.defaultFrame)

function djotFrame:_init (node)
  self.file = SILE.currentlyProcessingFile
  self.node = node
  local sp = node_pos(node)
  if sp then
    self.lno = sp.lno or 0
    self.col = sp.col or 0
    self.pos = sp.pos or 0
  end
end

function djotFrame:__tostring ()
  return self.node.t
end

-- DJOT AST CONVERTER TO SILE AST

local djotast = require("djot.ast")

local Renderer = pl.class()

function Renderer:_init (options)
  self.references = {}
  self.footnotes = {}
  self.shift_headings = SU.cast("integer", options.shift_headings or 0)
  self.metadata = {}
  for key, val in pairs(options) do
    local meta = key:match("^meta:(.*)")
    if meta then
      if meta:match("[%w_+-]+") then
        self.metadata[meta] = val
      else
        SU.warn("Invalid metadata key is skipped: "..meta)
      end
    end
  end
  self.tight = false -- We do not use it currently, though!
end

function Renderer:render (doc)
  self.references = doc.references
  self.footnotes = doc.footnotes
  return self[doc.t](self, doc)
end

function Renderer:matchConditions(node)
  -- Djot extension: conditional symbols
  -- NOTE: We went for a quick hack in our modified Djot parser,
  -- having the conditions in the class attribute.
  -- Of course, it should be done in a more elegant way.
  if node.attr and node.attr.class then
    local conds_exist = {}
    local conds_notexist = {}
    local newclass = node.attr.class:gsub( "[?][%w_-]*", function(key)
      table.insert(conds_exist, key:sub(2))
      return ""
    end)
    -- newclass =
    newclass:gsub( "[!][%w_-]*", function(key)
      table.insert(conds_notexist, key:sub(2))
      return ""
    end)
    for _, cond in ipairs(conds_exist) do
      if not self.footnotes[":"..cond..":"] and not self.metadata[cond] then
        return false
      end
    end
    for _, cond in ipairs(conds_notexist) do
      if self.footnotes[":"..cond..":"] or self.metadata[cond] then
        return false
      end
    end
    -- We could avoid passing the conditions further:
    -- node.attr.class = newclass
    -- Have to check we correctly memoize symbol substitution, though.
  end
  return true
end

function Renderer:render_children (node)
  -- trap stack overflow
  local out = {}
  local ok, err = pcall(function ()
    if node.c and #node.c > 0 then
      local oldtight
      if node.tight ~= nil then
        oldtight = self.tight
        self.tight = node.tight
      end
      for i=1, #node.c do
        local child = node.c[i]
        if self:matchConditions(child) then
          local pId = SILE.traceStack:pushFrame(djotFrame(child))
          local content = self[child.t](self, child)
          -- Simplify outputs by collating strings
          if type(content) == "string" and type(out[#out]) == "string" then
            out[#out] = out[#out] .. content
          else
            -- Simplify out by removing empty elements
            if type(content) ~= "table" or content.command or #content > 1 then
              out[#out+1] = content
            elseif #content == 1 then
              -- Simplify out by removing useless grouping
              out[#out+1] = content[1]
            end
          end
          SILE.traceStack:pop(pId)
        end
      end
      if node.tight ~= nil then
        self.tight = oldtight
      end
    end
  end)
  if not ok then
    -- Here we shall not use SU.error...
    if err:find("stack overflow") then
      -- The HTML example had a warning here, but it is dubious
      -- that we can just try to ignore content.
      error("Djot content too deeply nested", 2)
    elseif err:find("paperSize") then
       -- HACK
       -- SILE 0.15.13 is still unimaginative how to avoid crashing the outputter
       -- and SU.error raises another error in the process.
      SILE.scratch.caughterror = true
      error("", 2)
    else
      error(err, 2) -- rethrow
    end
  end
  --  Simplify output by removing useless grouping
  if type(out) == "table" and #out == 1 and not out.command then
    out = out[1]
  end
  return out
end

function Renderer:doc (node)
  return self:render_children(node)
end

function Renderer:raw_block (node)
  return createCommand("markdown:internal:rawblock", { format = node.format }, node.s, node_pos(node))
end

function Renderer:para (node)
  if #node.c == 1 and node.c[1].t == "symbol" then
    -- Tweak the standalone symbol to be marked as "kind of" a block element.
    node.c[1]._standalone_ = true
  end

  local content = self:render_children(node)
  local pos = node_pos(node)
  -- interpret as a div when containing attributes
  if node.attr then
    return createCommand("markdown:internal:div", node.attr, content, pos)
  end
  return createCommand("markdown:internal:paragraph", {}, content, pos)
end

function Renderer:blockquote (node)
  local content = self:render_children(node)
  local pos = node_pos(node)
  local out
  if node.caption then
    -- Djot extension: caption supported on blockquotes
    local caption = self:render_children(node.caption)
    out = createStructuredCommand("markdown:internal:captioned-blockquote", node.attr or {}, {
      content,
      createCommand("caption", {}, caption)
    }, pos)
  else
    out = createCommand("markdown:internal:blockquote", node.attr or {}, content, pos)
  end
  if node.attr then
    -- Add a div when containing attributes
    return createCommand("markdown:internal:div", node.attr, out, pos)
  end
  return out
end

function Renderer:div (node)
  local options = node.attr or {}
  local content = self:render_children(node)
  local pos = node_pos(node)
  local out
  --- Djot extension: caption supported on div blocks
  out = createCommand("markdown:internal:div", options, content, pos)
  if node.caption then
    local caption = self:render_children(node.caption)
    out = createStructuredCommand("markdown:internal:captioned-figure", node.attr or {}, {
      out,
      createCommand("caption", {}, caption)
    }, pos)
  end
  return out
end

function Renderer:section (node)
  -- djot.lua differs from djot.js
  -- See https://github.com/jgm/djot/issues/213#issuecomment-1647755452
  -- A section is inserted when a header is found at the document level.
  -- The id is set on the section, not on the header.
  -- But attributes are set on the header, not on the section with djot.lua
  -- whereas they are set on the section with djot.js.
  self.sectionid = node.attr and node.attr.id
  local content = self:render_children(node)
  return content
end

function Renderer:heading (node)
  local options = node.attr or {}
  local content = self:render_children(node)
  -- See above:
  -- At document level, the id is set on the section.
  -- But in nested blocks (e.g. in divs), the id is set on the header.
  options.id = options.id or self.sectionid
  options.level = node.level + self.shift_headings
  return createCommand("markdown:internal:header", options, content, node_pos(node))
end

function Renderer:thematic_break (node)
  local options = node.attr or {}
  return createCommand("markdown:internal:thematicbreak", options, nil, node_pos(node))
end

function Renderer:code_block (node)
  local options = node.attr or {}
  options.class = node.lang and ((options.class and (options.class.." ") or "") .. node.lang) or options.class
  if utils.hasClass(options, "djot") or utils.hasClass(options, "markdown") then
    options.shift_headings = self.shift_headings
    self:resolveAllUserDefinedSymbols()
    -- Parent metadata just have a label xxx
    -- User-defined memoized metadata have the symbol (:xxx:) as key
    -- So we sort the keys to get the user-defined metadata first as overrides.
    for key, val in SU.sortedpairs(self.metadata) do
      local name = key:match("^:([%w_+-]+):$") or key -- remove leading and trailing colons
      if not options["meta:" .. name] then
        options["meta:" .. name] = val
      end
    end
  end
  local pos = node_pos(node)
  local out
  out = createCommand("markdown:internal:codeblock", options, node.s, pos)
  if node.caption then
    -- Potential Djot extension (but not yet -- explicit wrapping in a div block might
    -- be sufficient for now.
    SU.warn("Caption on code block is not supported (ignored)")
  end
  return out
end

function Renderer:table (node)
  local options = node.attr or {}
  if not node.c then
    SU.error("Table without content (should not occur)")
  end
  local pos = node_pos(node)
  -- extract caption, check rows
  local rows = {}
  local caption
  for _, v in ipairs(node.c) do
    if v.t == "caption" then
      caption = self:render_children(v)
    elseif v.t == "row" then
      rows[#rows+1] = v
    else
      SU.error("Unexpected element in table: "..v.t)
    end
  end
  node.c = rows

  local row = rows[1]
  local numberOfCols = #row.c
  local cWidth = {}
  for i = 1, numberOfCols do
    -- Currently we make all columns the same width, with the table taking
    -- a full line width. Well, nearly full: 99.9% to avoid 100% which
    -- causes issues in SILE flushed/centered environments, but this is
    -- deemed acceptable (hardly visible, and in most case we have some
    -- rounding anyway with the number format, so we aren't really making
    -- things worse).
    -- N.B. For future consideration: in Djot we could use a table attribute
    -- for specifying the target width. This would however require some
    -- changes to the ptable implementation, though...
    cWidth[i] = string.format("%.5f%%lw", 99.9 / numberOfCols)
  end
  local ptable = createStructuredCommand("ptable", {
     cols = table.concat(cWidth, " "),
     header = SU.boolean(row.head, false),
  }, self:render_children(node), pos)

  local wrapped = caption and {
    ptable,
    createCommand("caption", {}, caption, pos)
  } or { ptable }
  return createStructuredCommand("markdown:internal:captioned-table", options, wrapped, pos)
end

function Renderer:row (node)
  local options = {}
  local content = self:render_children(node)
  options.background = node.head and "#eee"
  return createStructuredCommand("row", options, content, node_pos(node))
end

function Renderer:cell (node)
  local options = {}
  local content = self:render_children(node)
  options.halign = node.align
  return createStructuredCommand("cell", options, content, node_pos(node))
end

function Renderer.caption (_, _)
  -- Extracted at processing, so we should not enter this method.
  SU.error("Caption rendering is not expected here.")
end

local listStyle = {
  ["1"] = "arabic",
  I = "Roman",
  i = "roman",
  A = "Alpha",
  a = "alpha",
}

function Renderer:list (node)
  local pos = node_pos(node)
  local sty = node.style
  if sty == "*" or sty == "+" or sty == "-" then
    local content = self:render_children(node)
    for i = 1, #content do
      if content[i].command ~= "item" then
        content[i] = createCommand("item", {}, content[i], pos)
      end
    end
    return createStructuredCommand("itemize", {}, content, pos)
  end

  if sty == "X" then
    local content = self:render_children(node)
    for i = 1, #content do
      if content[i].command ~= "item" then
        content[i] = createCommand("item", {}, content[i], pos)
      end
    end
    return createStructuredCommand("itemize", {}, content, pos)
  end

  if sty == ":" then
    local content = self:render_children(node)
    -- Kind of a hack: propagate Djot attributes to the defn (item) nodes
    -- This is not very cleverly done...
    if content.command then
      -- We have only one definition item so the AST got simplified
      content.options = node.attr or {}
    else
      -- Or we have a list of definition items...
      for _, v in ipairs(content) do
        if type(v) == "table" and v.command then
          v.options = node.attr or {}
        end
      end
    end
    return createCommand("markdown:internal:paragraph", {}, content, pos)
  end

  -- Enumerate
  local a = node.style:sub(1,1)
  local b = node.style:sub(-1)
  local options = {
    start = node.start,
  }
  if a:match("%p") then
    options.before = a
  end
  if b:match("%p") then
    options.after = b
  end
  local list_type = node.style:gsub("%p", "")
  options.display = listStyle[list_type]

  local content = self:render_children(node)
  for i = 1, #content do
    if content[i].command ~= "item" then
      content[i] = createCommand("item", {}, content[i], pos)
    end
  end
  return createStructuredCommand("enumerate", options, content, pos)
end

function Renderer:list_item (node)
  local options = {}
  local bullet = ((node.checkbox == "checked") and "☑")
    or ((node.checkbox == "unchecked") and "☐")
  options.bullet = bullet

  local content = self:render_children(node)
  return createCommand("item", options, content, node_pos(node))
end

function Renderer:term (node)
  local content = self:render_children(node)
  return createCommand("term", {}, content, node_pos(node))
end

function Renderer:definition (node)
  local content = self:render_children(node)
  return createCommand("desc", {}, content, node_pos(node))
end

function Renderer:definition_list_item (node)
  -- See the list renderer, we'll override options on defn nodes from
  -- Djot attributes on the whole list.
  return createStructuredCommand("markdown:internal:defn", {}, self:render_children(node))
end

function Renderer.reference_definition (_)
  SU.warn("Reference definition issue")
  return "¤(def ref)" -- TODO, I didn't get why the HTML renderer had this.
end

function Renderer:footnote_reference (node)
  local label = node.s
  local node_footnote = self.footnotes[label]
  if not node_footnote then
    SU.error("Failure to find footnote '"..label.."'")
  end
  local content = self:render_children(node_footnote)
  local options = node_footnote.attr or {}
  options.id = options.id or label -- use note label as id if not specified
  return createCommand("markdown:internal:footnote", options, content, node_pos(node))
end

function Renderer:raw_inline (node)
  return createCommand("markdown:internal:rawinline", { format = node.format }, node.s, node_pos(node))
end

function Renderer:str (node)
  if node.attr then
    -- add a span, if needed, to contain attribute on a bare string:
    return createCommand("markdown:internal:span", node.attr, node.s, node_pos(node))
  end
  return node.s
end

function Renderer.softbreak (_)
  return " "
end

function Renderer.hardbreak (_)
  return createCommand("markdown:internal:hardbreak")
end

function Renderer:nbsp (node)
  local options = node.attr or {}
  return createCommand("markdown:internal:nbsp", options, nil, node_pos(node))
end

function Renderer:verbatim (node)
  -- TODO options/attrs... but we need more work on pandocast/markdown and a replacement for \code
  local options = {}
  return createCommand("code", options, node.s, node_pos(node))
end

function Renderer:link (node)
  local content = self:render_children(node)
  local options = djotast.new_attributes{}
  if node.reference then
    local ref = self.references[node.reference]
    if ref then
      if ref.attr then
        djotast.copy_attributes(options, ref.attr)
      end
      djotast.insert_attribute(options, "src", ref.destination)
    end
  elseif node.destination then
    djotast.insert_attribute(options, "src", node.destination)
  end
  -- link's attributes override reference's:
  djotast.copy_attributes(options, node.attr)
  return createCommand("markdown:internal:link", options, content, node_pos(node))
end

Renderer.url = Renderer.link

Renderer.email = Renderer.link

function Renderer:image (node)
  local content = self:render_children(node)
  local options = djotast.new_attributes{}
  if node.reference then
    local ref = self.references[node.reference]
    if ref then
      if ref.attr then
        djotast.copy_attributes(options, ref.attr)
      end
      djotast.insert_attribute(options, "src", ref.destination)
    end
  elseif node.destination then
    djotast.insert_attribute(options, "src", node.destination)
  end
  -- image's attributes override reference's:
  djotast.copy_attributes(options, node.attr)
  return createCommand("markdown:internal:image", options, content, node_pos(node))
end

function Renderer:span (node)
  local options = node.attr or {}
  local content = self:render_children(node)
  return createCommand("markdown:internal:span", options, content, node_pos(node))
end

function Renderer:mark (node)
  local options = node.attr or {}
  local content = self:render_children(node)
  djotast.insert_attribute(options, "class", "mark")
  return createCommand("markdown:internal:span", options, content, node_pos(node))
end

function Renderer:insert (node)
  local options = node.attr or {}
  local content = self:render_children(node)
  djotast.insert_attribute(options, "class", "inserted")
  return createCommand("markdown:internal:span", options, content, node_pos(node))
end

function Renderer:delete (node)
  local options = node.attr or {}
  local content = self:render_children(node)
  djotast.insert_attribute(options, "class", "deleted")
  return createCommand("markdown:internal:span", options, content, node_pos(node))
end

local function extractAttrValue (attr, key)
  if not attr then
    return nil, false
  end
  local value = attr[key]
  attr[key] = nil
  local n = 0
  for _ in pairs(attr) do
    n = n + 1
  end
  return value, n > 0
end

function Renderer:subscript (node)
  local content = self:render_children(node)
  local pos = node_pos(node)
  local fake, hasOtherAttrs = extractAttrValue(node.attr, "fake")
  local out = createCommand("textsubscript", { fake = fake }, content, pos)
  if hasOtherAttrs then
    -- Add a span when containing other attributes
    return createCommand("markdown:internal:span", node.attr, out, pos)
  end
  return out
end

function Renderer:superscript (node)
  local content = self:render_children(node)
  local pos = node_pos(node)
  local fake, hasOtherAttrs = extractAttrValue(node.attr, "fake")
  local out = createCommand("textsuperscript", { fake = fake }, content, pos)
  if hasOtherAttrs then
    -- Add a span when containing other attributes
    return createCommand("markdown:internal:span", node.attr, out, pos)
  end
  return out
end

function Renderer:emph (node)
  local content = self:render_children(node)
  local pos = node_pos(node)
  if node.attr then
    -- Add a span for attributes
    -- Applied first before the font change, so that font-specific attributes
    -- are applied in the right context (e.g. .underline)
    content = createCommand("markdown:internal:span", node.attr, content, pos)
  end
  return createCommand("em", {}, content, pos)
end

function Renderer:strong (node)
  local content = self:render_children(node)
  local pos = node_pos(node)
  if node.attr then
    -- Add a span for attributes
    -- Applied first before the font change, so that font-specific attributes
    -- are applied in the right context (e.g. .underline)
    content = createCommand("markdown:internal:span", node.attr, content, pos)
  end
  return createCommand("strong", {}, content, pos)
end

function Renderer:double_quoted (node)
  local content = self:render_children(node)
  local pos = node_pos(node)
  content = createCommand("doublequoted", {}, content, pos)
  if node.attr then
    -- Add a span for attributes
    -- Applied after, so as to encompass the quotes.
    -- That's probably the expectation, so e.g. "text"{lang=fr} will use French
    -- primary quotations marks.
    content = createCommand("markdown:internal:span", node.attr, content, pos)
  end
  return content
end

function Renderer:single_quoted (node)
  local content = self:render_children(node)
  local pos = node_pos(node)
  content = createCommand("singlequoted", {}, content, pos)
  if node.attr then
    -- Add a span for attributes
    -- Applied after, so as to encompass the quotes.
    -- That's probably the expectation, so e.g. 'text'{lang=fr} will use French
    -- secondary quotations marks.
    content = createCommand("markdown:internal:span", node.attr, content, pos)
  end
  return content
end

function Renderer.left_double_quote (_)
  return("“")
end

function Renderer.right_double_quote (_)
  return("”")
end

function Renderer.left_single_quote (_)
  return("‘")
end

function Renderer.right_single_quote (_)
  return("’")
end

function Renderer.ellipses (_)
  return("…")
end

function Renderer.em_dash (_)
  return("—")
end

function Renderer.en_dash (_)
  return("–")
end

function Renderer:getUserDefinedSymbol (label, node_fake_metadata)
  local content
  if self.metadata[label] then -- use memoized
    content = self.metadata[label]
  else
    if #node_fake_metadata.c == 1 and node_fake_metadata.c[1].t == "para" then
      -- Skip a single para node.
      content = self:render_children(node_fake_metadata.c[1])
      if type(content) == "table" then content._single_ = true end
    else
      content = self:render_children(node_fake_metadata)
    end
    self.metadata[label] = content -- memoize
  end
  return content
end

function Renderer:resolveAllUserDefinedSymbols ()
  -- Ensure all fake footnotes are rendered and memoized, even unused ones.
  for label, node_fake_metadata in pairs(self.footnotes) do
    if label:match("^:([%w_+-]+):$") then
      self:getUserDefinedSymbol(label, node_fake_metadata)
    end
  end
end

function Renderer:symbol (node)
  -- Let's first look at fake footnotes to resolve the symbol.
  -- We just added unforeseen templating and recursive variable substitution to Djot.
  local label = ":" .. node.alias .. ":"
  local node_fake_metadata = self.footnotes[label]

  if node_fake_metadata then
    if #node_fake_metadata.c > 1 and not node._standalone_ then
      SU.error("Cannot use multi-paragraph metadata "..label.." as inline content")
    end
    local content = self:getUserDefinedSymbol(label, node_fake_metadata)
    if node.attr then
      if type(content) ~= "table" or content._single_ or not node._standalone_ then
        -- Add a span for attributes on the inline variant.
        content = createCommand("markdown:internal:span", node.attr, content, node_pos(node))
      else
        -- Those should rather come from the paragraph
        SU.warn("Attributes ignored on block-like symbol '" .. node.alias .. "'")
      end
    end
    return content
  else
    -- Let's then look for metadata passed to the renderer
    if self.metadata[node.alias] then
      local text = self.metadata[node.alias]
      if node.attr then
        -- Add a span for attributes
        return createCommand("markdown:internal:span", node.attr, text, node_pos(node))
      end
      return text
    end
    -- Not a metadata symbol, pass our internal properties and delegate
    local options = node.attr or {}
    options._symbol_ = node.alias
    options._standalone_ = node._standalone_
    return createCommand("markdown:internal:symbol", options, nil, node_pos(node))
  end
end

function Renderer:math (node)
  local options = node.attr or {}
  local mode = "text"
  -- Note that djot.lua sets the type of math in the class attribute.
  -- Recent versions of Djot.js use a first-order AST node instead.
  if string.find(node.attr.class, "display") then
    mode = "display"
  end
  options.mode = mode
  return createCommand("markdown:internal:math", options, { node.s }, node_pos(node))
end

function Renderer:naive_citations (node)
  local pos = node_pos(node)
  return utils.naiveCitations(node.s, pos)
end

-- SILE INPUTTER LOGIC

local base = require("inputters.base")

local inputter = pl.class(base)
inputter._name = "djot"
inputter.order = 2

function inputter.appropriate (round, filename, _)
  if round == 1 then
    return filename:match("dj$")
  end
  -- No other round supported...
  return false
end

function inputter:_loadFilter (name, env)
  -- Resolve the Lua file name in the same way as SILE for documents in the user tree.
  local qname = name:match("%.lua$") and name or (name .. ".lua")
  local filename = SILE.resolveFile(qname)
  if filename then
    local filter, err = utils.sandboxedLoadfile(filename, env)
    if not filter then
      SU.error("Failure loading filter '".. name .. "': " .. err)
    end
    if #filter == 0 then
      -- Just a single filter.
      -- (The Djot filter logic expects a list of filters applied in sequence.)
      filter = { filter }
    end
    return filter
  end
  SU.error("Cannot find filter '" .. name .. "'")
end

function inputter:parse (doc)
  local djot = require("djot")
  local djast = djot.parse(doc, true, function (warning)
    local text = doc:sub(1, warning.pos)
    local ep = luautf8.len(text) -- byte to utf8 position
    local sp = ep
    while sp > ep - 16 do -- at most 16 characters...
      local current = luautf8.sub(doc, sp, sp)
      if current:match("[\n\r]") then
        break -- ...on same line
      end
      sp = sp - 1
    end
    local snippet = luautf8.sub(doc, sp + 1, ep)
    SU.warn(warning.message .. " near [[…" .. snippet .. "]]")
  end)

  local fname = self.options.filter
  if fname then
    if type(fname) ~= "string" then
      SU.error("The 'filter' option to the Djot inputter must be a string")
    end
    local filter = self:_loadFilter(fname, {
      -- Allow Djot AST manipulations in the filter environment.
      djot = {
        ast = {
          insert_attribute = djot.ast.insert_attribute,
          copy_attributes = djot.ast.copy_attributes,
          new_attributes = djot.ast.new_attributes,
          new_node = djot.ast.new_node,
          add_child = djot.ast.add_child,
          has_children = djot.ast.has_children,
        }
      }
    })
    djot.filter.apply_filter(djast, filter)
  end

  local renderer = Renderer(self.options, doc)
  local tree = renderer:render(djast)

  -- The "writer" returns a SILE AST.
  -- Wrap it in a document structure so we can just process it, and if at
  -- root level, load a (default) support class.
  tree = createCommand("document", { class = "markdown" }, tree)
  return { tree }
end

return inputter
