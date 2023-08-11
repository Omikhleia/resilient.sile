--
-- Generic sectioning command and styles for SILE
-- An extension of the "styles" package and the sectioning paradigm
-- 2021-2023, Didier Willis
-- License: MIT
--
local base = require("packages.resilient.base")

local ast = require("silex.ast")
local createCommand, createStructuredCommand, subContent
        = ast.createCommand, ast.createStructuredCommand, ast.subContent

local package = pl.class(base)
package._name = "resilient.sectioning"

function package:_init (options)
  base._init(self, options)
  self.class:loadPackage("counters")
end

local function hasContent()
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
    local numSty = secStyle.numberstyle.main and self:resolveStyle(secStyle.numberstyle.main)
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
    if secStyle.hook then
      local hookOptions = pl.tablex.copy(options)
      hookOptions.counter = secStyle.counter.id
      hookOptions.level = secStyle.counter.level

      local titleHookContent
      local numsty = sty.sectioning and sty.sectioning.numberstyle
          and sty.sectioning.numberstyle.header
      if numbering and numsty then
        titleHookContent = {
          createCommand("style:apply:number", { name = numsty, text = number }),
          subContent(content)
        }
      else
        titleHookContent = content
      end
      SILE.call(secStyle.hook, hookOptions, titleHookContent)
    end

    local titleContent = {}
    -- TOC entry
    -- We pass it added to the content, so the paragraph style is applied around it
    -- (and the TOC info node is located in the right place, notwithstanding breaks, skips, etc.).
    -- BUT that will be a problem later if the paragraph style includes input filters or needs
    -- to tweaks (typically, text casing is in that situation).
    -- We could have done things slightly differently (splitting how paragraph style is applied),
    -- but I went another quick and dirty route in the styles package...
    local toclevel = secStyle.settings.toclevel
    local bookmark = secStyle.settings.bookmark
    if toclevel and toc then
      titleContent[#titleContent + 1] =
        createStructuredCommand("tocentry",
          { level = toclevel, number = number, bookmark = bookmark }, subContent(content))
    end

    -- Show section number (if numbering is true AND a main style is defined)
    if numbering then
      if secStyle.numberstyle.main then
        titleContent[#titleContent + 1] =
          createCommand("style:apply:number", { name = secStyle.numberstyle.main, text = number })
        if SU.boolean(numSty.numbering and numSty.numbering.standalone, false) then
          titleContent[#titleContent + 1] =
            createCommand("break") -- HACK. Pretty weak unless the parent paragraph style is ragged.
        end
      end
    end
    -- Section (title) content
    titleContent[#titleContent + 1] = subContent(content)

    -- Cross-reference label
    -- If the \label command is defined, assume a cross-reference package
    -- is loaded and allow specifying a label marker. This makes it less clumsy
    -- than having to put it in the section title content, or just after the section
    -- (with the risk of impacting indent/noindent and novbreak decisions here)
    if marker and SILE.Commands["label"] then
      titleContent[#titleContent + 1] = createCommand("label", { marker = marker })
    end
    SILE.call("style:apply:paragraph", { name = name }, titleContent)
  end, "Apply sectioning")

  self:registerCommand("open-on-odd-page", function (_, _)
    -- NOTE: We do not use the "open-double-page" from the two side
    -- package as it has doesn't have the nice logic we have here:
    --  - check we are not already at the top of a page
    --  - disable header and folio on blank even page
    -- I really had hard times to make this work correctly. It now
    -- seems ok, but it might be fragile.
    SILE.typesetter:leaveHmode() -- Important, flushes nodes to output queue.
    if hasContent() then
      -- We are not at the top of a page, eject the current content.
      SILE.call("supereject")
    end
    SILE.typesetter:leaveHmode() -- Important again...
    -- ... so now we are at the top of a page, and only need
    -- to add a blank page if we have not landed on an odd page.
    if not SILE.documentState.documentClass:oddPage() then
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

  self:registerCommand("open-on-any-page", function (_, _)
    SILE.typesetter:leaveHmode() -- Important, flushes nodes to output queue.
    if hasContent() then
      -- We are not at the top of a page, eject the current content.
      SILE.call("supereject")
    end
    SILE.typesetter:leaveHmode()
  end, "Open a single page")

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

The package also provides the \autodoc:command{\open-on-odd-page} and
\autodoc:command{\open-on-any-page} low level commands, which are used
by the styling specifications.
\end{document}]]

return package
