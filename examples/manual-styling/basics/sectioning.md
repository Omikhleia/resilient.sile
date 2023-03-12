## Sectioning styles

Before introducing the syntax for this style specification, we may need to clarify
what "sectioning" means for us.

 - Of course, in the most basic sense, we imply the usual “parts”, “chapters”,
   “sections”, etc. found in book or article classes.
 - But thinking further, it may be any structural division, possibly tranverse
   to the above—for instance, series of questions & answers, figures and tables.

With these first assumptions in mind, let’s summarize the requirements:

 - The section title is usually typeset in a certain font, etc.—It has a character style.
 - A section usually introduces a certain spacing after or before it, etc.—It has a
   paragraph style.
 - Sections are usually numbered according to some scheme, which may be hierarchical,
   and do not necessarily all use the same scheme.—It has a named (multi-level) counter,
   a level in that counter and a display format at that level. _Usually,_ we just wrote,
   but we can consider it is even mandatory, or we do not really need to call this
   a section.
 - Sections may go into a table of contents at some specified level. Hence, they may
   have a ToC level.
 - Sections going into a table of contents may as well possibly go in the PDF bookmarks
   (outline).
 - Sections may trigger a page break and may even need to open on an odd page.
 - Sections, especially those who do not cause a (forced) page break, may recommmend
   allowing a page break before them (so usual that it should default to true).
 - Sections can be interdependent, in the sense that some of them may reset the counters
   of others, or can act upon other unrelated counters (e.g. footnotes), request to be added
   to page headers, and so on.—The list of possibilities could be long here and very dependent on the kind of structure one considers, and it would be boresome to invent a
   syntax covering all potential needs, so some sort of “hook” has at least to be provided
   (more on that later).
-  The main numbering, when used, may need some text strings prepended or appended to it,
   (e.g. "Chapter 1.")
 - When added to page headers (or in similar contexts, as per the supporting class
   design, one may want the section number to appear or not, and to be possibly
   formatted in a different way than in the ToC or in the main text flow.
 - When referenced (with the appropriate cross-reference solution), yet another number
   style may be wanted (e.g. "chap. 1").

With the exception of the two first elements, which are already covered by the character
and paragraph styles, a lot of things have to be addressed.

Here is, therefore, the style specification.

```yaml
⟨sectioning style name⟩:
  style:
    ⟨character style specification⟩
    ⟨paragraph style specification⟩
    sectioning:
      counter:
        id: "⟨counter name⟩"
        level: ⟨integer⟩
      settings:
        toclevel: ⟨integer⟩
        bookmark: true|false
        open: "unset|any|odd"
        goodbreak: true|false
      numberstyle:
        main: "⟨number style name⟩"
        header: "⟨number style name⟩"
        reference: "⟨number style name⟩"
      hook: "⟨command name⟩"
```

That’s a lot of fields. However, many have default values and the simple
inheritance mechanism provided by the styles also allows one to reuse existing
base specifications. In this author’s opinion, it is quite flexible and clear.
The two last options, however, may require a clarification.

For the "main" number style, some sections may expect the number to be on its
own standalone line rather than just before the section title.—Chapters and parts,
for instance, may often use it. This specification, therefore, supports an extra
`standalone` boolean properties on number styles.

We haven’t addressed yet the various “side-effects” a section may have on other sections,
page headers, folios, etc. As noted, we just provide a command name to be called upon
entering the section (after any page break, if it applies). It is passed the section title,
the options you provided on the sectionning command, and the current value of the
`counter` and `level`, would the hook need to show the relevant counter
somewhere (e.g. in a page header).

One of the rationale for introducing styles was to avoid command “hooks” with different
names, unknown scopes and effects, and also to formalize our expectations with a
regular format that one could easily tweak. Eventually resorting to a hook may look amiss.
Still, there are obvious benefits in the proposed paradigm:

 - Style inheritance and reusability.
 - The fact that a user can tweak most aspects in a pretty standard way, e.g.
   adjust a mere skip, a font size, etc. without having to know how it is coded.
 - For class (or package) implementors, the possibility to focus on proper
   sectioning and styling, ending up with a class that is reduced to a bare
   minimum.

