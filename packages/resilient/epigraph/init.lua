--
-- An epigraph package for SILE.
-- Following the resilient styling paradigm.
--
-- 2021-2023, Didier Willis
-- License: MIT
--
local base = require("packages.resilient.base")

local package = pl.class(base)
package._name = "resilient.epigraph"

local ast = SILE.utilities.ast
local createStructuredCommand, subContent, extractFromTree
        = ast.createStructuredCommand, ast.subContent, ast.extractFromTree

function package:_init (options)
  base._init(self, options)

  self.class:loadPackage("raiselower")
  self.class:loadPackage("rules")
end

function package.declareSettings (_)
  SILE.settings:declare({
    parameter = "epigraph.width",
    type = "measurement",
    default = SILE.types.measurement("60%lw"),
    help = "Width of an epigraph (defaults to 60% of the current line width)."
  })

  SILE.settings:declare({
    parameter = "epigraph.rule",
    type = "measurement",
    default = SILE.types.measurement(),
    help = "Thickness of the rule drawn below an epigraph text (defaults to 0, meaning no rule)."
  })

  SILE.settings:declare({
    parameter = "epigraph.margin",
    type = "measurement",
    default = SILE.types.measurement(),
    help = "Margin (indent) for an epigraph (defaults to 0)."
  })
end

function package:registerCommands ()
  self:registerCommand("epigraph", function (options, content)
    SILE.settings:temporarily(function ()
      local parindent =
        options.parindent ~= nil and SU.cast("glue", options.parindent)
        or SILE.settings:get("document.parindent")
      local width =
        options.width ~= nil and SU.cast("measurement", options.width)
        or SILE.settings:get("epigraph.width")
      local margin =
        options.margin ~= nil and SU.cast("measurement", options.margin)
        or SILE.settings:get("epigraph.margin")

      local framew = SILE.typesetter.frame:width()
      local epigraphw = width:absolute()
      local skip = framew - epigraphw - margin
      local source = extractFromTree(content, "source")
      SILE.typesetter:leaveHmode()

      local sty = self:resolveStyle("epigraph")
      local align = sty.paragraph and sty.paragraph.align or "right"
      if align == "left" then
        SILE.settings:set("document.lskip", SILE.types.node.glue(margin))
        SILE.settings:set("document.rskip", SILE.types.node.glue(skip))
      elseif align == "right" then
        SILE.settings:set("document.lskip", SILE.types.node.glue(skip))
        SILE.settings:set("document.rskip", SILE.types.node.glue(margin))
      else
        -- undocumented because ugly typographically, IMHO
        SILE.settings:set("document.lskip", SILE.types.node.glue((skip + margin) / 2))
        SILE.settings:set("document.lskip", SILE.types.node.glue((skip + margin) / 2))
      end

      SILE.settings:set("document.parindent", parindent)
      SILE.call("style:apply:paragraph", { name = "epigraph-text" }, {
        subContent(content),
        createStructuredCommand("epigraph:internal:source", {
          width = epigraphw,
          rule = options.rule
        }, source),
      })

      SILE.typesetter:leaveHmode()
    end)
  end, "Displays an epigraph.")

  self:registerCommand("epigraph:internal:source", function (options, content)
    local rule =
        options.rule ~= nil and SU.cast("measurement", options.rule)
        or SILE.settings:get("epigraph.rule")

    local width = SU.required(options, "width", "epigraph")
    width = SU.cast("measurement", width)

    if rule:tonumber() ~= 0 then
      SILE.typesetter:leaveHmode()
      SILE.call("noindent")
      SILE.call("raise", { height = "0.5ex" }, function ()
        -- HACK. Oh my. When left-aligned, the rule is seen as longer than The
        -- line and a new line is inserted. Tweaking it by 0.05pt seems to avoid
        -- it. Rounding issue somewhere? I feel tired.
        SILE.call("hrule", { width = width - 0.05, height = rule })
      end)
    end

    if SU.ast.hasContent(content) then
      SILE.typesetter:leaveHmode(1)
      if rule:tonumber() == 0 then
        SILE.call("style:apply:paragraph", { name = "epigraph-source-norule" }, content)
      else
        SILE.call("style:apply:paragraph", { name = "epigraph-source-rule" }, content)
      end
    end
  end)
end

function package:registerStyles ()
  self:registerStyle("epigraph", {}, {
    font = {
      size = "0.9em"
    },
    paragraph = {
      before = { skip = "medskip" },
      after = { skip = "bigskip" }
    }
  })

  self:registerStyle("epigraph-text", { inherit = "epigraph"}, {
    paragraph = {
      align = "justify",
    }
  })

  self:registerStyle("epigraph-source", {}, {
    -- Saner default without the italic we had in v1.
    -- font = {
    --   style = "italic"
    -- },
    paragraph = {
      align = "right",
      before = {
        vbreak = false,
        indent = false -- by default, we probably don't expect a paragraph indent here.
      }
    }
  })
  self:registerStyle("epigraph-source-norule", { inherit = "epigraph-source" }, {
    paragraph = {
      before = { skip = "smallskip" }
    }
  })
  self:registerStyle("epigraph-source-rule", { inherit = "epigraph-source" }, {
  })
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
With the default styling, the epigraph is placed at the right hand side of the text block,
and the source is typeset at the bottom right of the block.

\begin{epigraph}
  \randomtext
\source{\randomsource}
\end{epigraph}

The default width for the epigraph block is defined by the \autodoc:setting{epigraph.width}
setting, which defaults to 60 percents of the curent line width.
A \autodoc:parameter{width} option is also provided to override it on a single
epigraph.
It may be set to a relative value, e.g. 80 percents the current line
width:

\begin[width=80%lw]{epigraph}
  \randomtext
\end{epigraph}

Or, pretty obviously, with a fixed value, e.g. 8cm.

\begin[width=8cm]{epigraph}
  \randomtext
\end{epigraph}

By default, paragraph indentation is inherited from the document. It can be tuned
with the \autodoc:parameter{parindent} option. For instance, we set it to 0 below.

\begin[parindent=0em]{epigraph}
  \randomtext
\end{epigraph}

A rule may be shown below the epigraph text (and above the source, if
present — in that case, the vertical source skip amount does not
apply). Its thickness is controlled with \autodoc:parameter{rule} being set
to a non-null value, e.g. 0.4pt. The \autodoc:setting{epigraph.rule} may
also be set to define the global default thickness.

\begin[rule=0.4pt]{epigraph}
  \randomtext
  \source{\randomsource}
\end{epigraph}

It is also possible to offset the epigraph from the side (left or right, depending on
styling) it is attached to, with the \autodoc:parameter{margin} option, e.g. 0.5cm:

\begin[margin=0.5cm, rule=0.4pt]{epigraph}
  \randomtext
  \source{\randomsource}
\end{epigraph}

If you want to specify what styling the epigraph environment should use, you
can redefine the \code{epigraph} style (typically for global vertical skips,
font size, etc.), and the \code{epigraph-text} and \code{epigraph-source} styles.

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
