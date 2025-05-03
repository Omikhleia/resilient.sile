--
-- Re-implementation of the verbatim package for SILE
-- Following the resilient styling paradigm.
--
-- License: GPL-3.0-or-later
--
-- Copyright (C) 2023-2025 Didier Willis
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
--
local base = require("packages.resilient.base")

local package = pl.class(base)
package._name = "resilient.verbatim"

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

  self:registerCommand("verbatim:block", function (_, content)
    local lskip = SILE.settings:get("document.lskip") or SILE.types.node.glue()
    local rskip = SILE.settings:get("document.rskip") or SILE.types.node.glue()
    SILE.typesetter:leaveHmode()
    SILE.settings:temporarily(function()
      SILE.settings:set("typesetter.parseppattern", "\n")
      SILE.settings:set("typesetter.obeyspaces", true) -- FIXME Dubious setting
      -- We handle the fixed part of right and left skip to support nesting.
      -- We use use a true left alignment (= infinite right stretchability).
      SILE.settings:set("document.lskip", SILE.types.node.glue(lskip.width.length))
      SILE.settings:set("document.rskip", SILE.types.node.hfillglue(rskip.width.length))
      SILE.settings:set("document.parindent", SILE.types.node.glue())
      SILE.settings:set("current.parindent", SILE.types.node.glue())
      SILE.settings:set("document.spaceskip", SILE.types.length("1spc"))
      SILE.settings:set("shaper.variablespaces", false)
      SILE.call("language", { main = "und" })
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
