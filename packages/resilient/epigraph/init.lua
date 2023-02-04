--
-- An epigraph package for SILE
-- 2021-2023, Didier Willis
-- License: MIT
--
local base = require("packages.resilient.base")

local package = pl.class(base)
package._name = "resilient.epigraph"

function package:_init (options)
  base._init(self, options)

  self.class:loadPackage("raiselower")
  self.class:loadPackage("rules")
end

local extractFromTree = function (tree, command)
  for i=1, #tree do
    if type(tree[i]) == "table" and tree[i].command == command then
      return table.remove(tree, i)
    end
  end
end

function package.declareSettings (_)
  SILE.settings:declare({
    parameter = "epigraph.beforeskipamount",
    type = "vglue",
    default = SILE.settings:get("plain.medskipamount"),
    help = "Vertical offset before an epigraph (defaults to a medium skip)."
  })

  SILE.settings:declare({
    parameter = "epigraph.afterskipamount",
    type = "vglue",
    default = SILE.settings:get("plain.bigskipamount"),
    help = "Vertical offset after an epigraph (defaults to a big skip)."
  })

  SILE.settings:declare({
    parameter = "epigraph.sourceskipamount",
    type = "vglue",
    default = SILE.settings:get("plain.smallskipamount"),
    help = "Vertical offset betwen an epigraph text and its source (defaults to a small skip)."
  })

  SILE.settings:declare({
    parameter = "epigraph.parindent",
    type = "glue",
    default = SILE.settings:get("document.parindent"),
    help = "Paragraph identation in an epigraph (defaults to document paragraph indentation)."
  })

  SILE.settings:declare({
    parameter = "epigraph.width",
    type = "length",
    default = SILE.length("60%lw"),
    help = "Width of an epigraph (defaults to 60% of the current line width)."
  })

  SILE.settings:declare({
    parameter = "epigraph.rule",
    type = "length",
    default = SILE.length("0"),
    help = "Thickness of the rule drawn below an epigraph text (defaults to 0, meaning no rule)."
  })

  SILE.settings:declare({
    parameter = "epigraph.align",
    type = "string",
    default = "right",
    help = "Position of an epigraph in the frame (right or left, defaults to right)."
  })

  SILE.settings:declare({
    parameter = "epigraph.ragged",
    type = "boolean",
    default = false,
    help = "Whether an epigraph is ragged (defaults to false)."
  })

  SILE.settings:declare({
    parameter = "epigraph.margin",
    type = "length",
    default = SILE.length("0"),
    help = "Margin (indent) for an epigraph (defaults to 0)."
  })
end

function package:registerCommands ()
  self:registerCommand("epigraph:font", function (_, _)
    SILE.call("font", { size = SILE.settings:get("font.size") - 1 })
  end, "Font used for an epigraph")

  self:registerCommand("epigraph:source:font", function (_, _)
    SILE.call("font", { style = "italic" })
  end, "Font used for the epigraph source, if present.")

  self:registerCommand("epigraph", function (options, content)
    SILE.settings:temporarily(function ()
      local beforeskipamount =
        options.beforeskipamount ~= nil and SU.cast("vglue", options.beforeskipamount)
        or SILE.settings:get("epigraph.beforeskipamount")
      local afterskipamount =
        options.afterskipamount ~= nil and SU.cast("vglue", options.afterskipamount)
        or SILE.settings:get("epigraph.afterskipamount")
      local sourceskipamount =
        options.sourceskipamount ~= nil and SU.cast("vglue", options.sourceskipamount)
        or SILE.settings:get("epigraph.sourceskipamount")
      local parindent =
        options.parindent ~= nil and SU.cast("glue", options.parindent)
        or SILE.settings:get("epigraph.parindent")
      local width =
        options.width ~= nil and SU.cast("length", options.width)
        or SILE.settings:get("epigraph.width")
      local rule =
        options.rule ~= nil and SU.cast("length", options.rule)
        or SILE.settings:get("epigraph.rule")
      local align =
        options.align ~= nil and SU.cast("string", options.align)
        or SILE.settings:get("epigraph.align")
      local ragged =
        options.ragged ~= nil and SU.cast("boolean", options.ragged)
        or SILE.settings:get("epigraph.ragged")
      local margin =
        options.margin ~= nil and SU.cast("length", options.margin)
        or SILE.settings:get("epigraph.margin")

      local framew = SILE.typesetter.frame:width()
      local epigraphw = width:absolute()
      local skip = framew - epigraphw - margin
      local source = extractFromTree(content, "source")
      SILE.typesetter:leaveHmode()
      SILE.typesetter:pushVglue(beforeskipamount)

      local l = ragged
        and SILE.length(skip, 1e10) -- some real huge strech
        or SILE.length({ length = skip })
      local glue = SILE.nodefactory.glue({ width = l })
      if align == "left" then
        SILE.settings:set("document.rskip", glue)
        SILE.settings:set("document.lskip", margin)
      else
        SILE.settings:set("document.lskip", glue)
        SILE.settings:set("document.rskip", margin)
      end

      SILE.settings:set("document.parindent", parindent)
      SILE.call("style:apply", { name = "epigraph" }, function()
        SILE.process(content)
        if rule:tonumber() ~= 0 then
          SILE.typesetter:leaveHmode()
          SILE.call("noindent")
          SILE.call("raise", { height = "0.5ex" }, function ()
            SILE.call("hrule", {width = epigraphw, height = rule })
          end)
        end
        if source then
          SILE.typesetter:leaveHmode(1)
          if rule:tonumber() == 0 then
            SILE.typesetter:pushVglue(sourceskipamount)
          end
          SILE.call("style:apply", { name = "epigraph-source" }, function()
            SILE.call("raggedleft", {}, source)
          end)
        end
      end)
      SILE.typesetter:leaveHmode()
      SILE.typesetter:pushVglue(afterskipamount)
    end)
  end, "Displays an epigraph.")
end

function package:registerStyles ()
  self:registerStyle("epigraph", {}, { font = { size = -1 } })
  self:registerStyle("epigraph-source", {}, { font = { style="italic" } })
end

package.documentation = [[\begin{document}
\use[module=packages.lorem]
\define[command=randomtext]{\lorem[words=18].}
\define[command=randomsource]{The Lorem Ipsum Book.}

The \autodoc:package{resilient.epigraph} package for SILE can be used to typeset
a relevant quotation or saying as an epigraph, usually at either the start or end of
a section. Various handles are provided to tweak the appearance.\footnote{This is
very loosely inspired from the LaTeX \code{epigraph} package.}

The \autodoc:environment{epigraph} environment typesets an epigraph using the provided text.
An optional source (author, book name, etc.) can also be defined, with
the \autodoc:command[check=false]{\source} command in the text block.
By default the epigraph is placed at the right hand side of the text block,
and the source is typeset at the bottom right of the block.

\begin{epigraph}
  \randomtext
\source{\randomsource}
\end{epigraph}

Without source:

\begin{epigraph}
  \randomtext
\end{epigraph}

The default width for the epigraph block is \autodoc:setting{epigraph.width}.
A \autodoc:parameter{width} option is also provided to override it on a single
epigraph\footnote{Basically, all global settings are also available as
command options (or reciprocally!), with the same name but the namespace left
out. For the sake of brevity, we will therefore omit the namespace from this
point onward.}.
It may be set to a relative value, e.g. 80 percents the current line
width:

\begin[width=80%lw]{epigraph}
  \randomtext
\end{epigraph}

Or, pretty obviously, with a fixed value, e.g. 8cm.

\begin[width=8cm]{epigraph}
  \randomtext
\end{epigraph}

The vertical skips are controlled by \autodoc:parameter{beforeskipamount},
\autodoc:parameter{afterskipamount}, \autodoc:parameter{sourceskipamount}. The latter is
only applied if there is a source specified and the epigraph doesn’t
show a rule (see further below).

In the following example, the two first options are set to
0.5cm and the source skip is set to 0.

\begin[beforeskipamount=0.5cm, afterskipamount=0.5cm, sourceskipamount=0]{epigraph}
  \randomtext
\source{\randomsource}
\end{epigraph}

By default, paragraph indentation is inherited from the document. It can be tuned
with \autodoc:parameter{parindent}, e.g. 1em.

\begin[parindent=1em]{epigraph}
  \randomtext

  \randomtext
\end{epigraph}

A rule may be shown below the epigraph text (and above the source, if
present — in that case, the vertical source skip amount does not
apply). Its thickness is controlled with \autodoc:parameter{rule} being set
to a non-null value, e.g. 0.4pt.

\begin[rule=0.4pt]{epigraph}
  \randomtext
  \source{\randomsource}
\end{epigraph}

Likewise, without source:

\begin[rule=0.4pt]{epigraph}
  \randomtext
\end{epigraph}

By default, the epigraph text is justified. This may be changed setting
\autodoc:parameter{ragged} to true.

The text is then ragged on the opposite side to the epigraph block,
so on the left for a right-aligned block.

\begin[ragged=true]{epigraph}
  \randomtext
  \source{\randomsource}
\end{epigraph}

It would be ragged on the right for a left-aligned epigraph block.

\begin[align=left, ragged=true]{epigraph}
  \randomtext
  \source{\randomsource}
\end{epigraph}

Here, we introduced the \autodoc:parameter{align} option, set to \code{left}.
All the settings previously mentioned also apply to left-aligned
epigraphs, so we can of course tweak them at convenience.

\begin[align=left, rule=0.4pt, parindent=0, width=45%lw]{epigraph}
  \randomtext
  \source{\randomsource}
\end{epigraph}

It is also possible to offset the epigraph from the side (left or right) it is attached to, with the
\autodoc:parameter{margin} option, e.g. 0.5cm:

\begin[margin=0.5cm, rule=0.4pt]{epigraph}
  \randomtext
  \source{\randomsource}
\end{epigraph}

If you want to specify what styling the epigraph environment should use, you
can redefine the \code{epigraph} style. By default it will be the same
as the surrounding document, just smaller.
The epigraph source is typeset in italic by default. It can be modified too,
by redefining \code{epigraph-source}.

\style:redefine[name=epigraph, as=saved:epigraph]{\font[style=italic]}
\style:redefine[name=epigraph-source, as=saved:epigraph-source]{\font[style=normal]}
\begin{epigraph}
  \randomtext
\source{\randomsource}
\end{epigraph}
\style:redefine[name=epigraph, from=saved:epigraph]
\style:redefine[name=epigraph-source, from=saved:epigraph-source]

As final notes, the epigraph source is intended to be short by nature, therefore
no specific effort has been made to correctly handle sources longer than
the epigraph block or even spanning on multiple lines.

Before anyone asks, the alignment options for an epigraph are to the left or to the right
of the frame only; notably, there is no intention to support centering. This author does not
think centered epigraphs are typographically sound.

For the curious-minded, it turns out that nested epigraphs do work somewhat as intended.
Your mileage may vary depending on the combination of settings.
This is not expected to be a highly requested feature and has not been thoroughly tested.

\begin[rule=0.4pt, width=80%lw]{epigraph}
\randomtext
\begin[width=80%lw]{epigraph}
  Words — so innocent and powerless as they are, as standing in a dictionary,
  how potent for good and evil they become in the hands of one who knows how to combine them.
  \source{Nathaniel Hawthorne}
\end{epigraph}
\randomtext
\source{\randomsource}
\end{epigraph}

\end{document}]]

return package
