--- Re-implementation of the verbatim package for re·sil·ient.
--
-- Following the resilient styling paradigm.
--
-- @license MIT
-- @copyright (c) 2023-2025 Omikhkeia / Didier Willis
-- @module packages.resilient.verbatim

--- The "resilient.verbatim" package.
--
-- Extends `packages.resilient.base`.
--
-- @type packages.resilient.verbatim

local base = require("packages.resilient.base")
local package = pl.class(base)
package._name = "resilient.verbatim"

--- (Override) Register all commands provided by this package.
function package:registerCommands ()

  -- Unchanged from the original implementation.
  self:registerCommand("verbatim:font", function (options, content)
    SU.warn([[The verbatim:font command is not expected to be used in the resilient context.

    It may be removed in the future, so please try to check why you are seeing
    this warning and possibly report an issue, depending on your findings.
]])
    options.family = options.family or "Hack"
    if not options.size and not options.adjust then
      options.adjust = "ex-height"
    end
    SILE.call("font", options, content)
  end)

  -- Kept for compatibility, but this command is dubious...
  self:registerCommand("obeylines", function (_, content)
  SILE.settings:temporarily(function()
      SILE.settings:set("typesetter.parseppattern", "\n")
      SILE.process(content)
    end)
  end)

  self:registerCommand("verbatim", function (_, content)
    SILE.call("style:apply:paragraph", { name = "verbatim" }, content)
  end, "Typesets its contents styled as 'verbatim'.")

end

--- (Override) Register all styles provided by this package.
function package:registerStyles ()
  base.registerStyles(self)

  self:registerStyle("verbatim", { inherit = "code" }, {
    paragraph = {
      lines = "preserve",
      indent = false,
      align = "left",
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
