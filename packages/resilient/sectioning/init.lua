--
-- Generic sectioning command and styles for SILE
-- An extension of the "styles" package and the sectioning paradigm
-- 2021-2023, Didier Willis
-- License: MIT
--
local base = require("packages.resilient.base")

local package = pl.class(base)
package._name = "resilient.sectioning"

function package:_init (options)
  base._init(self, options)
  self.class:loadPackage("counters")
end

local interWordSpace = function ()
  -- Returns a glue corresponding to the current interword space (depending on settings).
  local fontOpts = SILE.font.loadDefaults({})
  return SILE.shaper:makeSpaceNode(fontOpts, { width = "1spc"}) -- FIXME not sure of the 1spc here.
end

function package:registerCommands ()

  local resolveSectionStyleDef = function (name)
    local stylespec = self:resolveStyle(name)
    if stylespec.sectioning then
      return {
        counter = stylespec.sectioning.counter or
          SU.error("Sectioning style '"..name.."' must have a counter"),
        display = stylespec.sectioning.display or "arabic",
        level = stylespec.sectioning.level or 1,
        open = stylespec.sectioning.open, -- nil = do not open a page
        numberstyle = stylespec.sectioning.numberstyle,
        goodbreak = stylespec.sectioning.goodbreak,
        toclevel = stylespec.sectioning.toclevel,
        bookmark = stylespec.sectioning.bookmark,
        hook = stylespec.sectioning.hook,
      }
    end
    SU.error("Style '"..name.."' is not a sectioning style")
  end

  self:registerCommand("sectioning", function (options, content)
    local name = SU.required(options, "style", "sectioning")
    local numbering = SU.boolean(options.numbering, true)
    local toc = SU.boolean(options.toc, true)
    local marker = options.marker

    local secStyle = resolveSectionStyleDef(name)

    -- 1. Handle the page-break: opening page: "unset", "odd" or "any"
    --    (Would "even" be useful? I do not think is has any actual use)
    if secStyle.open and secStyle.open ~= "unset" then
      -- Sectioning style that causes a page-break.
      if secStyle.open == "odd" then
        SILE.call("open-on-odd-page")
      else -- Case: any
        SILE.call("open-on-any-page")
      end
      local sty = self:resolveStyle(name) -- Heavy-handed, but I was tired.
      if sty.paragraph and sty.paragraph.skipbefore then
        -- Ensure the vertical skip will be applied even if at the top of
        -- the page. Introduces a line, though. I haven't found how to avoid
        -- it :(
        SILE.typesetter:initline()
      end
    else
      -- Sectioning style that doesn't cause a forced page-break.
      -- We may insert a goodbreak, though.
      SILE.typesetter:leaveHmode()
      if SU.boolean(secStyle.goodbreak, true) then
        SILE.call("goodbreak")
      end
    end

    -- 2. Handle the style hook if specified.
    --    (Pass the user-defined options + the counter and level,
    --    so it has the means to compute and show it if it wants)
    if secStyle.hook then
      local hookOptions = pl.tablex.copy(options)
      hookOptions.counter = secStyle.counter
      hookOptions.level = secStyle.level
      SILE.call(secStyle.hook, hookOptions, content)
    end

    -- 3. Process the section content
    SILE.call("style:apply:paragraph", { name = name }, function ()
      -- 3A. Counter for numbered sections
      local number
      if numbering then
        SILE.call("increment-multilevel-counter", {
          id = secStyle.counter,
          level = secStyle.level,
          display = secStyle.display
        })
        number = self.class.packages.counters:formatMultilevelCounter(
          self.class:getMultilevelCounter(secStyle.counter), { noleadingzeros = true }
        )
      end

      -- 3B. TOC entry)
      local toclevel = secStyle.toclevel and SU.cast("integer", secStyle.toclevel)
      local bookmark = SU.boolean(secStyle.bookmark, true)
      if toclevel and toc then
        SILE.call("tocentry", { level = toclevel, number = number, bookmark = bookmark }, SU.subContent(content))
      end

      -- 3C. Show entry number
      if numbering then
        if secStyle.numberstyle then
          local numSty = self:resolveStyle(secStyle.numberstyle)
          local pre = numSty.numbering and numSty.numbering.before
          local post = numSty.numbering and numSty.numbering.after
          local kern = numSty.numbering and numSty.numbering.kern or interWordSpace()

          SILE.call("style:apply", { name = secStyle.numberstyle }, function ()
            if pre and pre ~= "false" then SILE.typesetter:typeset(pre) end
            SILE.typesetter:typeset(number)
            if post and post ~= "false" then SILE.typesetter:typeset(post) end
          end)
          if SU.boolean(numSty.numbering and numSty.numbering.standalone, false) then
            SILE.call("break") -- HACK. Pretty weak unless the parent paragraph style is ragged.
          else
            SILE.call("kern", { width = kern })
          end
        else
          SILE.typesetter:typeset(number)
          SILE.call("kern", { width = interWordSpace() })
        end
      end
      -- 3D. Section (title) content
      SILE.process(content)
      -- 3E. Cross-reference label
      -- If the \label command is defined, assume a cross-reference package
      -- is loaded and allow specifying a label marker. This makes it less clumsy
      -- than having to put it in the section title content, or just after the section
      -- (with the risk of impacting indent/noindent and novbreak decisions here)
      if marker and SILE.Commands["label"] then SILE.call("label", { marker = marker }) end
    end)
    -- Was present in the original book class for section and subsection
    -- But seems to behave weird = cancelled for now.
    -- SILE.typesetter:inhibitLeading()
  end, "Apply sectioning")

  self:registerCommand("open-on-odd-page", function (_, _)
    -- NOTE: We do not use the "open-double-page" from the two side
    -- package as it has doesn't have the nice logic we have here:
    --  - check we are not already at the top of a page
    --  - disable header and folio on blank even page
    -- I really had hard times to make this work correctly. It now
    -- seems ok, but it might be fragile.
    SILE.typesetter:leaveHmode() -- Important, flushes nodes to output queue.
    if #SILE.typesetter.state.outputQueue ~= 0 then
      -- We are not at the top of a page, eject the current content.
      SILE.call("supereject")
    end
    SILE.typesetter:leaveHmode() -- Important again...
    -- ... so now we are at the top of a page, and only need
    -- to add a blank page if we have not landed on an odd page.
    if not SILE.documentState.documentClass:oddPage() then
      SILE.typesetter:typeset("")
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
    if #SILE.typesetter.state.outputQueue ~= 0 then
      -- We are not at the top of a page, eject the current content.
      SILE.call("supereject")
    end
    SILE.typesetter:leaveHmode()
  end, "Open a single page")

end

package.documentation = [[\begin{document}
\use[module=packages.resilient.lists]

This package provides a generic framework for sectioning commands, expanding upon
the concepts introduced in the \autodoc:package{resilient.styles} package.
Class and package implementors are free to use the abstractions proposed here,
if they find them sound with respect to their goals.

The core idea is that all sectionning commands could be defined via
approriate styles and that any user-friendly command for typesetting a section
is then just a convenience wrapper. For that purpose, the package defines
two things:

\begin{itemize}
\item{A sectionning style specification.}
\item{A generic \code{\\sectioning} command,}
\end{itemize}

\smallskip

Let’s start with the latter, which is the simplest.

\begin{codes}
\code{\\sectioning[style=\doc:args{name},\par
\qquad{}numbering=\doc:args{true|false}, toc=\doc:args{true|false}]\{\doc:args{content}\}}
\end{codes}

It takes a (sectioning) style name, boolean options specifying whether
that section is numbered and goes in the table of contents\footnote{Only honored if the
style defines a TOC level, but we will see that in a moment.}, an optional marker name
(which can be used to refer to the section with a cross-references packages) and a content
logically representing the section title. It could obviously be directly used as-is.
With such a thing in our hands, defining, say, a \code{\\chapter} command is just,
as stated above, a “convenience” helper. Let us do it in Lua, to be able to support
all options, as a class would actually do.

\begin{codes}
self:registerCommand("chapter", function (options, content)\par
\quad{}options.style = "sectioning-chapter"\par
\quad{}SILE.call("sectioning", options, content)\par
end, "Begin a new chapter")\par
\end{codes}

The only assumption here being, obviously, that a \code{sectioning-chapter}
style has been appropriately defined to convey all the usual features a sectioning
command may need. Before introducing its syntax, we need to clarify what “sectioning”
means for us.

\begin{itemize}
\item{Of course, in the most basic sense, we imply the usual “parts”, “chapters”,
  “sections”, etc. found in book or article classes.}
\item{But thinking further, it could be any structural division, possibly tranverse
  to the above—for instance, series of questions & answers, figures and tables.}
\end{itemize}

\smallskip
With these first assumptions in mind, let’s summarize the requirements:

\begin{enumerate}
\item{The section title is usually typeset in a certain font, etc.—It has a character style.}
\item{A section usually introduces a certain spacing after or before it, etc.—It has a paragraph style.}
\item{Sections are usually numbered according to some scheme, which may be hierarchical, and do not
  necessarily all use the same scheme.—It has a named (multi-level) counter, a level in that counter
  and a display format at that level. Usually, we wrote, but we can consider it is even mandatory, or we do not really
  need to call this a section.}
\item{Sections may go into a table of contents at some specified level.—It may hence have a TOC level.}
\item{Sections going into a table of contents may as well possibly go in the PDF bookmarks (outline).}
\item{Sections may trigger a page break and may even need to open on an odd page.}
\item{Sections, especially those who do not cause a (forced) page break, may recommmend
  allowing a page break before them (so usual that it should default to true).}
\item{The numbering, when used, may need some text strings prepended or appended to it.}
\item{Sections can be interdependent, in the sense that some of them may reset the counters
  of others, or can act upon other unrelated counters (e.g. footnotes), request to be added
  to page headers, and so on.—The list of possibilities could be long here and very dependent
  on the kind of structure one considers, and it would be boresome to invent a syntax
  covering all potential needs, so some sort of “hook” has at least to be provided (more on that later).}
\end{enumerate}

\smallskip
With the exception of the two first elements, which are already covered by the \autodoc:package{resilient.styles}
package, the rest is new. Here is therefore the specification introduced in this package.

\begin{codes}
\\style:define[name=\doc:args{name}]\{
\par\quad\\font[\doc:args{font specification}]
\par\quad\\color[\doc:args{color specification}]
\par\quad\\paragraph[\doc:args{paragraph specification}]
\par\quad\\sectioning[
\par\qquad{}counter=\doc:args{counter}, level=\doc:args{integer}, display=\doc:args{display},
\par\qquad{}toclevel=\doc:args{integer},
\par\qquad{}bookmark=\doc:args{true|false},
\par\qquad{}open=\doc:args{unset|any|odd},
\par\qquad{}goodbreak=\doc:args{true|false},
\par\qquad{}numberstyle=\doc:args{style name},
\par\qquad{}hook=\doc:args{command name}
\par]\}
\end{codes}

That’s a whole bunch of new pseudo-commands in our style specifications, and class or
package implementors may frown upon such a long list. On the other hand, many have default
values and the simple inheritance mechanism provided by the styles also allows one
to reuse existing base specifications. In this author’s opinion, it is quite flexible
and clear. The two last options, however, still require a clarification.

The \code{numberstyle} refers by its name to another style, similar to those
used for table of contents and enumerations, i.e. possibly containing, in addition to
regular character style elements, how to actually present the section number.
\begin{itemize}
\item{The text to prepend to the number,}
\item{The text to append to the number,}
\item{The kerning space added after it (defaults to an inter-word space, i.e. usually
      stretchable and shrinkable, depending on the relevant SILE settings).}
\item{And an additional option, here, whether the formatted number has to be on a standalone
  line rather than just before the section title.—Chapters and parts, for instance,
  may often use it.}
\end{itemize}

\begin{codes}
\par\quad{}\\numbering[before=\doc:args{string}, after=\doc:args{string}, kern=\doc:args{length},
\par\qquad{}standalone=\doc:args{false|true}]
\end{codes}

And yet, we haven’t addressed the various “side-effects” a section may have on other sections,
page headers, folios, etc. As noted, we just provide a command name to be called upon
entering the section (after any page break, if it applies.) It is passed the section title
and the same options that were invoked on the \code{\\sectioning} call,
plus \code{counter} and \code{level}, would the hook need to show the relevant counter
somewhere (e.g. in a page header). One could put any code here, obviously, and defeat the point of the whole
style system. But if implementors play the game and are concerned with separation of
concerns, it will just do the minimum things it should—and in many cases, it may be so
simple that one could even do it in SILE language rather than in Lua.

You may remember, from the \autodoc:package{resilient.styles} package, that one of the
rationale for introducing styles was to avoid command “hooks” with different names,
unknown scopes and effects, and also to formalize our expectations with a
regular format that one could easily tweak. Resorting to a such a complex specification and
eventually even a hook may look amiss. Still, there are obvious benefits in the proposed
paradigm:
\begin{itemize}
\item{Style inheritance and reusability.}
\item{The fact that a user can tweak most aspects in a pretty standard way, e.g.
  adjust a mere skip, a font size, etc. without having to know how it is coded.}
\item{For class (or package) implementors, the possibility to focus on proper
  sectioning and styling, ending up with a class that is reduced to a bare
  minimum.}
\end{itemize}
\end{document}]]

return package
