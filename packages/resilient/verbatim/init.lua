local base = require("packages.resilient.base")

local package = pl.class(base)
package._name = "resilient.verbatim"

function package:registerCommands ()

  -- Unchanged from the original implementation, as bad as it is.
  self:registerCommand("verbatim:font", function (options, content)
    SU.warn([[The verbatim:font command is not expected to be used in the resilient context.

    It may be removed in the future, so please try to check why you are seeing
    this warning and possibly report an issue, depending on your findings.
]])
    options.family = options.family or "Hack"
    options.size = options.size or SILE.settings:get("font.size") - 3
    SILE.call("font", options, content)
  end)

  -- Kept for compatibility, but this command is dubious...
  self:registerCommand("obeylines", function (_, content)
  SILE.settings:temporarily(function()
      SILE.settings:set("typesetter.parseppattern", "\n")
      SILE.process(content)
    end)
  end)

  self:registerCommand("verbatim:block", function (_, content)
    local lskip = SILE.settings:get("document.lskip") or SILE.nodefactory.glue()
    local rskip = SILE.settings:get("document.rskip") or SILE.nodefactory.glue()
    SILE.typesetter:leaveHmode()
    SILE.settings:temporarily(function()
      SILE.settings:set("typesetter.parseppattern", "\n")
      SILE.settings:set("typesetter.obeyspaces", true) -- Dubious
      -- IMPLEMENTATION NOTE
      -- Contrary to SILE's original implementation, we don't set the
      -- document.baselineskip to zero, this does not seem to be a sane thing.
      -- Moreover we handle the right and left skip nesting, and use a true
      -- left alignment (= infinite right stretchability rather than some 10000pt).
      SILE.settings:set("document.lskip", SILE.nodefactory.glue(lskip.width.length))
      SILE.settings:set("document.rskip", SILE.nodefactory.hfillglue(rskip.width.length))
      SILE.settings:set("document.parindent", SILE.nodefactory.glue())
      SILE.settings:set("current.parindent", SILE.nodefactory.glue())
      SILE.settings:set("document.spaceskip", SILE.length("1spc"))
      SILE.settings:set("shaper.variablespaces", false)
      SILE.settings:set("document.language", "und")
      SILE.process(content)
      SILE.typesetter:leaveHmode()
    end)
  end, "Typesets its contents in a left-aligned block honoring spaces and line-breaks.")

  self:registerCommand("verbatim", function (_, content)
    SILE.call("style:apply:paragraph", { name = "verbatim" }, content)
  end, "Typesets its contents styled as 'verbatim'.")

end

function package:registerStyles ()
  base.registerStyles(self)

  SILE.scratch.styles.alignments["obeylines"] = "verbatim:block"

  self:registerStyle("verbatim", { inherit = "code" }, {
    paragraph = {
      align = "obeylines",
      --after = {
        -- FIXME
        -- Some weird skip occurs naturally in the resilient manual (djot and markdown content)
        -- It would need investigation.
        -- skip = "smallskip"
      --},
      before = {
        skip = "smallskip"
      }
    }
  })
end


package.documentation = [[
\begin{document}
The \autodoc:package{resilient.verbatim} package is a re-implementation of the
default \autodoc:package{verbatim} package from SILE.

It changes SILE’s settings so that text is set ragged right, with no hyphenation, no indentation and regular spacing.
It also tells SILE to honor multiple spaces and line breaks.

This package does not support the \code{verbatim:font} “hook” that the original implementation had.
Rather, the content formatting is based on a \code{verbatim} style.

It also defines the \code{obeylines} alignment option to paragraph styles.
\end{document}
]]

return package
