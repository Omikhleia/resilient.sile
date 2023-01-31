--
-- Re-implementation of the footnotes package
-- 2021, 2022, Didier Willis
--
local base = require("packages.base")

local package = pl.class(base)
package._name = "resilient.footnotes"

function package:_init (options)
  base._init(self, options)

  self.class:loadPackage("resilient.abbr") -- for abbr:nbsp - MAYBE WE'LL CHANGE THIS
  self.class:loadPackage("textsubsuper") -- for textsuperscript
  self.class:loadPackage("rebox") -- used by footnote:rule
  self.class:loadPackage("rules") -- used by footnote:rule
  self.class:loadPackage("counters") -- used for counter formatting
  self.class:loadPackage("raiselower") -- NOT NEEDED NOW, NO?
  self.class:loadPackage("insertions")
  if not SILE.scratch.counters.footnotes then
    SILE.scratch.counters.footnote = { value = 1, display = "arabic" }
  end
  options = options or {}
  self.class:initInsertionClass("footnote", {
    insertInto = options.insertInto or "footnotes",
    stealFrom = options.stealFrom or { "content" },
    maxHeight = SILE.length("75%ph"),
    topBox = SILE.nodefactory.vglue("2ex"),
    interInsertionSkip = SILE.length("1ex"),
  })
end

function package:registerCommands ()
  self:registerStyles()
  local styles = self.class.packages["resilient.styles"]

  -- Footnote separator and rule

  self:registerCommand("footnote:separator", function (_, content)
    SILE.settings:pushState()
    local material = SILE.call("vbox", {}, content)
    SILE.scratch.insertions.classes.footnote.topBox = material
    SILE.settings:popState()
  end, "Base function to create a footnote separator.")

  self:registerCommand("footnote:rule", function (options, _)
    local width = SU.cast("measurement", options.width or "25%fw")
    local beforeskipamount = SU.cast("vglue", options.beforeskipamount or "2ex")
    local afterskipamount = SU.cast("vglue", options.afterskipamount or "1ex")
    local thickness = SU.cast("measurement", options.thickness or "0.5pt")
    SILE.call("footnote:separator", {}, function ()
      SILE.call("noindent")
      SILE.typesetter:pushExplicitVglue(beforeskipamount)
      SILE.call("rebox", {}, function ()
        SILE.call("hrule", { width = width, height = thickness })
      end)
      SILE.typesetter:leaveHmode()
      SILE.typesetter:pushExplicitVglue(afterskipamount)
    end)
  end, "Small helper command (wrapper around footnote:separator) to set a footnote rule.")

  -- Footnote reference call (within the text flow)

  self:registerCommand("footnote:mark", function (options, _)
    local fnStyName = options.mark and "footnote-reference-mark" or "footnote-reference-counter"
    local fnSty = styles:resolveStyle(fnStyName)
    local pre = fnSty.numbering and fnSty.numbering.before or ""
    local post = fnSty.numbering and fnSty.numbering.after or ""
    local kern = fnSty.numbering and fnSty.numbering.kern
    if kern then SU.warn("footnote marker style should not have a kern (numbering) - ignored") end
    local text = pre .. (options.mark or self.class.packages.counters:formatCounter(SILE.scratch.counters.footnote)) .. post

    SILE.call("style:apply", { name = fnStyName }, { text })
  end, "Command internally called to typeset the footnote call reference in the text flow.")

  -- Footnote reference counter (within the footnote)

  self:registerCommand("footnote:counter", function (options, _)
    local fnStyName = options.mark and "footnote-marker-mark" or "footnote-marker-counter"
    local fnSty = styles:resolveStyle(fnStyName)
    local pre = fnSty.numbering and fnSty.numbering.before or ""
    local post = fnSty.numbering and fnSty.numbering.after or ""
    local kern = fnSty.numbering and fnSty.numbering.kern and SU.cast("length", fnSty.numbering.kern)
    local text = pre .. (options.mark or self.class.packages.counters:formatCounter(SILE.scratch.counters.footnote)) .. post

    SILE.call("noindent")
    SILE.call("style:apply", { name = fnStyName }, { text })
    if not kern then
      SILE.call("abbr:nbsp", { fixed = true })
    else
      SILE.call("kern", { width = kern })
    end
  end, "Command internally called to typeset the footnote counter in the footnote itself.")

  -- Footnote insertion block max height and inter-skip tuning

  self:registerCommand("footnote:options", function (options, _)
    if options["maxHeight"] then
      SILE.scratch.insertions.classes.footnote.maxHeight = SILE.length(options["maxHeight"])
    end
    if options["interInsertionSkip"] then
      SILE.scratch.insertions.classes.footnote.interInsertionSkip = SILE.length(options["interInsertionSkip"])
    end
  end, "Command that can be used for tuning the maxHeight and interInsertionSkip for footnotes.")

  self:registerCommand("footnote", function (options, content)
    SILE.call("footnote:mark", options)
    local opts = SILE.scratch.insertions.classes.footnote or {}
    local frame = opts.insertInto and SILE.getFrame(opts.insertInto.frame)
    local oldGetTargetLength = SILE.typesetter.getTargetLength
    local oldFrame = SILE.typesetter.frame
    SILE.typesetter.getTargetLength = function () return SILE.length(0xFFFFFF) end

    SILE.settings:pushState()
    -- Restore the settings to the top of the queue, which should be the document #986
    SILE.settings:toplevelState()
    SILE.typesetter:initFrame(frame)

    -- Reset settings the document may have but should not be applied to footnotes
    -- See also same resets in folio package
    for _, v in ipairs({
      "current.hangAfter",
      "current.hangIndent",
      "linebreak.hangAfter",
      "linebreak.hangIndent" }) do
      SILE.settings:set(v, SILE.settings.defaults[v])
    end

    local labelRefs = self.class.packages.labelrefs
    if labelRefs then -- Cross-reference support
      -- FIXME We recompute the footnote number at least three times (here, on call, on use).
      -- Room for micro-optimization!
      local fn = options.mark or self.class.packages.counters:formatCounter(SILE.scratch.counters.footnote)
      labelRefs:pushLabelRef(fn)
    end

    -- Apply the font before boxing, so relative baselineskip applies #1027
    local material
    SILE.call("style:apply", { name = "footnote" }, function ()
        material = SILE.call("vbox", {}, function ()
        SILE.call("footnote:counter", options)
        SILE.process(content)
      end)
    end)

    if labelRefs then -- Cross-reference support
      labelRefs:popLabelRef()
    end

    SILE.settings:popState()
    SILE.typesetter.getTargetLength = oldGetTargetLength
    SILE.typesetter.frame = oldFrame
    self.class:insert("footnote", material)
    if not (options.mark) then
      SILE.scratch.counters.footnote.value = SILE.scratch.counters.footnote.value + 1
    end
  end, "Typeset a footnote (main command for end-users)")
end

function package:registerStyles ()
  local styles = self.class.packages["resilient.styles"]
  styles:defineStyle("footnote", {}, { font = { size = "-1" } })
  styles:defineStyle("footnote-reference", {}, { properties = { position = "super" } })
  styles:defineStyle("footnote-reference-mark", { inherit = "footnote-reference" }, {})
  styles:defineStyle("footnote-reference-counter", { inherit = "footnote-reference" }, {})
  styles:defineStyle("footnote-marker", {}, { properties = { position = "super" } })
  styles:defineStyle("footnote-marker-mark", { inherit = "footnote-marker" }, {})
  styles:defineStyle("footnote-marker-counter", { inherit = "footnote-marker" }, {})
end

package.documentation = [[\begin{document}
The \autodoc:package{resilient.footnotes} package is a re-implementation of the
default \autodoc:package{footnotes} package from SILE.

In addition to the \autodoc:command{\footnote} command, it provides
a \autodoc:command{\footnote:rule} command as a convenient helper to set
a footnote rule. It may be called, early on in your documents, without options,
or one or several of the following: \autodoc:parameter{length=<length>},
\autodoc:parameter{beforeskipamount=<glue>}, \autodoc:parameter{afterskipamount=<glue>}
and \autodoc:parameter{thickness=<length>}.

The default values for these options are, in order, 25\%fw, 2ex, 1ex and 0.5pt.

It also adds a new \autodoc:parameter{mark} option to the footnote command, which
allows typesetting a footnote with a specific marker instead of
a counter\footnote[mark=†]{As shown here, using \autodoc:command{\footnote[mark=†]{…}}.}.
In that case, the footnote counter is not altered. Among other things, these custom
marks can be useful for editorial footnotes.

The footnote content is typeset according to the \code{footnote} style
(and this re-implementation of the original footnote package, therefore, does not have a
\autodoc:command[check=false]{\footnote:font} hook).

It also redefines the way the marker in the footnote itself
(that is, the internal \autodoc:command{\footnote:counter} command) and
the footnote reference call in the main text flow (that is, the internal
\autodoc:command{\footnote:mark} command) are formatted.
The relevant styles are \code{footnote-reference} for the reference call,
and \code{footnote-marker} for the footnote marker. By default,
both the footnote marker and the footnote reference call are configured to use actual
superscript characters if supported by the current font (see the \autodoc:package{textsubsuper}
package)\footnote{You can see a typical footnote here.}. These two styles also
both have \code{-mark} and \code{-counter} derived styles, would you need to specialize
them differently for custom marks and automated numberic counters, respectively.
This may be interesting, for instance, with a \autodoc:command[check=false]{\numbering} style
specification to define prepended and appended elements or kerning.

\end{document}]]

return package
