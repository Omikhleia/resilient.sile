--- Djot native support for SILE
--
-- @copyright License: License: MIT (c) 2023 Omikhleia
-- @classmod packages.djot
--
local base = require("packages.base")

local package = pl.class(base)
package._name = "djot"

--- Package initialization.
--
-- It basically loads the required common packages,
-- and loads the djot inputter.
function package:_init ()
  base._init(self)
  self.class:loadPackage("markdown.commands")

  -- Extend inputters if needed.
  -- Chicken and eggs... This just forces the inputter to be loaded!
  local _ = SILE.inputters.djot
end

--- Package raw handler registrations.
--
-- It enables a raw handler for djot content.
function package:registerRawHandlers ()

  self.class:registerRawHandler("djot", function(options, content)
    SILE.processString(content[1], "djot", nil, options)
  end)

end

package.documentation = [[\begin{document}
The \autodoc:package{djot} package allows you to use Djot as your alternative format
of choice for documents.

This experimental package supports quite the same advanced features as the \autodoc:package{markdown}
package, e.g. the ability to use custom styles, to pass native content through to SILE, etc.

Once you have loaded the package, the \autodoc:command{\include[src=<file>]} command supports
natively reading and processing a Djot file:

\begin{verbatim}
\\use[module=packages.djot]
\\include[src=somefile.dj]
\end{verbatim}

\smallskip

Other possibilities exist (such as setting \autodoc:parameter{format=djot} on the
\autodoc:command{\include} command, if the file extension cannot be one of the supported variants, etc.).
Refer to the SILE manual for more details on inputters and their usage.

Embedding raw Djot content from within a document in SIL markup is also possible:

\begin{verbatim}
\\begin[type=djot]\{raw\}
Some *Djot* content
\\end\{raw\}
\end{verbatim}

\smallskip

The Djot syntax parsing relies on John MacFarlane’s \strong{djot} Lua library,
which empovers this package and thus allows native processing of Djot directly within SILE,
as a first-class language.
\end{document}]]

return package
