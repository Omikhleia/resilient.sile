--
-- Enumerations and bullet lists for SILE
-- This a replacement to the "lists" package introduced in SILE,
-- with (expectedly) the same user API but with additional
-- features and styling methods.
-- 2021-2023, Didier Willis
-- License: MIT
--
-- NOTE: Though not described explicitly in the documentation, the package supports
-- two nesting techniques:
-- The "simple" or compact one:
--    \begin{itemize}
--       \item{L1.1}
--       \begin{itemize}
--          \item{L2.1}
--       \end{itemize}
--    \end{itemize}
-- The "alternative" one, which consists in having the nested elements in an item:
--    \begin{itemize}
--       \item{L1.1
--         \begin{itemize}
--            \item{L2.1}
--         \end{itemize}}
--    \end{itemize}
-- The latter might be less readable, but is of course more powerful, as other
-- contents can be added to the item, as in:
--    \begin{itemize}
--       \item{L1.1
--         \begin{itemize}
--            \item{L2.1}
--         \end{itemize}%
--         This is still in L1.1}
--    \end{itemize}
-- But personally, for simple lists, I prefer the first "more readable" one.
-- Lists from Mardown, obviously, due to their structure, would need the
-- second technique.
--
local base = require("packages.resilient.base")

local hboxer = require("resilient-compat.hboxing") -- Compatibility hack/shim

local package = pl.class(base)
package._name = "resilient.lists"

local checkEnumStyleName = function (name, defname)
  return SILE.scratch.styles.specs[name] and name or defname
end

local trimLeft = function (str)
  return str:gsub("^%s*", "")
end

local trimRight = function (str)
  return str:gsub("%s*$", "")
end

local trim = function (str)
  return trimRight(trimLeft(str))
end

local enforceListType = function (cmd)
  if cmd ~= "enumerate" and cmd ~= "itemize" then
    SU.error("Only 'enumerate', 'itemize' or 'item' are accepted in lists, found '"..cmd.."'")
  end
end

local unichar = function (str)
  local hex = (str:match("[Uu]%+(%x+)") or str:match("0[xX](%x+)"))
  if hex then
    return tonumber("0x"..hex)
  end
  return nil
end

function package:resolveEnumStyleDef (name)
  local stylespec = self:resolveStyle(name)
  if stylespec.numbering then
    return {
      display = stylespec.numbering.display or "arabic",
      after = stylespec.numbering.after and stylespec.numbering.after.text or "",
      before = stylespec.numbering.before and stylespec.numbering.before.text or "",
    }
  end
  if stylespec.enumerate then
    return {
      -- afterwards called character for distinguishing it from itemize symbol
      character = stylespec.enumerate.symbol or "U+0031",
    }
  end
  if stylespec.itemize then
    return {
      symbol = stylespec.itemize.symbol or "•",
    }
  end
  SU.error("Style '"..name.."' is not a list style")
end

function package:doItem (options, content)
  local enumStyle = content._lists_.style
  local styleName = content._lists_.styleName
  local counter = content._lists_.counter
  local indent = content._lists_.indent

  if not SILE.typesetter:vmode() then
    SILE.call("par")
  end

  local mark = hboxer.makeHbox(function ()
    local text
    if enumStyle.character then
      local cp = unichar(enumStyle.character)
      if cp then
        text = luautf8.char(cp + counter - 1)
      else
        SU.error("Invalid enumeration symbol in style '" .. styleName .. "'")
      end
    elseif enumStyle.display then
      text = enumStyle.before
        .. self.class.packages.counters:formatCounter({
             value = counter,
             display = enumStyle.display })
        .. enumStyle.after
    else -- enumStyle.symbol
      local bullet = options.bullet or enumStyle.symbol
      local cp = unichar(bullet)
      if cp then
        text = luautf8.char(cp)
      else
        text = bullet
      end
    end
    SILE.call("style:apply", { name = styleName }, { text })
  end)

  local stepback
  if enumStyle.display then
    -- The positionning is quite tentative... LaTeX would right justify the
    -- number (at least for roman numerals), i.e.
    --   i. Text
    --  ii. Text
    -- iii. Text.
    -- Other Office software do not do that...
    local labelIndent = SILE.settings:get("lists.enumerate.labelindent"):absolute()
    stepback = indent - labelIndent
  else
    -- Center bullets in the indentation space
    stepback = indent / 2 + mark.width / 2
  end

  SILE.call("kern", { width = -stepback })
  -- reinsert the mark with modified length
  -- using \rebox caused an issue sometimes, not sure why, with the bullets
  -- appearing twice in output... but we can avoid it:
  -- reboxing an hbox was dumb anyway. We just need to fix its width before
  -- reinserting it in the text flow.
  mark.width = SILE.length(stepback)
  SILE.typesetter:pushHbox(mark)
  SILE.process(content)
end

function package:doNestedList (listType, options, content)
  -- variant
  local variant = SILE.settings:get("lists."..listType..".variant")
  local listAltStyleType = variant and listType.."-"..variant or listType

  -- depth
  local depth = SILE.settings:get("lists.current."..listType..".depth") + 1

  -- styling
  local styleName = checkEnumStyleName("lists-"..listAltStyleType..depth, "lists-"..listType..depth)
  local enumStyle = self:resolveEnumStyleDef(styleName)
  -- options may override the enumeration style:
  -- we can alter it as style resolving returned us a deep copy.
  if enumStyle.display then
    if options.before or options.after then
      -- for before/after, don't mix default style and options
      enumStyle.before = options.before or ""
      enumStyle.after = options.after or ""
    end
    if options.display then enumStyle.display = options.display end
  elseif enumStyle.symbol then
    enumStyle.symbol = options.bullet or enumStyle.symbol
  end

  -- indent
  local baseIndent = (depth == 1) and SILE.settings:get("document.parindent").width:absolute() or SILE.measurement("0pt")
  local listIndent = SILE.settings:get("lists."..listType..".leftmargin"):absolute()

  -- processing
  if not SILE.typesetter:vmode() then
    SILE.call("par")
  end
  SILE.settings:temporarily(function ()
    SILE.settings:set("lists.current."..listType..".depth", depth)
    SILE.settings:set("current.parindent", SILE.nodefactory.glue())
    SILE.settings:set("document.parindent", SILE.nodefactory.glue())
    SILE.settings:set("document.parskip", SILE.settings:get("lists.parskip"))
    local lskip = SILE.settings:get("document.lskip") or SILE.nodefactory.glue()
    SILE.settings:set("document.lskip", SILE.nodefactory.glue(lskip.width + (baseIndent + listIndent)))

    local counter = options.start and (SU.cast("integer", options.start) - 1) or 0
    for i = 1, #content do
      if type(content[i]) == "table" then
        if content[i].command == "item" then
          counter = counter + 1
          -- Enrich the node with internal properties
          content[i]._lists_ = {
            style = enumStyle,
            counter = counter,
            indent = listIndent,
            styleName = styleName,
          }
        else
          enforceListType(content[i].command)
        end
        SILE.process({ content[i] })
        if not SILE.typesetter:vmode() then
          SILE.call("par")
        else
          SILE.typesetter:leaveHmode()
        end
      elseif type(content[i]) == "string" then
        -- All text nodes are ignored in structure tags, but just warn
        -- if there do not just consist in spaces.
        local text = trim(content[i])
        if text ~= "" then SU.warn("Ignored standalone text ("..text..")") end
      else
        SU.error("List structure error")
      end
    end
  end)

  if not SILE.typesetter:vmode() then
      SILE.call("par")
  else
    SILE.typesetter:leaveHmode()
    if not((SILE.settings:get("lists.current.itemize.depth")
        + SILE.settings:get("lists.current.enumerate.depth")) > 0)
    then
      -- So we reached the list top level:
      -- We want to have a document.parskip here, but the previous level already
      -- added a lists.parskip normally.
      -- HACK:
      --   Having to check the typesetter's internal queue is probably fragile.
      --   Having to compare glue references too...
      --   So we just compare their string representation, which is someting
      --   such as "VG<text represention of the dimension>", possibly in a
      --   some relative unit ("non-absolutized").
      local prev = SILE.typesetter.state.outputQueue[#SILE.typesetter.state.outputQueue]
      if prev:tostring() == SILE.settings:get("lists.parskip"):tostring() then
        SU.debug("lists", "Replacing last lists.parskip by document.parskip")
        SILE.typesetter.state.outputQueue[#SILE.typesetter.state.outputQueue] = SILE.settings:get("document.parskip")
      else
        -- Shouldn't occur, but let's be cautious:
        -- The problem here is that we need to make them absolute to perform a
        -- computation. "Too early" absolutization may be problematic, however,
        -- that's why we tried to avoid it. Bah.
        SU.debug("lists", "Compensating last lists.parskip")
        local g = SILE.settings:get("document.parskip").height:absolute() - SILE.settings:get("lists.parskip").height:absolute()
        SILE.typesetter:pushVglue(g)
      end
    end
  end
end

function package:_init (options)
  base._init(self, options)
  self.class:loadPackage("counters")
end

function package.declareSettings (_)

  SILE.settings:declare({
    parameter = "lists.current.enumerate.depth",
    type = "integer",
    default = 0,
    help = "Current enumerate depth (nesting) - internal"
  })

  SILE.settings:declare({
    parameter = "lists.current.itemize.depth",
    type = "integer",
    default = 0,
    help = "Current itemize depth (nesting) - internal"
  })

  SILE.settings:declare({
    parameter = "lists.enumerate.leftmargin",
    type = "measurement",
    default = SILE.measurement("2em"),
    help = "Left margin (indentation) for enumerations"
  })

  SILE.settings:declare({
    parameter = "lists.enumerate.labelindent",
    type = "measurement",
    default = SILE.measurement("0.5em"),
    help = "Label indentation for enumerations"
  })

  SILE.settings:declare({
    parameter = "lists.itemize.leftmargin",
    type = "measurement",
    default = SILE.measurement("1.5em"),
    help = "Left margin (indentation) for bullet lists (itemize)"
  })

  SILE.settings:declare({
    parameter = "lists.parskip",
    type = "vglue",
    default = SILE.nodefactory.vglue("0pt plus 1pt"),
    help = "Leading between paragraphs and items in a list"
  })

  --  Styling

  SILE.settings:declare({
    parameter = "lists.itemize.variant",
    type = "string or nil",
    default = nil,
    help = "Bullet list variant (styling)"
  })

  SILE.settings:declare({
    parameter = "lists.enumerate.variant",
    type = "string or nil",
    default = nil,
    help = "Enumeration list variant (styling)"
  })

end

function package:registerCommands ()

  self:registerCommand("enumerate", function (options, content)
    self:doNestedList("enumerate", options, content)
  end)

  self:registerCommand("itemize", function (options, content)
    self:doNestedList("itemize", options, content)
  end)

  self:registerCommand("item", function (options, content)
    if not content._lists_ then
      SU.error("The item command shall not be called outside a list")
    end
    self:doItem(options, content)
  end)

end

function package:registerStyles ()
  self:registerStyle("lists-enumerate-base", {}, {})
  self:registerStyle("lists-itemize-base", {}, {})

  -- Enumerate style
  self:registerStyle("lists-enumerate1", { inherit = "lists-enumerate-base" }, {
    numbering = { display = "arabic", after =  { text = "." } }
  })
  self:registerStyle("lists-enumerate2", { inherit = "lists-enumerate-base" }, {
    numbering = { display = "roman", after = { text = "." } }
  })
  self:registerStyle("lists-enumerate3", { inherit = "lists-enumerate-base" }, {
    numbering = { display = "alpha", after = { text = ")" } }
  })
  self:registerStyle("lists-enumerate4", { inherit = "lists-enumerate-base" }, {
    numbering = { display = "arabic", after = { text = ")" } }
  })
  self:registerStyle("lists-enumerate5", { inherit = "lists-enumerate-base" }, {
    numbering = { display = "arabic", before = { text = "§" }, after = { text = "." } }
  })

  -- Alternate enumerate style
  self:registerStyle("lists-enumerate-alternate1", { inherit = "lists-enumerate-base" }, {
    numbering = { display = "Alpha", after = { text = "." } }
  })
  self:registerStyle("lists-enumerate-alternate2", { inherit = "lists-enumerate-base" }, {
    numbering = { display = "Roman", after = { text = "." } }
  })
  self:registerStyle("lists-enumerate-alternate3", { inherit = "lists-enumerate-base" }, {
    numbering = { display = "roman", after = { text = "." } }
  })
  self:registerStyle("lists-enumerate-alternate4", { inherit = "lists-enumerate-base" }, {
    font = { style = "italic" },
    numbering = { display = "alpha", after = { text = "." } }
  })
  self:registerStyle("lists-enumerate-alternate5", { inherit = "lists-enumerate-base" }, {
    enumerate = { symbol = "U+2474" }
  })

  -- Itemize style
  self:registerStyle("lists-itemize1", { inherit = "lists-itemize-base" }, {
    itemize = { symbol = "•" } -- black bullet
  })
  self:registerStyle("lists-itemize2", { inherit = "lists-itemize-base" }, {
    itemize = { symbol = "◦" } -- circle bullet
  })
  self:registerStyle("lists-itemize3", { inherit = "lists-itemize-base" }, {
    itemize = { symbol = "–" } -- en-dash
  })
  self:registerStyle("lists-itemize4", { inherit = "lists-itemize-base" }, {
    itemize = { symbol = "•" } -- black bullet
  })
  self:registerStyle("lists-itemize5", { inherit = "lists-itemize-base" }, {
    itemize = { symbol = "◦" } -- circle bullet
  })
  self:registerStyle("lists-itemize6", { inherit = "lists-itemize-base" }, {
    itemize = { symbol = "–" } -- en-dash
  })

  -- Alternate itemize style
  self:registerStyle("lists-itemize-alternate1", { inherit = "lists-itemize-base" }, {
    itemize = { symbol = "—" } -- em-dash
  })
  self:registerStyle("lists-itemize-alternate2", { inherit = "lists-itemize-base" }, {
    itemize = { symbol = "•" } -- black bullet
  })
  self:registerStyle("lists-itemize-alternate3", { inherit = "lists-itemize-base" }, {
    itemize = { symbol = "◦" } -- circle bullet
  })
  self:registerStyle("lists-itemize-alternate4", { inherit = "lists-itemize-base" }, {
    itemize = { symbol = "–" } -- en-dash
  })
  self:registerStyle("lists-itemize-alternate5", { inherit = "lists-itemize-base" }, {
    itemize = { symbol = "•" } -- black bullet
  })
  self:registerStyle("lists-itemize-alternate6", { inherit = "lists-itemize-base" }, {
    itemize = { symbol = "◦" } -- circle bullet
  })
end

package.documentation = [[\begin{document}
The \autodoc:package{resilient.lists} package is a feature-rich, style-enabled replacement for
the SILE standard \autodoc:package{lists} package.

It provides enumerations and bulleted lists (a.k.a. \em{itemization}\kern[width=0.1em]), which
can be styled and, of course, nested together.

\smallskip
\em{Bulleted lists.}
\novbreak

The \autodoc:environment{itemize} environment initiates a bulleted list.
Each item is, as could be guessed, wrapped in an \autodoc:command{\item} command.

The environment, as a structure or data model, can only contain item elements and other lists.
Any other element causes an error to be reported, and any text content is ignored with a warning.

\begin{itemize}
    \item{Lorem}
    \begin{itemize}
        \item{Ipsum}
        \begin{itemize}
            \item{Dolor}
            \begin{itemize}
                \item{Sit amet}
            \end{itemize}
        \end{itemize}
    \end{itemize}
\end{itemize}

The current implementation supports up to 6 indentation levels, which
are set according to the \code{lists-itemize⟨\em{level}⟩} styles.

On each level, the indentation is defined by the \autodoc:setting{lists.itemize.leftmargin}
setting (defaults to 1.5em) and the bullet is centered in that margin.

Note that if your document has a paragraph indent enabled at this point, it
is also added to the first list level.

The good typographic rules sometimes mandate a certain form of representation.
In French, for instance, the em-dash is far more common for the initial bullet
level than the black circle. When one typesets a book in a multi-lingual
context, changing all the style levels consistently would be appreciated.
The package therefore exposes a \autodoc:setting{lists.itemize.variant}
setting, to switch to an alternate set of styles, such as the following.

\set[parameter=lists.itemize.variant, value=alternate]{%
\begin{itemize}
    \item{Lorem}
    \begin{itemize}
        \item{Ipsum}
        \begin{itemize}
            \item{Dolor}
            \begin{itemize}
                \item{Sit amet}
            \end{itemize}
        \end{itemize}
    \end{itemize}
\end{itemize}}%

The alternate styles are expected to be named \code{lists-itemize-⟨\em{variant}⟩⟨\em{level}⟩}
and the package comes along with a predefined “alternate” variant using the em-dash.\footnote{This author is
obviously French…} A good typographer is not expected to switch variants in the middle of a list, so the effect
has not been checked. Be a good typographer.

Besides using styles, you can explicitly select a bullet symbol of your choice to be used, by specifying
the options \autodoc:parameter{bullet=<character>}, on the \autodoc:environment{itemize} environment.

You can also force a specific bullet character to be used on a specific item with
\autodoc:command{\item[bullet=<character>]}.

\smallskip
\em{Enumerations.}
\novbreak

The \autodoc:environment{enumerate} environment initiates an enumeration.
Each item shall, again, be wrapped in an \autodoc:command{\item} command.
This environment too is regarded as a structure, so the same rules as above apply.

The enumeration starts at one, unless you specify the \autodoc:parameter{start=<integer>}
option (a numeric value, regardless of the display format).

\begin{enumerate}
    \item{Lorem}
    \begin{enumerate}
        \item{Ipsum}
        \begin{enumerate}
            \item{Dolor}
            \begin{enumerate}
                \item{Sit amet}
                \begin{enumerate}
                    \item{Consectetur}
                \end{enumerate}
            \end{enumerate}
        \end{enumerate}
    \end{enumerate}
\end{enumerate}

The current implementation supports up to 5 indentation levels, which
are set according to the \code{lists-enumerate⟨\em{level}⟩} styles.

On each level, the indentation is defined by the \autodoc:setting{lists.enumerate.leftmargin} setting (defaults to 2em).
Note, again, that if your document has a paragraph indent enabled at this point, it is also added to the first list level.
And… ah, at least something less repetitive than a raw list of features.
\em{Quite obviously}, we cannot center the label.
Roman numbers, folks, if any reason is required.
The \autodoc:setting{lists.enumerate.labelindent} setting specifies the distance between the label and the previous indentation level (defaults to 0.5em).
Tune these settings at your convenience depending on your styles.
If there is a more general solution to this subtle issue, this author accepts patches.\footnote{TeX typesets
the enumeration label ragged left. Other Office software do not.}

As for bullet lists, switching to an alternate set of styles is possible with,
you certainly guessed it already, the \autodoc:setting{lists.enumerate.variant} setting.

\set[parameter=lists.enumerate.variant, value=alternate]{%
\begin{enumerate}
    \item{Lorem}
    \begin{enumerate}
        \item{Ipsum}
        \begin{enumerate}
            \item{Dolor}
            \begin{enumerate}
                \item{Sit amet}
                \begin{enumerate}
                    \item{Consectetur}
                \end{enumerate}
            \end{enumerate}
        \end{enumerate}
    \end{enumerate}
\end{enumerate}}%

The alternate styles are expected to be \code{lists-enumerate-⟨\em{variant}⟩⟨\em{level}⟩},
how imaginative, and the package comes along with a predefined “alternate” variant, just because.

Besides using styles (or defaulting to them), you can also explicitly select the display type
(format) of the values (as “arabic”, “roman”, etc.), the text prepended or appended
to them, by specifying the options \autodoc:parameter{display=<display>}, \autodoc:parameter{before=<string>},
and \autodoc:parameter{after=<string>} to the \autodoc:environment{enumerate} environment.

\smallskip

\em{Nesting.}
\novbreak

Both environment can be nested, \em{of course}. The way they do is best illustrated by
an example.

\set[parameter=lists.itemize.variant, value=alternate]{%
\begin[variant=alternate]{enumerate}
    \item{Lorem}
    \begin{enumerate}
        \item{Ipsum}
        \begin{itemize}
            \item{Dolor}
            \begin{enumerate}
                \item{Sit amet}
                \begin{itemize}
                    \item{Consectetur}
                \end{itemize}
            \end{enumerate}
        \end{itemize}
    \end{enumerate}
\end{enumerate}}%

\smallskip

\em{Vertical spaces.}
\novbreak

The package tries to ensure a paragraph is enforced before and after a list.
In most cases, this implies paragraph skips to be inserted, with the usual
\autodoc:setting{document.parskip} glue, whatever value it has at these points
in the surrounding context of your document.
Between list items, however, the paragraph skip is switched to the value
of the \autodoc:setting{lists.parskip} setting.

\smallskip

\em{Other considerations.}
\novbreak

Do not expect these fragile lists to work in any way in centered or ragged-right environments, or
with fancy line-breaking features such as hanged or shaped paragraphs.
Please be a good typographer. Also, these lists have not been experimented yet in right-to-left or vertical writing direction.

\end{document}]]

return package
