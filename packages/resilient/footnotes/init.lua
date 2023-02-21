--
-- Re-implementation of the footnotes package
-- 2021-2023, Didier Willis
--
local base = require("packages.resilient.base")

local package = pl.class(base)
package._name = "resilient.footnotes"

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

  self.class:loadPackage("resilient.abbr") -- for abbr:nbsp
  self.class:loadPackage("textsubsuper") -- for textsuperscript (indirect)
  self.class:loadPackage("rebox") -- used by footnote:rule
  self.class:loadPackage("rules") -- used by footnote:rule
  self.class:loadPackage("counters") -- used for counter formatting
  self.class:loadPackage("insertions")

  -- N.B. Kept starting at 1, with post-incrementation done in the footnote
  -- command, as this was the original footnote package did, although it's
  -- rather weird... But if other packages need to retrieve that counter,
  -- let's not introduce a discrepancy.
  local fnSty = self:resolveStyle("footnote")
  local display = fnSty.numbering and fnSty.numbering.display or "arabic"
  SILE.call("set-counter", { id = "footnote", value = 1, display = display })

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
    local fnStyName = options.mark and "footnote-reference-symbol" or "footnote-reference-counter"
    local text = options.mark or self.class.packages.counters:formatCounter(SILE.scratch.counters.footnote)
    SILE.call("style:apply:number", { name = fnStyName, text = text })
  end, "(Internal) Command called to typeset the footnote call reference in the text flow.")

  -- Footnote reference mark (within the footnote)

  self:registerCommand("footnote:marker", function (options, _)
    local fnStyName = options.mark and "footnote-marker-symbol" or "footnote-marker-counter"
    local text = options.mark or self.class.packages.counters:formatCounter(SILE.scratch.counters.footnote)
    SILE.call("noindent")
    SILE.call("style:apply:number", { name = fnStyName, text = text })
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

    local fnStyName = options.mark and "footnote-marker-symbol" or "footnote-marker-counter"
    local fnSty = self:resolveStyle(fnStyName)
    local kern = fnSty.numbering and fnSty.numbering.before
      and fnSty.numbering.before.kern and castKern(fnSty.numbering.before.kern)

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
      SILE.call("increment-counter", { id = "footnote" })
    end
  end, "Typeset a footnote (main command for end-users)")
end

function package:registerStyles ()
  self:registerStyle("footnote", { main = true }, {
    numbering = { display = "arabic" },
    font = { size = "0.8em" }
    -- Lacroux: Les notes sont composées dans un corps inférieur à celui du texte courant.
    -- (Rapport : environ 2/3.) [followed by a list of usual sizes]"
    -- So our em-ratio is is NOT really correct... But call that ageing, I don't like
    -- reading small notes.
  })
  self:registerStyle("footnote-reference", {}, {
    -- numbering = { before = { kern = "1thsp"}}, -- French
    --
    -- Bringhurst: "In the main text, superscript numbers are used to indicate
    -- notes because superscript numbers minimize interruption."
    properties = { position = "super" }
  })
  self:registerStyle("footnote-reference-symbol", { inherit = "footnote-reference" }, {
  })
  self:registerStyle("footnote-reference-counter", { main = true, inherit = "footnote-reference" }, {})

  self:registerStyle("footnote-marker", {}, {
    -- Bringhurst: "(...) the number in the note should be full size"
    -- (so no superscript here).
    -- Bringurst is less opinionated on how the footnote text should be
    -- presented. Tschichold 1951 lists plenty of rules according to his taste,
    -- but seldom seen in actual books.
    numbering = { before = { kern = "-3.75nspc"}, after = { kern = "iwsp" }}
  })
  self:registerStyle("footnote-marker-symbol", { inherit = "footnote-marker" }, {
  })
  self:registerStyle("footnote-marker-counter", { inherit = "footnote-marker" }, {
    numbering = { after = { text = "." }}
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

It also adds a new \autodoc:parameter{mark=<symbol>} option to the footnote command, which
allows typesetting a footnote with a specific custom symbol instead of
a counter\footnote[mark=†]{As shown here, using \autodoc:command{\footnote[mark=†]{…}}.}.
In that case, the footnote counter is not altered. Among other things, these custom
marks can be useful for editorial footnotes.

The footnote content is typeset according to the \code{footnote} style
(and this re-implementation of the original footnote package, therefore, does not have a
\autodoc:command[check=false]{\footnote:font} hook).

It also redefines the way the marker in the footnote itself
and the footnote reference call in the main text flow are formatted.
The relevant styles are \code{footnote-reference-counter} or
\code{footnote-reference-symbol} for the reference call;
and \code{footnote-marker-counter} or \code{footnote-marker-symbol} for the
footnote marker.\footnote{You can see a typical footnote here.}.

\end{document}]]

return package
