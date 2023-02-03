--
-- Re-implementation of the footnotes package
-- 2021-2023, Didier Willis
--
local base = require("packages.resilient.base")

local hboxer = require("resilient-compat.hboxing") -- Compatibility hack/shim

local package = pl.class(base)
package._name = "resilient.footnotes"

function package:_init (options)
  base._init(self, options)

  -- Numaric space (a.k.a. figure space) unit
  local numsp = SU.utf8charfromcodepoint("U+2007")
  SILE.registerUnit("nspc", {
    relative = true,
    definition = function (value)
      return value * SILE.shaper:measureChar(numsp).width
    end
  })

  self.class:loadPackage("resilient.abbr") -- for abbr:nbsp
  self.class:loadPackage("textsubsuper") -- for textsuperscript (indirect)
  self.class:loadPackage("rebox") -- used by footnote:rule
  self.class:loadPackage("rules") -- used by footnote:rule
  self.class:loadPackage("counters") -- used for counter formatting
  self.class:loadPackage("insertions")
  -- FIXME Can't we remove this and expect counters to work?
  -- We'd have to check with SILE upstream how to avoid any use of
  -- the internal scratch variable at package boundaries...
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
  -- Footnote separator and rule

  self:registerCommand("footnote:separator", function (_, content)
    SILE.settings:pushState()
    local material = SILE.call("vbox", {}, content)
    SILE.scratch.insertions.classes.footnote.topBox = material
    SILE.settings:popState()
  end, "(Internal) Base function to create a footnote separator.")

  self:registerCommand("footnote:rule", function (options, _)
    local width = SU.cast("measurement", options.width or "20%fw") -- "Usually 1/5 of the text block"
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

  self:registerCommand("footnote:reference", function (options, _)
    local fnStyName = options.mark and "footnote-reference-mark" or "footnote-reference-counter"
    local fnSty = self:resolveStyle(fnStyName)
    local pre = fnSty.numbering and fnSty.numbering.before or ""
    local post = fnSty.numbering and fnSty.numbering.after or ""
    local kern = fnSty.numbering and fnSty.numbering.kern and SU.cast("length", fnSty.numbering.kern)
    local text = pre .. (options.mark or self.class.packages.counters:formatCounter(SILE.scratch.counters.footnote)) .. post

    -- Lacroux: "Quelle que soit sa forme, l’appel de note se place avant la ponctuation.
    -- Il est précédé par une espace fine insécable."
    -- (i.e. the footnote call mark must be placed before a punctuation, an preceded by a thin space)
    -- However, we can't make this general, as English usage often places footnotes mark after
    -- a punctuation (e.g. esp. a period) and does'nt seem to use a thin space.
    -- Anyhow, if the style defines a kern, use it **before** the mark.
    if kern then
      SILE.call("kern", { width = kern })
    end
    SILE.call("style:apply", { name = fnStyName }, { text })
  end, "(Internal) Command called to typeset the footnote call reference in the text flow.")

  -- Footnote reference mark (within the footnote)

  self:registerCommand("footnote:marker", function (options, _)
    local fnStyName = options.mark and "footnote-marker-mark" or "footnote-marker-counter"
    local fnSty = self:resolveStyle(fnStyName)
    local pre = fnSty.numbering and fnSty.numbering.before or ""
    local post = fnSty.numbering and fnSty.numbering.after or ""
    local kern = fnSty.numbering and fnSty.numbering.kern and SU.cast("length", fnSty.numbering.kern)
    local text = pre .. (options.mark or self.class.packages.counters:formatCounter(SILE.scratch.counters.footnote)) .. post

    -- If the kerning space is positive, it should correspond to the space inserted
    -- after the footnote marker.
    -- If negative, the note text should be indented by that amount, with the
    -- footnote mark left-aligned in the available space.
    if kern and kern:tonumber() < 0 then
      -- IMPLEMENTATION NOTE / HACK / FRAGILE
      -- SILE's behavior with a hbox occuring as very first element of a line
      -- is plain weird. The width of the box is "adjusted" with respect to
      -- the parindent, it seems.
      local hbox = hboxer.makeHbox(function ()
        SILE.call("style:apply", { name = fnStyName }, { text })
      end)
      local remainingSpace = -hbox.width

      -- We want at least the space of a figure digit between the footnote
      -- mark and the text.
      if remainingSpace:tonumber() - SILE.length("1nspc"):absolute() <= 0 then
        SILE.call("style:apply", { name = fnStyName }, { text })
        SILE.call("abbr:nbsp", { fixed = true })
      else
          -- Otherwise, the footnote mark goes beyond the available space,
          -- so add a fixed interword space after it.
          SILE.call("style:apply", { name = fnStyName }, { text })
          SILE.call("kern", { width = remainingSpace })
      end
    else
      SILE.call("noindent")
      SILE.call("style:apply", { name = fnStyName }, { text })
      if not kern then
        SILE.call("abbr:nbsp", { fixed = true })
      else
        SILE.call("kern", { width = kern })
      end
    end
  end, "(Internal) Command called to typeset the footnote counter in the footnote itself.")

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
    SILE.call("footnote:reference", options)
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

    local fnStyName = options.mark and "footnote-marker-mark" or "footnote-marker-counter"
    local fnSty = self:resolveStyle(fnStyName)
    local kern = fnSty.numbering and fnSty.numbering.kern and SU.cast("length", fnSty.numbering.kern)

    -- Apply the font before boxing, so relative baselineskip applies #1027
    local material
    SILE.call("style:apply", { name = "footnote" }, function ()
      if kern and kern:tonumber() < 0 then
        -- HACK / FRAGILE: immediate absolutization, cause weird things occur
        -- otherwise (not sure when this gets absolutized with respect to the
        -- vbox construction, but something deeper is amiss...)
        SILE.settings:set("document.parindent", kern:absolute())
        SILE.settings:set("document.lskip", -kern:absolute())
      end
      material = SILE.call("vbox", {}, function ()
        SILE.call("footnote:marker", options)
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
  self:registerStyle("footnote", {}, {
    font = { size = "0.9em" }
    -- Lacroux: Les notes sont composées dans un corps inférieur à celui du texte courant.
    -- (Rapport : environ 2/3.) [followed by a list of sizes]"
    -- So our em-ratio is is NOT really correct... But call that ageing, I don't like
    -- reading small notes.
  })
  self:registerStyle("footnote-reference", {}, {
    -- Bringhurst: "In the main text, superscript numbers are used to indicate
    -- notes because superscript numbers minimize interruption."
    properties = { position = "super" }
    -- numbering = { kern = "1pt" } = No, see comment in footnote:reference command
  })
  self:registerStyle("footnote-reference-mark", { inherit = "footnote-reference" }, {})
  self:registerStyle("footnote-reference-counter", { inherit = "footnote-reference" }, {})

  self:registerStyle("footnote-marker", {}, {
    -- Bringhurst: "(...) the number in the note should be full size"
    -- (so no superscript here).
    -- Bringurst is less opinionated on how the footnote text should be
    -- presented. Tschichold 1951 lists plenty of rules according to his taste,
    -- but seldom seen in actual books.
    numbering = { kern = "-3.75nspc"}
  })
  self:registerStyle("footnote-marker-mark", { inherit = "footnote-marker" }, {})
  self:registerStyle("footnote-marker-counter", { inherit = "footnote-marker" }, {
    numbering = { after = "." }
    -- Bringhurst: "Punctuation, apart from empty space, is not normally needed
    -- between the number and text of the note" - But then he has an example with
    -- a period...
    -- Jan Tschichold 1951 "(...) normal numeral followed by period" (but also
    -- very opinionated on indents, see above)
  })
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

The default values for these options are, in order, 20\%fw, 2ex, 1ex and 0.5pt.

It also adds a new \autodoc:parameter{mark} option to the footnote command, which
allows typesetting a footnote with a specific marker instead of
a counter\footnote[mark=†]{As shown here, using \autodoc:command{\footnote[mark=†]{…}}.}.
In that case, the footnote counter is not altered. Among other things, these custom
marks can be useful for editorial footnotes.

The footnote content is typeset according to the \code{footnote} style
(and this re-implementation of the original footnote package, therefore, does not have a
\autodoc:command[check=false]{\footnote:font} hook).

It also redefines the way the marker in the footnote itself
and the footnote reference call in the main text flow are formatted.
The relevant styles are \code{footnote-reference} for the reference call,
and \code{footnote-marker} for the footnote marker. By default,
the footnote reference call are configured to use superscript characters
(see the \autodoc:package{textsubsuper} package)\footnote{You can see a typical footnote here.}.
These two styles also both have \code{-mark} and \code{-counter} derived styles,
would you need to specialize them differently for custom marks and automated numberic
counters, respectively.
This may be interesting, for instance, with a \autodoc:command[check=false]{\numbering} style
specification to define prepended and appended elements or kerning.

\end{document}]]

return package
