--
-- A style package for SILE
-- License: MIT
-- 2021-2023, Didier Willis
--
local base = require("packages.base")

local package = pl.class(base)
package._name = "resilient.styles"

local hboxer = require("resilient-compat.hboxing") -- Compatibility hack/shim

local function interwordSpace ()
  return SILE.shaper:measureSpace(SILE.font.loadDefaults({}))
end

local function castKern (kern)
  if type(kern) == "string" then
    local value, rest = kern:match("^(%d*)iwsp[ ]*(.*)$")
    if value then
      if rest ~= "" then SU.error("Could not parse kern '"..kern.."'") end
      return (tonumber(value) or 1) * interwordSpace()
    end
  end
  return SU.cast("length", kern)
end

function package:_init (options)
  base._init(self, options)
  self.class:registerHook("finish", self.writeStyles)

  -- Numeric space (a.k.a. figure space) unit
  local numsp = SU.utf8charfromcodepoint("U+2007")
  SILE.registerUnit("nspc", {
    relative = true,
    definition = function (value)
      return value * SILE.shaper:measureChar(numsp).width
    end
  })

  -- Thin space unit, as 1/2 fixed inter-word space
  SILE.registerUnit("thsp", {
    relative = true,
    definition = function (value)
      return value * 0.5 * interwordSpace()
    end
  })
end

-- local function table_print_value (value, indent, done)
--   indent = indent or 0
--   done = done or {}
--   if type(value) == "table" and not done [value] then
--     done [value] = true

--     local list = {}
--     for key in pairs (value) do
--       list[#list + 1] = key
--     end
--     table.sort(list, function(a, b) return tostring(a) < tostring(b) end)
--     local last = list[#list]

--     local rep = "\n"
--     local comma
--     for _, key in ipairs (list) do
--       -- if key == last then
--       --   comma = ''
--       -- else
--       --   comma = ','
--       -- end
--       local keyRep
--       if type(key) == "number" then
--         keyRep = key
--       else
--         keyRep = tostring(key) -- string.format("%q", tostring(key))
--       end
--       rep = rep .. string.format(
--         "%s%s: %s\n",
--         string.rep(" ", indent + 2),
--         keyRep,
--         table_print_value(value[key], indent + 2, done)
--        -- comma
--       )
--     end

--     --rep = rep .. string.rep(" ", indent) -- indent it
--     rep = rep .. ""

--     done[value] = false
--     return rep
--   elseif type(value) == "string" then
--     return string.format("%q", value)
--   else
--     return tostring(value)
--   end
-- end

function package.writeStyles (_)
  local stydata = pl.pretty.write(SILE.scratch.styles)
  -- table_print_value(SILE.scratch.styles.specs)
  local styfile, err = io.open(SILE.masterFilename .. '.sty', "w")
  if not styfile then return SU.error(err) end
  styfile:write(stydata)
  styfile:close()
end

SILE.scratch.styles = {
  -- Actual style specifications will go there (see defineStyle etc.)
  specs = {},
  -- Known aligns options, with the command implementing them.
  -- Users can register extra options in this table.
  alignments = {
    center = "center",
    left = "raggedright",
    right = "raggedleft",
    -- be friendly with users...
    raggedright = "raggedright",
    raggedleft = "raggedleft",
  },
  -- Known skip options.
  -- Users can add register custom skips there.
  skips = {
    smallskip = SILE.settings:get("plain.smallskipamount"),
    medskip = SILE.settings:get("plain.medskipamount"),
    bigskip = SILE.settings:get("plain.bigskipamount"),
  },
  -- Known position options, with the command implementing them
  -- Users can register extra options in this table.
  positions = {
    super = "textsuperscript",
    sub = "textsubscript",
  }
}

-- programmatically define a style
-- optional origin allows tracking e.g which package declared that style.
function package.defineStyle (_, name, opts, styledef, origin)
  SILE.scratch.styles.specs[name] = { inherit = opts.inherit, style = styledef, origin = origin }
end

-- merge two tables.
-- It turns out that pl.tablex.union does not recurse into the table,
-- so let's do it the proper way.
-- N.B. modifies t1 (and t2 wins on leaves existing in both)
local function recursiveTableMerge(t1, t2)
  for k, v in pairs(t2) do
    if (type(v) == "table") and (type(t1[k]) == "table") then
      recursiveTableMerge(t1[k], t2[k])
    else
      t1[k] = v
    end
  end
end

-- resolve a style (incl. inherited fields)

function package:resolveStyle (name, discardable)
  local stylespec = SILE.scratch.styles.specs[name]
  if not stylespec then
    if not SU.boolean(discardable, false) then SU.error("Style '"..name.."' does not exist") end
    return {}
  end

  if stylespec.inherit then
    local inherited = self:resolveStyle(stylespec.inherit, discardable)
    -- Deep merging the specification options
    local res = pl.tablex.deepcopy(inherited)
    recursiveTableMerge(res, stylespec.style)
    return res
  end
  return stylespec.style
end

-- human-readable specification for debug (text)
local function dumpOptions(options)
  local opts = {}
  for k, v in pairs(options) do
    opts[#opts+1] = k.."="..v
  end
  return table.concat(opts, ", ")
end
function package.dumpStyle (_, name)
  local stylespec = SILE.scratch.styles.specs[name]
  if not stylespec then return "(undefined)" end

  local desc = {}
  for k, v in pairs(stylespec.style) do
    desc[#desc+1] = k .. "[" .. dumpOptions(v).."]"
  end
  local textspec = table.concat(desc, ", ")
  if stylespec.inherit then
    if #textspec > 0 then
      textspec = stylespec.inherit.." > "..textspec
    else
      textspec = "< "..stylespec.inherit
    end
  end
  return textspec
end

function package:registerCommands ()
  self:registerCommand("style:font", function (options, content)
    local size = tonumber(options.size)
    local opts = pl.tablex.copy(options) -- shallow copy
    if size then
      opts.size = SILE.settings:get("font.size") + size
    end

    SILE.call("font", opts, content)
  end, "Applies a font, with additional support for relative sizes.")

  self:registerCommand("style:define", function (options, content)
    local name = SU.required(options, "name", "style:define")
    if options.inherit and SILE.scratch.styles.specs[options.inherit] == nil then
      SU.error("Unknown inherited named style '" .. options.inherit .. "'.")
    end
    if options.inherit and options.inherit == options.name then
      SU.error("Named style '" .. options.name .. "' cannot inherit itself.")
    end
    SILE.scratch.styles.specs[name] = { inherit = options.inherit, style = {} }
    for i=1, #content do
      if type(content[i]) == "table" and content[i].command then
          SILE.scratch.styles.specs[name].style[content[i].command] = content[i].options
      end
    end
  end, "Defines a named style.")

  -- Very naive cascading...
  local styleForProperties = function (style, content)
    if style.properties and style.properties.position and style.properties.position ~= "normal" then
      local positionCommand = SILE.scratch.styles.positions[style.properties.position]
      if not positionCommand then
        SU.error("Invalid style position '"..style.position.position.."'")
      end
      SILE.call(positionCommand, {}, content)
    else
      SILE.process(content)
    end
  end
  local styleForColor = function (style, content)
    if style.color then
      SILE.call("color", style.color, function ()
        styleForProperties(style, content)
      end)
    else
      styleForProperties(style, content)
    end
  end
  local styleForFont = function (style, content)
    if style.font then
      SILE.call("style:font", style.font, function ()
        styleForColor(style, content)
      end)
    else
      styleForColor(style, content)
    end
  end

  local styleForSkip = function (skip, vbreak)
    local b = SU.boolean(vbreak, true)
    if skip then
      local vglue = SILE.scratch.styles.skips[skip] or SU.cast("vglue", skip)
      if not b then SILE.call("novbreak") end
      SILE.typesetter:pushExplicitVglue(vglue)
    end
    if not b then SILE.call("novbreak") end
  end

  local styleForAlignment = function (style, content, breakafter)
    if style.paragraph and style.paragraph.align then
      if style.paragraph.align and style.paragraph.align ~= "justify" then
        local alignCommand = SILE.scratch.styles.alignments[style.paragraph.align]
        if not alignCommand then
          SU.error("Invalid paragraph style alignment '"..style.paragraph.align.."'")
        end
        if not breakafter then SILE.call("novbreak") end
        SILE.typesetter:leaveHmode()
        -- Here we must apply the font, then the alignement, so that line heights are
        -- correct even on the last paragraph. But the color introduces hboxes so
        -- must be applied last, no to cause havoc with the noindent/indent and
        -- centering etc. environments
        if style.font then
          SILE.call("style:font", style.font, function ()
            SILE.call(alignCommand, {}, function ()
              styleForColor(style, content)
              if not breakafter then SILE.call("novbreak") end
            end)
          end)
        else
          SILE.call(alignCommand, {}, function ()
            styleForColor(style, content)
            if not breakafter then SILE.call("novbreak") end
          end)
        end
      else
        styleForFont(style, content)
        if not breakafter then SILE.call("novbreak") end
        -- NOTE: SILE.call("par") would cause a parskip to be inserted.
        -- Not really sure whether we expect this here or not.
        SILE.typesetter:leaveHmode()
      end
    else
      styleForFont(style, content)
    end
  end


  -- APPLY A CHARACTER STYLE

  self:registerCommand("style:apply", function (options, content)
    local name = SU.required(options, "name", "style:apply")
    local styledef = self:resolveStyle(name, options.discardable)

    styleForFont(styledef, content)
  end, "Applies a named style to the content.")

  -- APPLY A PARAGRAPH STYLE

  self:registerCommand("style:apply:paragraph", function (options, content)
    local name = SU.required(options, "name", "style:apply:paragraph")
    local styledef = self:resolveStyle(name, options.discardable)
    local parSty = styledef.paragraph

    if parSty then
      local bb = SU.boolean(parSty.breakbefore, true)
      if #SILE.typesetter.state.nodes then
        if not bb then SILE.call("novbreak") end
        SILE.typesetter:leaveHmode()
      end
      styleForSkip(parSty.skipbefore, parSty.breakbefore)
      if SU.boolean(parSty.indentbefore, true) then
        SILE.call("indent")
      else
        SILE.call("noindent")
      end
    end

    local ba = not parSty and true or SU.boolean(parSty.breakafter, true)
    styleForAlignment(styledef, content, ba)

    if parSty then
      if not ba then SILE.call("novbreak") end
      -- NOTE: SILE.call("par") would cause a parskip to be inserted.
      -- Not really sure whether we expect this here or not.
      SILE.typesetter:leaveHmode()
      styleForSkip(parSty.skipafter, parSty.breakafter)
      if SU.boolean(parSty.indentafter, true) then
        SILE.call("indent")
      else
        SILE.call("noindent")
      end
    end
  end, "Applies the paragraph style entirely.")

  -- NUMBER STYLE

  self:registerCommand("style:apply:number", function (options, _)
    local name = SU.required(options, "name", "style:apply:number")
    local text = SU.required(options, "text", "style:apply:number")
    local styledef = self:resolveStyle(name, options.discardable)

    local numSty = styledef.numbering
    if not numSty then
      SILE.call("style:apply", { name = name }, { text })
      return -- Done (not a numbering style)
    end

    local beforetext = ""
    local aftertext = ""
    local beforekern, afterkern
    if numSty.before then
      beforetext = numSty.before.text or ""
      beforekern = numSty.before.kern and castKern(numSty.before.kern)
    end
    if numSty.after then
      aftertext = numSty.after.text or ""
      afterkern = numSty.after.kern and castKern(numSty.after.kern)
    end
    text = beforetext .. text .. aftertext

    -- If the kerning space is positive, it should correspond to the space inserted
    -- after the number.
    -- If negative, the text should be indented by that amount, with the
    -- number left-aligned in the available space.
    if beforekern and beforekern:tonumber() < 0 then
      -- IMPLEMENTATION NOTE / HACK / FRAGILE
      -- SILE's behavior with a hbox occuring as very first element of a line
      -- is plain weird. The width of the box is "adjusted" with respect to
      -- the parindent, it seems.
      -- FIXME So we need to fix it here for the two cases (i.e.) in a text flow,
      -- and not only at the start of a paragraph!!!!
      local hbox = hboxer.makeHbox(function ()
        SILE.call("style:apply", { name = name }, { text })
      end)
      local remainingSpace = hbox.width < 0 and -hbox.width or -beforekern:absolute() - hbox.width

      -- We want at least the space of a figure digit between the number
      -- and the text.
      if remainingSpace:tonumber() - SILE.length("1nspc"):absolute() <= 0 then
        -- It's not the case, the numbergoes beyond the available space.
        -- So add a fixed interword space after it.
        SILE.call("style:apply", { name = name }, { text })
        if afterkern then
          SILE.call("kern", { width = afterkern })
        end
      else
        -- It's the case, add the remaining space after the number, so
        -- everything is aligned.
        SILE.call("style:apply", { name = name }, { text })
        SILE.call("kern", { width = remainingSpace })
      end
    else
      if beforekern then
        SILE.call("kern", { width = beforekern })
      end
      SILE.call("style:apply", { name = name }, { text })
      if beforekern then
        SILE.call("kern", { width = afterkern })
      end
    end
  end, "Applies the number style.")

  -- STYLE REDEFINITION

  self:registerCommand("style:redefine", function (options, content)
    SU.required(options, "name", "style:redefined")

    if options.as then
      if options.as == options.name then
        SU.error("Style '" .. options.name .. "' should not be redefined as itself.")
      end

      -- Case: \style:redefine[name=style-name, as=saved-style-name]
      if SILE.scratch.styles.specs[options.as] ~= nil then
        SU.error("Style '" .. options.as .. "' would be overwritten.") -- Let's forbid it for now.
      end
      local sty = SILE.scratch.styles.specs[options.name]
      if sty == nil then
        SU.error("Style '" .. options.name .. "' does not exist!")
      end
      SILE.scratch.styles.specs[options.as] = sty

      -- Sub-case: \style:redefine[name=style-name, as=saved-style-name, inherit=true/false]{content}
      -- TODO We could accept another name in the inherit here? Use case?
      if content and (type(content) ~= "table" or #content ~= 0) then
        SILE.call("style:define", { name = options.name, inherit = SU.boolean(options.inherit, false) and options.as }, content)
      end
    elseif options.from then
      if options.from == options.name then
        SU.error("Style '" .. options.name .. "' should not be restored from itself, ignoring.")
      end

      -- Case \style:redefine[name=style-name, from=saved-style-name]
      if content and (type(content) ~= "table" or #content ~= 0) then
        SU.warn("Extraneous content in '" .. options.name .. "' is ignored.")
      end
      local sty = SILE.scratch.styles.specs[options.from]
      if sty == nil then
        SU.error("Style '" .. options.from .. "' does not exist!")
      end
      SILE.scratch.styles.specs[options.name] = sty
      SILE.scratch.styles.specs[options.from] = nil
    else
      SU.error("Style redefinition needs a 'as' or 'from' parameter.")
    end
  end, "Redefines a style saving the old version with another name, or restores it.")

  -- DEBUG OR DOCUMENTATION

  self:registerCommand("style:show", function (options, _)
    local name = SU.required(options, "name", "style:show")

    SILE.typesetter:typeset(self:dumpStyle(name))
  end, "Ouputs a textual (human-readable) description of a named style.")
end

package.documentation = [[\begin{document}
\use[module=packages.color]
\use[module=packages.unichar]
\use[module=packages.resilient.lists]

The \autodoc:package{resilient.styles} package aims at easily defining “styling specifications”.
It is intended to be used by other packages or classes, rather than directly—though
users might of course use the commands provided herein to customize some styling
definitions according to their needs.

How can one customize the various SILE environments they use in their writings?
For instance, in order to apply a different font or even a color to section
titles, a specific rendering for some entry levels in a table of contents and different
vertical skips here or there? They have several ways, already:

\begin{itemize}
\item{The implementation might provide settings that they can tune.}
\item{The implementation might be kind enough to provide a few “hooks” that they can change.}
\item{Otherwise, they have no other solution but digging into the class or package source code
  and rewrite the impacted commands, with the risk that they will not get updates, fixes and
  changes if the original implementation is modified in a later release.}
\end{itemize}

The last solution is clearly not satisfying. The first too, is unlikely, as class
and package authors cannot decidely expose everything in settings (which are not really
provided, one could even argue, for that purpose). Most “legacy” packages and classes
therefore rely on hooks. This degraded solution, however, may raise several concerns.
Something may seem wrong (though of course it is a matter of taste and could be debated).

\begin{enumerate}
\item{Many commands have “font hooks” indeed, with varying implementations,
    such as \autodoc:environment[check=false]{pullquote:font} and
    \autodoc:environment[check=false]{book:right-running-head-font} to quote
    just a few. None of these seem to have the same type of name. Their scope too is not
    always clear. But what if one also wants, for instance, to specify a color?
    Of course, in many cases, the hook could be redefined to apply that wanted color
    to the content… But, er, isn’t it called \code{…font}? Something looks amiss.}
\item{Those hooks often have fixed definitions, e.g. footnote text at 9pt, chapter heading
  at 22pt, etc. This doesn’t depend on the document main font size. LaTeX, years before,
  was only a bit better here, defining different relative sizes (but assuming a book is
  always typeset in 10pt, 11pt or 12pt).}
\item{Many commands, say book sectioning, rely on hard-coded vertical skips. But what if
  one wants a different vertical spacing? Two solutions come to mind, either redefining
  the relevant commands (say \autodoc:command[check=false]{\chapter}), but we noted the flaws of that
  method, or temporarily redefining the skips (say, \autodoc:command{\bigskip})… In a way,
  it all sounds very clumsy, cumbersome, somehow \em{ad hoc}, and… here, LaTeX-like.
  Which is not necessarily wrong (there is no offense intended here), but why not try
  a different approach?}
\end{enumerate}

Indeed, \em{why not try a different approach}. Actually, this is what most modern
word-processing software have been doing for a while, be it Microsoft Word or Libre/OpenOffice
and cognates… They all introduce the concept of “styles”, in actually three forms at
least: character styles, paragraph styles and page styles; But also frame styles,
list styles and table styles, to list a few others. This package is an attempt at
implementing such ideas, or a subset of them, in SILE. We do not intend to cover
all the inventory of features provided in these software via styles.
First, because some of them already have matching mechanisms, or even of a superior
design, in SILE. Page masters, for instances, are a neat concept, and we do not
really need to address them differently. This implementation therefore focuses
on some practical use cases. The styling paradigm proposed here has two aims:

\begin{itemize}
\item{Avoid programmable hooks as much as possible,}
\item{Replace them with a formal abstraction that can be shared between implementations.}
\end{itemize}

% We will even use our own fancy paragraph style for internal sectioning below.
\style:define[name=internal-sectioning]{
    \font[style=italic]
    \paragraph[skipbefore=smallskip, skipafter=smallskip, breakafter=false]
}
\define[command=P]{\style:apply:paragraph[name=internal-sectioning]{\process}}

\P{Regular styles.}

To define a (character) style, one uses the following syntax (with any of the internal
elements being optional):

\begin{codes}
\\style:define[name=\doc:args{name}]\{
\par\quad\\font[\doc:args{font specification}]
\par\quad\\color[color=\doc:args{color}]
\par\quad\\properties[position=\doc:args{normal|super|sub}]
\par\}
\end{codes}

\style:define[name=style@example]{
    \font[family=Libertinus Serif, features=+smcp, style=italic]
    \color[color=blue]
}

Can you guess how this \style:apply[name=style@example]{Style} was defined?

Note that despite their command-like syntax, the elements in style
specifications are not (necessarily) corresponding to actual commands.
It just uses that familiar syntax as a convenience.\footnote{Technically-minded readers may
also note it is also very simple to implement that way, just relying
on SILE’s standard parser and its underlying AST.}

Additional user-defined positioning properties can be registered by name and
command in \code{SILE.scratch.styles.positions}.

A style can also inherit from a previously-defined style:

\begin{codes}
\\style:define[name=\doc:args{name}, inherit=\doc:args{other-name}]\{
\par\quad…
\par\}
\end{codes}

This simple style inheritance mechanism is actually quite powerful, allowing
you to re-use or redefine (see further below) existing styles and just
override the elements you want.

\P{Styles for the table of contents.}

The style specification, besides the formatting commands, includes:

\begin{itemize}
\item{Displaying the page number or not,}
\item{Filling the line with dots or not (which, obviously, is only meaningful if the previous option is
      set to true),}
\item{Displaying the section number or not.}
\end{itemize}

\begin{codes}
\\style:define[name=\doc:args{name}]\{
\par\quad{}…
\par\quad\\toc[pageno=\doc:args{boolean}, dotfill=\doc:args{boolean}, numbering=\doc:args{boolean}]
\par\}
\end{codes}

Note that by nature, TOC styles are also paragraph styles (see further below). Moreover,
they also accept an extra specification, which is applied when \code{number} is true, defining:

\begin{itemize}
\item{The text to prepend to the number,}
\item{The text to append to the number,}
\item{The kerning space added after it (defaults to 1spc).}
\end{itemize}

\begin{codes}
\quad{}\\numbering[before=\doc:args{string}, after=\doc:args{string}, kern=\doc:args{length}]
\end{codes}

The pre- and post-strings can be set to false, if you need to disable
an inherited value.

\P{Character styles for bullet lists.}

The style specification includes the character to use as bullet. The other character
formatting commands should of course apply to the bullet too.

\begin{codes}
\\style:define[name=\doc:args{name}]\{
\par\quad{}…
\par\quad\\itemize[bullet=\doc:args{character}]
\par\}
\end{codes}

The bullet can be either entered directly as a character, or provided as a Unicode codepoint in
hexadecimal (U+xxxx).

\P{Character styles for enumerations.}

The style specification includes:

\begin{itemize}
\item{The display type (format) of the item, as “arabic”, “roman”, etc.}
\item{The text to prepend to the value,}
\item{The text to append to the value.}
\end{itemize}

\begin{codes}
\\style:define[name=\doc:args{name}]\{
\par\quad{}…
\par\quad\\enumerate[display=\doc:args{string}, before=\doc:args{string}, after=\doc:args{string}]
\par\}
\end{codes}

The specification also accepts another extended syntax:

\begin{codes}
\\style:define[name=\doc:args{name}]\{
\par\quad{}…
\par\quad\\enumerate[display=\doc:args{U+xxxx}]
\par\}
\end{codes}

\smallskip

Where the display format is provided as a Unicode codepoint in hexadecimal, supposed to
represent the glyph for “1”. It allows using a subsequent range of Unicode characters
as number labels, even though the font may not include any OpenType feature to enable
these automatically. For instance, one could specify U+2474 \unichar{U+2474} (“parenthesized digit one”)…
or, why not, U+2460 \unichar{U+2460}, U+2776 \unichar{U+2776} or even U+24B6 \unichar{U+24B6}, and so on.
It obviously requires the font to have these characters, and due to the way how Unicode is
done, the enumeration to stay within a range corresponding to expected characters.

The other character formatting commands should of course apply to the full label.

\P{Character styles for footnote markers.}

As for other styles above, the character style for footnote markers (i.e. the footnote
symbol or counter in the note itself) should support the "numbering" specification.

\begin{codes}
\quad{}\\numbering[before=\doc:args{string}, after=\doc:args{string}, kern=\doc:args{length}]
\end{codes}

If the kerning space is positive, it should correspond to the space inserted after the footnote
marker. If negative, the note text should be indented by that amount, with the footnote mark
left-aligned in the available space.

For consistency, footnote references (i.e. the footnote call in the main text body) should support
at least the first properties, that is:

\begin{codes}
\quad{}\\numbering[before=\doc:args{string}, after=\doc:args{string}, kern=\doc:args{length}]
\end{codes}

When set, the kerning space is used \em{before} the marker.\footnote{French usage, for instance,
recommends using a thin space or 1pt before the footnote call, which should always follow
a lexical element (i.e. not a punctuation, unlike English where footnote calls are often
seen \em{after} punctuations).}

\P{Paragraph styles.}

To define a paragraph style, one uses the following syntax (with any of the internal
elements being optional):

\begin{codes}
\\style:define[name=\doc:args{name}]\{
\par\quad{}…
\par\quad\\paragraph[skipbefore=\doc:args{glue|skip}, indentbefore=\doc:args{boolean}
\par\qquad{}skipafter=\doc:args{glue|skip}, indentafter=\doc:args{boolean},
\par\qquad{}breakbefore=\doc:args{boolean}, breakafter=\doc:args{boolean},
\par\qquad{}align=\doc:args{center|right|left|justify}]
\par\}
\end{codes}

The specification includes:

\begin{itemize}
\item{The amount of vertical space before the paragraph, as a variable length or a well-known named skip
    (bigskip, medskip, smallskip).}
\item{Whether indentation is applied to this paragraph (defaults to true). Book sectioning commands,
    typically, usually set it to false, for the section title not to be indented.}
\item{The amount of vertical space after the paragraph, as a variable length or a well-known named skip
    (bigskip, medskip, smallskip).}
\item{Whether indentation is applied to the next paragraph (defaults to true). Book sectioning commands,
    typically, may set it to false or true.\footnote{The usual convention for English
    books is to disable the first paragraph indentation after a section title. The French convention, however,
    is to always indent regular paragraphs, even after a section title.}}
\item{Whether a page break may occur before or after this paragraph (defaults to true). Book sectioning commands,
    typically, would set the after-break to false.}
\item{The paragraph alignment (center, left, right or justify—the latter is the default but may be
    useful to overwrite an inherited alignment).}
\end{itemize}

\P{Advanced paragraph styles.}

As specified above, the styles specifications do not provide any way to configure
the margins (i.e. left and right skips) and other low-level paragraph formatting
options.

\script{
-- We use long names with @ in them just to avoid messing with document
-- styles a user might have defined, but obviously this could just be
-- called "block" or whathever.
self:registerCommand("style@blockindent", function (options, content)
  SILE.settings:temporarily(function ()
    local indent = SILE.length("2em")
    SILE.settings:set("document.rskip", SILE.nodefactory.glue(indent))
    SILE.settings:set("document.lskip", SILE.nodefactory.glue(indent))
    SILE.process(content)
    SILE.call("par")
  end)
end, "Typesets its contents in a blockquote.")
SILE.scratch.styles.alignments["block@example"] = "style@blockindent"
}
\style:define[name=style@block]{
    \font[size=-1]
    \paragraph[skipbefore=smallskip, skipafter=smallskip, align=block@example]
}

\begin[name=style@block]{style:apply:paragraph}
But it does not mean this is not possible at all.
You can actually define your own command in Lua that sets these things at
your convenience, and register it with some name in
the \code{SILE.scratch.styles.alignments} array,
so it gets known and is now a valid alignment option.

It allows you to easily extend the styles while still getting the benefits
from their other features.
\end{style:apply:paragraph}

Guess what, it is actually what we did here in code, to typeset the above
“block-indented” paragraph. Similarly, you can also register your own skips
by name in \code{SILE.scratch.styles.skips} so that to use them
in the various paragraph skip options.

As it can be seen in the example above, moreover, what we call a paragraph
here in our styling specification is actually a “paragraph block”—nothing
forbids you to typeset more than one actual paragraph in that environment.
The vertical skip and break options apply before and after that whole block,
not within it; this is by design, notably so as to achieve that kind of
block-indented quotes.

\P{Applying a character style.}

To apply a character style to some content, one just has to do:

\begin{codes}
\\style:apply[name=\doc:args{name}]\{\doc:args{content}\}
\end{codes}

The command raises an error if the named style (or an inherited style) does
not exist. You can specify \autodoc:parameter{discardable=true} if you wish
it to be ignored, without error.

\P{Applying a paragraph style.}

Likewise, the following command applies the whole paragraph style to its content, that is:
the skips and options applying before the content, the character style and the alignment
on the content itself, and finally the skips and options applying after it.

\begin{codes}
\\style:apply:paragraph[name=\doc:args{name}]\{\doc:args{content}\}
\end{codes}

Why a specific command, you may ask? Sometimes, one may want to just apply only the
(character) formatting specifications of a style.

\P{Applying the other styles.}

A style is a versatile concept and a powerful paradigm, but for some advanced usages it
cannot be fully generalized in a single package. The sectioning, table of contents or
enumeration styles all require support from other packages. This package just provides
them a general framework to play with. Actually we refrained for checking many things
in the style specifications, so one could possibly extend them with new concepts and
benefit from the proposed core features and simple style inheritance model.

\P{Redefining styles.}

Regarding re-definitions now, the first syntax below allows one to change the definition
of style \doc:args{name} to new \doc:args{content}, but saving the previous definition to \doc:args{saved-name}:

\begin{codes}
\\style:redefine[name=\doc:args{name}, as=\doc:args{saved-name}]\{\doc:args{content}\}
\end{codes}

From now on, style {\\\doc:args{name}} corresponds to the new definition,
while \code{\\\doc:args{saved-name}} corresponds to previous definition, whatever it was.

Another option is to add the \code{inherit} option to true, as shown below:
\begin{codes}
\\style:redefine[name=\doc:args{name}, as=\doc:args{saved-name}, inherit=true]\{\doc:args{content}\}
\end{codes}

From now on, style {\\\doc:args{name}} corresponds to the new definition as above, but
also inherits from \code{\\\doc:args{saved-name}} — in other terms, both are applied. This allows
one to only leverage the new definition, basing it on the older one.

Note that if invoked without \doc:args{content}, the redefinition will just define an alias to the current
style (and in that case, obviously, the \code{inherit} flag is not supported).
It is not clear whether there is an interesting use case for it (yet), but here you go:

\begin{codes}
\\style:redefine[name=\doc:args{name}, as=\doc:args{saved-name}]
\end{codes}

Finally, the following syntax allows one to restore style \doc:args{name} to whatever was saved
in \doc:args{saved-name}, and to clear the latter:

\begin{codes}
\\style:redefine[name=\doc:args{name}, from=\doc:args{saved-name}]
\end{codes}

So now on, \code{\\\doc:args{name}} is restored to whatever was saved and \code{\\\doc:args{saved-name}}
is no longer defined.

These style redefinion mechanisms are, obviously, at the core of customization.

\P{Additional goodies.}

The package also defines a \autodoc:command{\style:font} command, which is basically the same as the
standard \autodoc:command{\font} command, but additionaly supports relative sizes with respect to
the current \code{font.size}. It is actually the command used when applying a font style
specification. For the sake of illustration, let’s assume the following definitions:

\begin{codes}
\\style:define[name=smaller]\{\\font[size=-1]\}

\\style:define[name=bigger]\{\\font[size=+1]\}

\\define[command=smaller]\{\\style:apply[name=smaller]\{\\process\}\}

\\define[command=bigger]\{\\style:apply[name=bigger]\{\\process\}\}
\end{codes}

\style:define[name=smaller]{\font[size=-1]}
\style:define[name=bigger]{\font[size=+1]}
\define[command=smaller]{\style:apply[name=smaller]{\process}}
\define[command=bigger]{\style:apply[name=bigger]{\process}}

Then:

\begin{codes}
Normal \\smaller\{Small \\smaller\{Tiny\}\},

Normal \\bigger\{Big \\bigger\{Great\}\}.
\end{codes}

Yields: Normal \smaller{Small \smaller{Tiny}}, Normal \bigger{Big \bigger{Great}}.

\end{document}]]

return package
