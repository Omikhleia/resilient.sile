# Styling concepts & workflow

## Using a style file

![The resilient styling workflow.](manual-styling/workflow.dot){width=9cm}

When processing your master document, you can provide a style file for it,
going by the same name, and the extension `.sty`.

If you don't have such a style file, no problem. Upon running SILE
for the first time on your document, you obtain, besides the usual PDF,
an output style file (as well as a bunch of other files, not represented
above, used for resolving tables of contents, cross-references, etc.)

All resilient classes and compliant packages provide default style
definitions. When an input style file is available, it is only
overwritten for missing styles.[^basics-overwrite-styles]
Typically, if you add another package dependency to your document,
you will get a bunch of additional style definitions. As a result,
the output style file is complete with the new definitions, keeping
other changes you might have applied to it.[^basics-unused-styles]

In order to customize the styling of a document, you can therefore
edit that style file, change the styles you want to alter,
and process the document again.

Would you wish to reset some unfortunate changes,
but you do not remember what the original settings were,
then remove those styles, and process the document again.
The default style definitions will be back in the output file.

Preciously save your style file with your document; copy and
rename it at convenience for use with other documents.

[^basics-overwrite-styles]: Well, it's not fully true. The
output style files has all styles sorted alphabetically,
and comments may be added to it. What we mean is that
the existing definitions are kept.

[^basics-unused-styles]: An implication here is that the style
file may contain unused styles. We might address in a future
version the possibility to identify and mark those styles.

## The purpose of styles

Styles intend to address the question of customization in a consistent, homogeneous,
unified and extensible way, with a simple but efficient inheritance mechanism.

How can you customize the various environments you use in your writings?
For instance, in order to apply a different font or even a color to section
titles, a specific rendering for some entry levels in a table of contents,
and different vertical skips here or there?
The styling paradigm offers a powerful generic abstraction towards that
goal.

### An opinionated note on alternatives {.unnumbered .notoc}

If you ever used (La)TeX, one possible way is to provide "hooks" that the user
can change. At places, SILE follows that approach too---either via commands that
the user can re-define, or via settings.[^styles-vs-hooks]
But this solution is not fully satisfying and raises several concerns.

 - Package and class authors would have to ensure an adequate hook or setting
   is provided in all cases that would need it; that is, at every place where
   there would have been be some "hard-coded" decision otherwise.[^styles-hard-coded]
   The number of necessary hooks can quickly become insane, without warranty
   that the approach remains consistent from a package to another...
 - Hooks are, by definition, programmable escapes to full-fledged commands
   that could do anything beyond they initial purpose. It may have some interest
   (and power), but it goes far beyond the issue of styling and can also have a
   lot of unintended side effects. There's some strong "separation of concerns"
   issue.

In many ways, using hooks sounds very clumsy and cumbersome. It's somehow
an _ad hoc_ answer to the initial question,[^styles-hook-latex] rather
than a real solution.

Styles are a different approach to the same core question.
Actually, it is what most modern word-processing software have been doing
for a while, be it Microsoft Word or Libre/OpenOffice and cognates...
They all introduce the concept of styles too. Web programmers also know
than even HTML abstracts styling decisions to Cascading Style Sheets.

The resilient styling paradigm aims at implementing such ideas, or a subset
of them. We do not intend to cover all the inventory of features provided
via styles in the above-mentioned software.
Some of them already have matching mechanisms, or even of a superior
design, in SILE. Yet, the style specifications make it easier, in our
opinion, for the end-user to customize his output. It also makes it
easier for class and package designers to abstract styling decisions,
by reusing the same mechanism in their own code, rather than reinventing
the wheel.

[^styles-vs-hooks]: Most "legacy" classes and packages in SILE rely on hooks,
such as `pullquote:font` and `book:right-running-head-font`, to quote just a few.
None of these seem to have the same type of name. Their scope too is not always
clear. What if one also wants, for instance, to specify a color? Of course,
in many cases, the hook could be redefined to also apply the expected color
to the content... But, er, isn’t it called `...font`? Something looks amiss!

[^styles-hard-coded]: One can doubt hooks would be provided for everything.
Consider SILE's default book class: At this time, the vertical skips around
sectioning commands are _simply_ hard-coded. Likewise, the decision to cancel
paragraph indentation after a section title is _also_ hard-coded, although
this is not appropriate in all contexts. French typography, for instance,
always expects a paragraph indentation, _even_ after section titles.

[^styles-hook-latex]: It's also very LaTeX-like. Which is not necessarily
wrong, there is no offense intended here. It's just a statement of fact.

