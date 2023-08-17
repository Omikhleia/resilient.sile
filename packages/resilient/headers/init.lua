--
-- headers package for book-like classes
-- Core logic for activating/deactivating headers
-- and handling their output.
-- 2021-2022, Didier Willis
--
-- License: MIT
--
local base = require("packages.base")

local package = pl.class(base)
package._name = "resilient.headers"

SILE.scratch.headers = SILE.scratch.headers or { off = false }

function package:registerCommands ()
  self:registerCommand("headers", function (_, _)
    SILE.scratch.headers.off = false
  end)

  self:registerCommand("noheaders", function (_, _)
    SILE.scratch.headers.off = true
  end)

  self:registerCommand("noheaderthispage", function (_, _)
    SILE.scratch.headers.off = 2
  end)

  self:registerCommand("header:rule", function (options, _)
    local valign = options.valign or "top"
    local offset = SU.cast("measurement", options.offset or "1bs")
    local thickness = SU.cast("measurement", options.thickness or "0.8pt")
    if valign ~= "top" and valign ~= "bottom" then
      SU.error("Invalid header rule valign option")
    end
    if thickness:tonumber() == 0 then
      SILE.scratch.headers.rule = nil
    else
      SILE.scratch.headers.rule = {
        valign = valign,
        offset = offset:absolute(),
        thickness = thickness:absolute()
      }
    end
  end, "Command to set a header rule.")
end

function package.outputHeader (_, headerContent, frame)
  if not frame then frame = "header" end
  if SILE.scratch.headers.off then
    if SILE.scratch.headers.off == 2 then
      SILE.scratch.headers.off = false
    end
  else
    local headerFrame = SILE.getFrame(frame)
    if headerFrame then
      SILE.typesetNaturally(headerFrame, function ()
        if headerContent then
          SILE.settings:pushState()
          -- Restore the settings to the top of the queue, which should be the document
          SILE.settings:toplevelState()
          SILE.settings:set("current.parindent", SILE.nodefactory.glue())
          SILE.settings:set("document.lskip", SILE.nodefactory.glue())
          SILE.settings:set("document.rskip", SILE.nodefactory.glue())

          -- Temporarilly kill footnotes and labels (fragile)
          local oldFt = SILE.Commands["footnote"]
          SILE.Commands["footnote"] = function() end
          local oldLbl = SILE.Commands["label"]
          SILE.Commands["label"] = function () end

          SILE.process(headerContent)

          SILE.typesetter:leaveHmode()

          SILE.Commands["footnote"] = oldFt
          SILE.Commands["label"] = oldLbl
          SILE.settings:popState()
        end

        if SILE.scratch.headers.rule then
          local rule = SILE.scratch.headers.rule
          local w = headerFrame:right() - headerFrame:left()
          local x = headerFrame:left()
          local y
          if rule.valign == "top" then
            y = headerFrame:top() + rule.offset
          else
            y = headerFrame:bottom() - rule.offset
          end
          SILE.outputter:drawRule(x, y, w, rule.thickness)
        end
      end)
    end
  end
end

package.documentation= [[\begin{document}
\use[module=packages.resilient.lists]

The \autodoc:package{resilient.headers} package provides a few basic commands for classes to
better control the output of the page headers, in a way similar to the \autodoc:package{folio}
package for page numbers. It also provides four commands to users:

\begin{itemize}
\item{\autodoc:command{\noheaders}: turns page headers off.}
\item{\autodoc:command{\noheaderthispage}: turns page headers off for one page,
  then on again afterward.}
\item{\autodoc:command{\headers}: turns page headers back on.}
\item{\autodoc:command{\header:rule[valign=<top|bottom>, offset=<length>,
  thickness=<length>]}: draws a header rule when the page headers are active.
  The default values for the options are, in order, top, 1bs and 0.8pt. The rule is drawn
  relative to the header frame; the offset is added if the alignement is to the top
  or substracted if it is to the bottom. This is the most generic solution, as header
  frames can be declared in different ways and, obviously, the nature of the content cannot
  be guessed, but one normally wants the rule to be displayed at the same place on each page…}
\end{itemize}

It exports a Lua method \code{outputHeader()} which should be called by
the class at the end of each page, with the desired content for the current page
header. The class is left responsible for choosing the header content material
depending on its own logic, e.g. two-side pages, sectioning, styling, etc.

\end{document}]]

return package
