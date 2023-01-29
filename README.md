# resilient.sile

[![license](https://img.shields.io/github/license/Omikhleia/resilient.sile?label=License)](LICENSE)
[![Luacheck](https://img.shields.io/github/actions/workflow/status/Omikhleia/resilient.sile/luacheck.yml?branch=main&label=Luacheck&logo=Lua)](https://github.com/Omikhleia/resilient.sile/actions?workflow=Luacheck)
[![Luarocks](https://img.shields.io/luarocks/v/Omikhleia/resilient.sile?label=Luarocks&logo=Lua)](https://luarocks.org/modules/Omikhleia/resilient.sile)

This collection of classes and packages for the [SILE](https://github.com/sile-typesetter/sile)
typesetting system provides advanced book classes and tools, 

This is the successor of my previous “[Omikhleia’s classes & packages for SILE](https://github.com/Omikhleia/omikhleia-sile-packages)”,
fully redesigned for SILE v0.14 or upper, and provided as a separate installable module.

Besides all the changes from SILE v0.12 to v0.14 and its new package and class APIs, this redesign entails
many more things, with breaking changes (consider it as v2.0 of the former solution).

It therefore comes under a new name (also used as a namespace here and there), **resilient**.
The name is a pun on "SILE" (as, after all, the initial target was always on redoing a book class that would satisfy my
requirements), but there will be a bit more to it than that, which might become more visible when the collection
expands.

This collection offers:
- At its core, a challenging and interesting “styling” paradigm, allowing to configure many
  styling decisions with a consistent and unified approach, abstracting the complexity.
- A pretty strong “book” class, with:
  - A mind-bogling choice of sound page layouts — old-fashioned or modern,
  - Almost everything you may expect for such a class: parts, chapters, sections, subsection, subsubsection…
  - Highly configurable table of contents, headers, footers, footnotes and sectioning environments,
  - And other useful features, from cross-references to advanced captioned figure and table environments, and more…
  - A great parity with Markdown, including many Pandoc-like extensions.
- A lightweight “résumé” class, for you to produce a colorful and yet professional-looking _curriculum vitæ_.

## Installation

These packages require SILE v0.14 or upper.

Installation relies on the **luarocks** package manager.

To install the latest development version and all its dependencies (see below), you may use the provided “rockspec”:

```
luarocks --lua-version 5.4 install --server=https://luarocks.org/dev resilient.sile
```

(Adapt to your version of Lua, if need be, and refer to the SILE manual for more
detailed 3rd-party package installation information.)

## See also

This collection also imports several modules also provided separately, would you find them useful on their own:

- [Paragraph boxes, framed boxes and tables](https://github.com/Omikhleia/ptable.sile)
- [Cross-references](https://github.com/Omikhleia/labelrefs.sile)
- [Superscripts and subscripts](https://github.com/Omikhleia/textsubsuper.sile)
- [Barcodes](https://github.com/Omikhleia/barcodes.sile) (for ISBNs, etc.)
- [Couyards](https://github.com/Omikhleia/couyards.sile) (typographic ornaments)
- [Markdown support](https://github.com/Omikhleia/markdown.sile)

Other packages that this author uses with this collection, but which are not mandatory
and are not yet made a dependency (for now, at least):

- [Printer options](https://github.com/Omikhleia/printoptions.sile) (image resolution tuning
  and vector rasterization, would you want to use a professional printer or print-on-demand services)
- [Fancy table of contents](https://github.com/Omikhleia/fancytoc.sile) (an alternative two-level table of contents with nice curly braces)

When used with this collection, the Markdown packages and the fancy table of contents are
leveraged with additional capabilities.

## Usage

A complete PDF version of the documentation (but not necessarily always the latest) should be
available [HERE](https://drive.google.com/file/d/1f54qDEGWaN-MFN932x-t0jm3V-5VSHee/view?usp=sharing)

## License

All code is under the MIT License.

The documentation is under CC-BY-SA 2.0.

The examples (i.e. anythings in the "examples" folder) have varying licenses and some are
used by courtesy of the authors. Please check their respective license or ask, in case of
doubts, for details and exact licensing terms.
