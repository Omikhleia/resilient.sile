--
-- Generic sectioning command and styles for SILE.
-- Following the resilient styling paradigm.
-- It is nn extension of the "styles" package and the sectioning paradigm.
--
-- License: GPL-3.0-or-later
--
-- Copyright (C) 2021-2025 Didier Willis
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
package._name = "resilient.sectioning"

function package:_init (options)
  base._init(self, options)
  self:loadPackage("counters")
end

local function hasContentInCurrentPage()
  -- Important, flushes nodes to output queue.
  SILE.typesetter:leaveHmode()
  -- The frame breaking logic is a bit messy:
  -- It's not enough to check if the output queue is empty, because in some
  -- cases where horizontal mode was already left, the output queue might still
  -- contain vglue nodes. These are ignored afterwards at the top of a frame,
  -- so do not count.
  local hasNonGlueContent = false
  for _, vnode in ipairs(SILE.typesetter.state.outputQueue) do
    if not vnode.is_vglue then
      hasNonGlueContent = true
      break
    end
  end
  return hasNonGlueContent
end

local function nameIfNotNull (name)
  -- Nothig to fancy but there's a special case for the null value in YAML
  -- style definitions.
  if not name then
    return nil
  end
  if type(name) == "string" then
    return name
  end
  if tostring(name) == "yaml.null" then
    return nil
  end
  SU.error("Invalid style name, expected a string or YAML null")
end

function package:registerCommands ()

  local resolveSectionStyleDef = function (name)
    local styledef = self:resolveStyle(name)
    if styledef.sectioning then
      -- Apply counter defaults
      styledef.sectioning.counter = styledef.sectioning.counter or {}
      styledef.sectioning.counter.id = styledef.sectioning.counter.id
        or SU.error("Sectioning style '"..name.."' must have a counter")
      styledef.sectioning.counter.level = styledef.sectioning.counter.level or 1

      -- Apply settings defaults
      styledef.sectioning.settings = styledef.sectioning.settings or {}
      -- styledef.sectioning.settings.open: if nil = do not open a page
      styledef.sectioning.settings.toclevel = styledef.sectioning.settings.toclevel
        and SU.cast("integer", styledef.sectioning.settings.toclevel)
      styledef.sectioning.settings.goodbreak = SU.boolean(styledef.sectioning.settings.goodbreak, true)
      styledef.sectioning.settings.bookmark = SU.boolean(styledef.sectioning.settings.bookmark, true)

      -- Apply numberstyle defaults
      styledef.sectioning.numberstyle = styledef.sectioning.numberstyle or {}
      -- styledef.sectioning.numberstyle.main: no default, won't display if absent
      -- styledef.sectioning.numberstyle.header: no default, won't display if absent
      -- styledef.sectioning.numberstyle.reference: no default, won't display if absent

      -- styledef.sectioning.hook may be absent (no hook)
      return styledef
    end
    SU.error("Style '"..name.."' is not a sectioning style")
  end

  self:registerCommand("sectioning", function (options, content)
    local name = SU.required(options, "style", "sectioning")
    local numbering = SU.boolean(options.numbering, true)
    local toc = SU.boolean(options.toc, true)
    local marker = options.marker

    local sty = resolveSectionStyleDef(name)
    local secStyle = sty.sectioning

    -- Handle the page-break: opening page: "unset", "odd" or "any"
    -- (Would "even" be useful? I do not think is has any actual use)
    if secStyle.settings.open and secStyle.settings.open ~= "unset" then
      -- Sectioning style that causes a page-break.
      if secStyle.settings.open == "odd" then
        SILE.call("open-on-odd-page")
      else -- Case: any
        SILE.call("open-on-any-page")
      end
      if sty.paragraph and sty.paragraph.before.skip then
        -- Ensure the vertical skip will be applied even if at the top of
        -- the page. Introduces a line, though. I haven't found how to avoid
        -- it :(
        SILE.typesetter:initline()
      end
    end
    -- N.B. for sectioning style that doesn't cause a forced page-break,
    -- we previously checked here if we had to insert a goodbreak.
    -- We now do it in the paragraph style logic, in order to properly manage
    -- consecutive styles (e.g. a subsection directly preceded by a section
    -- shouldn't trigger a goodbreak in-between).

    -- Process the section (title) content
    local numStyName = secStyle.numberstyle.main and nameIfNotNull(secStyle.numberstyle.main)
    local numSty = numStyName and self:resolveStyle(numStyName)
    local numDisplay = numSty and numSty.numbering and numSty.numbering.display or "arabic"

    -- Counter for numbered sections
    local number
    if numbering then
      SILE.call("increment-multilevel-counter", {
        id = secStyle.counter.id,
        level = secStyle.counter.level,
        display = numDisplay
      })
      number = self.class.packages.counters:formatMultilevelCounter(
        self.class:getMultilevelCounter(secStyle.counter.id), { noleadingzeros = true }
      )
    end

    -- Handle the style hook if specified.
    -- Pass the user-defined options, the counter and level, so it has them, if needed.
    -- Also pass the styled header content (possibly with the number).
    local titleHookContent
    if secStyle.hook then
      local hookOptions = pl.tablex.copy(options)
      hookOptions.counter = secStyle.counter.id
      hookOptions.level = secStyle.counter.level
      hookOptions.before = true -- HACK SEE BELOW
      local numsty = sty.sectioning
          and sty.sectioning.numberstyle
          -- Only user header number if main number style is defined
          and nameIfNotNull(sty.sectioning.numberstyle.main)
          and nameIfNotNull(sty.sectioning.numberstyle.header)
      if numbering and numsty then
        titleHookContent = {
          SU.ast.createCommand("style:apply:number", { name = numsty, text = number }),
          SU.ast.subContent(content)
        }
      else
        titleHookContent = SU.ast.subContent(content)
      end
      -- HACK HOOK - BAD DESIGN WORKAROUND
      -- https://github.com/Omikhleia/resilient.sile/issues/43
      -- The hook logic does two different things and we cannot change it
      -- without breaking existing style files. So we have to do this hack,
      -- calling the hook twice for the before and after parts, where the
      -- before part is responsible for settings things (presence or not of
      -- header and folio, other counter resets, etc.) and the after part
      -- is responsible for handling the running header.
      -- Moreover, the running header will need to an info node, inserted
      -- at the appropriate place in the content (see further below),
      -- without the style applied to the content (esp. text casing).
      -- So we hide it in a short-term command.
      SILE.call(secStyle.hook, hookOptions)
      hookOptions.before = false
      self:registerCommand("sectioning:hack:hook", function ()
        SILE.call(secStyle.hook, hookOptions, titleHookContent)
      end)
    end

    local titleContent = {}
    -- HACK TOC ENTRY - BAD DESIGN WORKAROUND
    -- We pass it added to the content, so the toc entry info note occurs at the right place.
    -- But we do not want the paragraph style applied around it
    -- (and the TOC info node is located in the right place, notwithstanding breaks, skips, etc.).
    -- That will be a problem later if the paragraph style includes input filters or needs
    -- to tweaks (typically, text casing is in that situation).
    -- We could have done things slightly differently (splitting how paragraph style is applied),
    -- but I went another quick and dirty route in the styles package...
    -- So we use the same hack as for the hook, hiding the content tree
    -- in a short-term command.
    local toclevel = secStyle.settings.toclevel
    local bookmark = secStyle.settings.bookmark
    if toclevel and toc then
      self:registerCommand("sectioning:hack:toc", function ()
        SILE.call("tocentry", { level = toclevel, number = number, bookmark = bookmark },
          SU.ast.subContent(content))
      end)
      titleContent[#titleContent + 1] = SU.ast.createCommand("sectioning:hack:toc")
    end

    -- Show section number (if numbering is true AND a main style is defined)
    if numbering then
      if numStyName then
        titleContent[#titleContent + 1] =
          SU.ast.createCommand("style:apply:number", { name = numStyName, text = number })
        if SU.boolean(numSty.numbering and numSty.numbering.standalone, false) then
          titleContent[#titleContent + 1] =
            SU.ast.createCommand("hardbreak")
        end
      end
    end
    -- Section (title) content
    titleContent[#titleContent + 1] = SU.ast.subContent(content)

    -- Cross-reference label
    -- If the \label command is defined, assume a cross-reference package
    -- is loaded and allow specifying a label marker. This makes it less clumsy
    -- than having to put it in the section title content, or just after the section
    -- (with the risk of impacting indent/noindent and novbreak decisions here)
    if marker and SILE.Commands["label"] then
      titleContent[#titleContent + 1] = SU.ast.createCommand("label", { marker = marker })
    end
    -- Running headers
    -- See HACK HOOK above
    if titleHookContent then
      -- As for labels, underlying info nodes will interact with indents/breaks, so we
      -- also try to get them in the title. But we do not want the main style to
      -- be applied to them, so we hid them in a short-term command...
      titleContent[#titleContent + 1] = SU.ast.createCommand("sectioning:hack:hook")
    end
    SILE.call("style:apply:paragraph", { name = name }, titleContent)
  end, "Apply sectioning")

  self:registerCommand("internal:open-spread", function (options, _)
    -- NOTE: We do not use the "open-double-page"/"open-spread" from the twoside
    -- package as it has doesn't have the nice logic we have here:
    --  - check we are not already at the top of a page
    --  - disable header and folio on blank pages
    -- I really had hard times to make this work correctly. It now
    -- seems ok, but it might be fragile.
    local parity = SU.required(options, "parity", "sectioning")
    if parity ~= "odd" and parity ~= "even" then
      SU.error("Invalid parity '"..parity.."' for internal open-spread")
    end

    SILE.typesetter:leaveHmode() -- Important, flushes nodes to output queue.
    if hasContentInCurrentPage() then
      -- We are not at the top of a page, eject the current content.
      SILE.call("supereject")
    end
    SILE.typesetter:leaveHmode() -- Important again...
    -- ... so now we are at the top of a page, and only need
    -- to add a blank page if we have not landed on the right one.
    local isOnOddPage = SILE.documentState.documentClass:oddPage()
    local needBlankPage = (parity == "odd" and not isOnOddPage)
                          or (parity == "even" and isOnOddPage)
    if needBlankPage then
      SILE.typesetter:typeset("") -- Some non glue empty content to force a page break.
      SILE.typesetter:leaveHmode()
      -- Disable headers and footers if we can... i.e. the
      -- supporting class loaded all the necessary commands.
      if SILE.Commands["nofoliothispage"] then
        SILE.call("nofoliothispage")
      end
      if SILE.Commands["noheaderthispage"] then
        SILE.call("noheaderthispage")
      end
      SILE.call("supereject")
    end
    SILE.typesetter:leaveHmode() -- and again!
  end, "Open a double page without header and folio")

  self:registerCommand("open-on-odd-page", function (_, _)
    SILE.call("internal:open-spread", { parity = "odd" })
  end, "Open an odd page, with a blank page without header and folio before if needed")

  self:registerCommand("open-on-even-page", function (_, _)
    SILE.call("internal:open-spread", { parity = "even" })
  end, "Open an even page, with a blank page without header and folio before if needed")

  self:registerCommand("open-on-any-page", function (_, _)
    SILE.typesetter:leaveHmode() -- Important, flushes nodes to output queue.
    if hasContentInCurrentPage() then
      -- We are not at the top of a page, eject the current content.
      SILE.call("supereject")
    end
    SILE.typesetter:leaveHmode()
  end, "Open a single page")

  self:registerCommand("hardbreak", function (_, _)
    -- We don't want to use a cr here, because it would affect parindents,
    -- insert a parskip, and maybe other things.
    -- It's a bit tricky to handle a hardbreak depending on the alignment
    -- of the paragraph:
    --    justified = we can't use a break, a cr (hfill+break) would work
    --    ragged left = we can't use a cr
    --    centered = we can't use a cr
    --    ragged right = we don't care, a break is sufficient and safer
    -- Knowning the alignment is not obvious, neither guessing it from the skips.
    -- Using a parfillskip seems to do the trick, but it's maybe a bit hacky.
    -- This is nevertheless what would have occurred with a par.
    SILE.typesetter:pushGlue(SILE.settings:get("typesetter.parfillskip"))
    SILE.call("break")
  end, "Insert a hard break respecting the paragraph alignment")

end

package.documentation = [[\begin{document}
The \autodoc:package{resilient.sectioning} package provides a generic framework
for sectioning commands, expanding upon the concepts introduced
in the \autodoc:package{resilient.styles} package.
Class and package implementors are free to use the abstractions proposed here,
if they find them sound with respect to their goals.

The core idea is that all sectioning commands could be defined via
approriate styles and that any user-friendly command for typesetting a section
is then just a convenience wrapper. For that purpose, the package defines
two things:

\begin{itemize}
\item{The sectioning style specification support.}
\item{A generic \autodoc:command{\sectioning} command.}
\end{itemize}

\smallskip

The latter is quite simple:

\raggedright{\language[main=und]{\autodoc:command{\sectioning[style=<name>,
  numbering=<boolean>, toc=<boolean>, marker=<string>]{<content>}}}}

\smallskip
It takes a (sectioning) style name, boolean options specifying whether
that section is numbered and goes in the table of contents\footnote{Only honored if the
sectoning style defines a TOC level.}, an optional marker name
(which can be used to refer to the section with a cross-references packages) and a content
logically representing the section title. It could obviously be directly used as-is.
With such a thing in our hands, defining, say, a \code{\\chapter} command is just,
as stated above, a “convenience” helper. Let us do it in Lua, to be able to support
all options, as a class would actually do.

\begin[type=autodoc:codeblock]{raw}
self:registerCommand("chapter", function (options, content)
    options.style = "sectioning-chapter"
    SILE.call("sectioning", options, content)
end, "Begin a new chapter")
\end{raw}

The only assumption here being, obviously, that a \code{sectioning-chapter}
style has been appropriately defined to convey all the usual features a sectioning
command may need.

The package also provides the \autodoc:command{\open-on-odd-page}, \autodoc:command{\open-on-even-page} and \autodoc:command{\open-on-any-page} low level commands, which are used by the styling specifications.
\end{document}]]

return package
