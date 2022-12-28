--
-- Re-implementation of the sidenotes package
-- 2021, 2022, Didier Willis
--
local base = require("packages.base")

local package = pl.class(base)
package._name = "resilient.sidenotes"

function package:_init (options)
  base._init(self, options)

  self.class:registerHook("newpage", function ()
    print("----------------SIDE", SILE.scratch.insertions.classes.sidenote['steal-position'])
    if self.class.oddPage and self.class:oddPage() then
      print("SIDE TO BOT")
      
      SILE.scratch.insertions.classes.sidenote['steal-position'] = "bottom"
    else
      print("SIDE TO TOP")
      SILE.scratch.insertions.classes.sidenote['steal-position'] = "top"
    end
  end)
  self.class:loadPackage("resilient.abbr") -- for abbr:nbsp - MAYBE WE'LL CHANGE THIS
  self.class:loadPackage("textsubsuper") -- for textsuperscript
  self.class:loadPackage("rebox") -- used by sidenote:rule
  self.class:loadPackage("rules") -- used by sidenote:rule
  self.class:loadPackage("counters") -- used for counter formatting
  self.class:loadPackage("raiselower") -- NOT NEEDED NOW, NO?
 -- self.class:loadPackage("insertions")
  if not SILE.scratch.counters.sidenotes then
    SILE.scratch.counters.sidenote = { value = 1, display = "arabic" }
  end


  options = options or {}
  self.class:initInsertionClass("sidenote", {
    insertInto = options.insertInto or "sidenotes",
    stealFrom = options.stealFrom or "margins",
    --['steal-position']= "bottom",
    maxHeight = SILE.length("75%ph"),
    topBox = SILE.nodefactory.vglue(), -- EEK
    interInsertionSkip = SILE.length("1ex"),
  })
end

function package:registerCommands ()
  self:registerStyles()
  local styles = self.class.packages["resilient.styles"]

  -- sidenote separator and rule

  self:registerCommand("sidenote:separator", function (_, content)
    SILE.settings:pushState()
    local material = SILE.call("vbox", {}, content)
    SILE.scratch.insertions.classes.sidenote.topBox = material
    SILE.settings:popState()
  end, "Base function to create a sidenote separator.")

  self:registerCommand("sidenote:rule", function (options, _)
    local width = SU.cast("measurement", options.width or "25%fw")
    local beforeskipamount = SU.cast("vglue", options.beforeskipamount or "2ex")
    local afterskipamount = SU.cast("vglue", options.afterskipamount or "1ex")
    local thickness = SU.cast("measurement", options.thickness or "0.5pt")
    SILE.call("sidenote:separator", {}, function ()
      SILE.call("noindent")
      SILE.typesetter:pushExplicitVglue(beforeskipamount)
      SILE.call("rebox", {}, function ()
        SILE.call("hrule", { width = width, height = thickness })
      end)
      SILE.typesetter:leaveHmode()
      SILE.typesetter:pushExplicitVglue(afterskipamount)
    end)
  end, "Small helper command (wrapper around sidenote:separator) to set a sidenote rule.")

  -- sidenote reference call (within the text flow)

  self:registerCommand("sidenote:mark", function (options, _)
    local fnStyName = options.mark and "sidenote-reference-mark" or "sidenote-reference-counter"
    local fnSty = styles:resolveStyle(fnStyName)
    local pre = fnSty.numbering and fnSty.numbering.before or ""
    local post = fnSty.numbering and fnSty.numbering.after or ""
    local kern = fnSty.numbering and fnSty.numbering.kern
    if kern then SU.warn("sidenote marker style should not have a kern (numbering) - ignored") end
    local text = pre .. (options.mark or self.class.packages.counters:formatCounter(SILE.scratch.counters.sidenote)) .. post

    SILE.call("style:apply", { name = fnStyName }, { text })
  end, "Command internally called to typeset the sidenote call reference in the text flow.")

  -- sidenote reference counter (within the sidenote)

  self:registerCommand("sidenote:counter", function (options, _)
    local fnStyName = options.mark and "sidenote-marker-mark" or "sidenote-marker-counter"
    local fnSty = styles:resolveStyle(fnStyName)
    local pre = fnSty.numbering and fnSty.numbering.before or ""
    local post = fnSty.numbering and fnSty.numbering.after or ""
    local kern = fnSty.numbering and fnSty.numbering.kern and SU.cast("length", fnSty.numbering.kern)
    local text = pre .. (options.mark or self.class.packages.counters:formatCounter(SILE.scratch.counters.sidenote)) .. post

    SILE.call("noindent")
    SILE.call("style:apply", { name = fnStyName }, { text })
    if not kern then
      SILE.call("abbr:nbsp", { fixed = true })
    else
      SILE.call("kern", { width = kern })
    end
  end, "Command internally called to typeset the sidenote counter in the sidenote itself.")

  -- sidenote insertion block max height and inter-skip tuning

  self:registerCommand("sidenote:options", function (options, _)
    if options["maxHeight"] then
      SILE.scratch.insertions.classes.sidenote.maxHeight = SILE.length(options["maxHeight"])
    end
    if options["interInsertionSkip"] then
      SILE.scratch.insertions.classes.sidenote.interInsertionSkip = SILE.length(options["interInsertionSkip"])
    end
  end, "Command that can be used for tuning the maxHeight and interInsertionSkip for sidenotes.")

  self:registerCommand("sidenote", function (options, content)
    SILE.call("sidenote:mark", options)
    local opts = SILE.scratch.insertions.classes.sidenote or {}
    local frame = opts.insertInto and SILE.getFrame(opts.insertInto.frame)
    local oldGetTargetLength = SILE.typesetter.getTargetLength
    local oldFrame = SILE.typesetter.frame
    SILE.typesetter.getTargetLength = function () return SILE.length(0xFFFFFF) end

    SILE.settings:pushState()
    -- Restore the settings to the top of the queue, which should be the document #986
    SILE.settings:toplevelState()
    SILE.typesetter:initFrame(frame)

    -- Reset settings the document may have but should not be applied to sidenotes
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
      -- FIXME We recompute the sidenote number at least three times (here, on call, on use).
      -- Room for micro-optimization!
      local fn = options.mark or self.class.packages.counters:formatCounter(SILE.scratch.counters.sidenote)
      labelRefs:pushLabelRef(fn)
    end

    -- Apply the font before boxing, so relative baselineskip applies #1027
    local material
    SILE.call("style:apply", { name = "sidenote" }, function ()
        material = SILE.call("vbox", {}, function ()
        SILE.call("sidenote:counter", options)
        SILE.process(content)
      end)
    end)

    if labelRefs then -- Cross-reference support
      labelRefs:popLabelRef()
    end

    SILE.settings:popState()
    SILE.typesetter.getTargetLength = oldGetTargetLength
    SILE.typesetter.frame = oldFrame
    self.class:insert("sidenote", material)
    if not (options.mark) then
      SILE.scratch.counters.sidenote.value = SILE.scratch.counters.sidenote.value + 1
    end
  end, "Typeset a sidenote (main command for end-users)")
end

function package:registerStyles ()
  local styles = self.class.packages["resilient.styles"]
  styles:defineStyle("sidenote", {}, { font = { size = "-1" } })
  styles:defineStyle("sidenote-reference", {}, { properties = { position = "super" } })
  styles:defineStyle("sidenote-reference-mark", { inherit = "sidenote-reference" }, {})
  styles:defineStyle("sidenote-reference-counter", { inherit = "sidenote-reference" }, {})
  styles:defineStyle("sidenote-marker", {}, { properties = { position = "super" } })
  styles:defineStyle("sidenote-marker-mark", { inherit = "sidenote-marker" }, {})
  styles:defineStyle("sidenote-marker-counter", { inherit = "sidenote-marker" }, {})
end

package.documentation = [[\begin{document}
The \autodoc:package{resilient.sidenotes} package is a re-implementation of the
default \autodoc:package{sidenotes} package from SILE.

In addition to the \autodoc:command{\sidenote} command, it provides
a \autodoc:command{\sidenote:rule} command as a convenient helper to set
a sidenote rule. It may be called, early on in your documents, without options,
or one or several of the following:

\autodoc:command{\sidenote:rule[length=<length>, beforeskipamount=<glue>,
  afterskipamount=<glue>, thickness=<length>]}

The default values for these options are, in order, 25\%fw, 2ex, 1ex and 0.5pt.

It also adds a new \autodoc:parameter{mark} option to the sidenote command, which
allows typesetting a sidenote with a specific marker instead of
a counter\sidenote[mark=†]{As shown here, using \autodoc:command{\sidenote[mark=†]{…}}.}.
In that case, the sidenote counter is not altered. Among other things, these custom
marks can be useful for editorial sidenotes.

The sidenote content is typeset according to the \code{sidenote} style
(and this re-implementation of the original sidenote package, therefore, does not have a
\autodoc:command[check=false]{\sidenote:font} hook).

It also redefines the way the marker in the sidenote itself
(that is, the internal \autodoc:command{\sidenote:counter} command) and
the sidenote reference call in the main text flow (that is, the internal
\autodoc:command{\sidenote:mark} command) are formatted.
The relevant styles are \code{sidenote-reference} for the reference call,
and \code{sidenote-marker} for the sidenote marker. By default,
both the sidenote marker and the sidenote reference call are configured to use actual
superscript characters if supported by the current font (see the \autodoc:package{textsubsuper}
package)\sidenote{You can see a typical sidenote here.}. These two styles also
both have \code{-mark} and \code{-counter} derived styles, would you need to specialize
them differently for custom marks and automated numberic counters, respectively.
This may be interesting, for instance, with a \autodoc:command[check=false]{\numbering} style
specification to define prepended and appended elements or kerning.

\end{document}]]

return package
