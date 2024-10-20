# resilient.sile

[![license](https://img.shields.io/github/license/Omikhleia/resilient.sile?label=License)](LICENSE)
[![Luacheck](https://img.shields.io/github/actions/workflow/status/Omikhleia/resilient.sile/luacheck.yml?branch=main&label=Luacheck&logo=Lua)](https://github.com/Omikhleia/resilient.sile/actions?workflow=Luacheck)
[![Luarocks](https://img.shields.io/luarocks/v/Omikhleia/resilient.sile?label=Luarocks&logo=Lua)](https://luarocks.org/modules/Omikhleia/resilient.sile)

This collection of classes and packages for the [SILE](https://github.com/sile-typesetter/sile) typesetting system provides advanced classes, packages and tools for streamlining the production of high-quality books and documents.

It offers a wide range of features, including:
- At its core, a challenging and interesting “styling” paradigm, allowing to configure many styling decisions with a consistent and unified approach, abstracting the complexity.
- A “master document” format, for easily combining your content from multiple files into a consistent work.
- A pretty strong “book” class, with:
  - A mind-bogling choice of sound page layouts — old-fashioned or modern,
  - Almost everything you may expect for such a class: parts, chapters, sections, subsections, subsubsections…
  - Highly configurable table of contents, headers, footers, footnotes and sectioning environments,
  - And other useful features, from cross-references to advanced captioned figure and table environments, and more…
  - A great parity with Markdown, including many Pandoc-like extensions, and with Djot
- A lightweight “résumé” class, for you to produce a colorful and yet professional-looking _curriculum vitæ_.

Whether you a seasoned typist or a beginner, the _re·sil·ient_ collection aims at making the process of creating beautiful books as simple as possible, from front cover to back cover, using a lightweight markup language for most of the content, if not all of it.

## Demonstration

Do you want to see what you can do with this collection? In addition to the nice “User Guide” documentation (see just below), there’s a whole repository of books and show-cases: [Awesome SILE books](https://github.com/Omikhleia/awesome-sile-books).

## Documentation

A complete PDF version of the documentation (but not necessarily always the latest) should be available [HERE](https://drive.google.com/file/d/1f54qDEGWaN-MFN932x-t0jm3V-5VSHee/view?usp=sharing), or in our [Calaméo bookshelf](https://www.calameo.com/accounts/7349338).

Did we say complete? Well, we lied a bit. For Markdown and Djot input, there is also a dedicated booklet,available [HERE](https://drive.google.com/file/d/19VfSMmfBIZwr43U-W842IkSE349wdgZb/view?usp=sharing) — or, again, in our [Calaméo bookshelf](https://www.calameo.com/accounts/7349338).


## Installation

These packages require SILE v0.14 or upper (recommended: SILE v0.15.5 or upper).

Installation relies on the **luarocks** package manager.
See its installation instructions on the [LuaRocks](https://luarocks.org/) website.

To install the latest version and all its dependencies (see below):

```
luarocks install resilient.sile
```

(Refer to the SILE manual for more detailed 3rd-party package installation information and configuration options.)

## See also

This collection also imports several modules also provided separately, would you find them useful on their own:

- [Paragraph boxes, framed boxes and tables](https://github.com/Omikhleia/ptable.sile)
- [Cross-references](https://github.com/Omikhleia/labelrefs.sile)
- [Superscripts and subscripts](https://github.com/Omikhleia/textsubsuper.sile)
- [Barcodes](https://github.com/Omikhleia/barcodes.sile) (for ISBNs, etc.)
- [QR codes](https://github.com/Omikhleia/qrcode.sile)
- [Couyards](https://github.com/Omikhleia/couyards.sile) (typographic ornaments)
- [Printer options](https://github.com/Omikhleia/printoptions.sile) (image resolution tuning
  and vector rasterization, would you want to use a professional printer or print-on-demand services)
- [Fancy table of contents](https://github.com/Omikhleia/fancytoc.sile) (an alternative two-level table of contents with nice curly braces)
- [Textual graphics embedders](https://github.com/Omikhleia/embedders.sile) (support for Graphviz, Lilypond, &c)
- [Markdown](https://github.com/Omikhleia/markdown.sile) (support for Markdown, Djot etc.)
- [Pie charts](https://github.com/Omikhleia/piecharts.sile) (support for pie charts)

When used with this collection, the Markdown packages and the fancy table of contents are leveraged with additional capabilities.

## Historical note

This collection is the successor of “[Omikhleia’s classes & packages for SILE](https://github.com/Omikhleia/omikhleia-sile-packages)”, fully redesigned for SILE v0.14 or upper, and provided as a separate installable module.

Besides all the changes from SILE v0.12 to v0.14, and its new package and class APIs, the redesign entails many more things, with breaking changes.It can be considered as a v2.x of the former solution.

It therefore comes under a new name (also used as a namespace here and there), **resilient**.
The name is a pun on “SILE” (as, after all, the initial target was always on redoing a book class that would satisfy my requirements), but there is a bit more to it than that, which might become more visible when the collection expands.

## License

All code is under the MIT License.

The documentation is under CC-BY-SA 2.0.

The examples (i.e. anythings in the “example” folder) have varying licenses and some are used by courtesy of the authors.
Please check their respective license or ask, in case of doubts, for details and exact licensing terms.
