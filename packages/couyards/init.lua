
--
-- A few printer's ornaments ("culs-de-lampe" or "couyards") for SILE
-- 2021, 2022, Didier Willis
-- License: MIT
--
local base = require("packages.base")

local package = pl.class(base)
package._name = "couyards"

-- Trick for ensuring we search resources from the folder containing the package,
-- wherever installed: get the debug location of a function just defined in
-- the current file, remove the initial @  and retrieve the dirname.
local function basepath ()
  return pl.path.dirname(debug.getinfo(basepath, "S").source:sub(2))
end

function package:_init (options)
  self.basepath = basepath()
  base._init(self, options)
end

function package:registerCommands ()
  self:registerCommand("couyard", function (options, _)
    SILE.require("packages/svg")
    local n = SU.cast("integer", options.type or 1)
    local width = options.width and SU.cast("measurement", options.width == "default" and "7em" or options.width)
    local height = options.height and SU.cast("measurement", options.height =="default" and "0.9em" or options.height)
    if width ~= nil and height ~= nil then SU.error("Specify only one of width or height") end
    if width == nil and height == nil then height = "0.9em" end

    if n == nil or n < 0 or n > 9 then SU.error("Invalid culs-de-lampe type") end
    local ornament = self.basepath .. "/culs-de-lampe/" .. "cul-de-lampe-" .. n .. ".svg"
    SILE.typesetter:leaveHmode()
    SILE.call("center", {}, function()
      if height ~= nil then
        SILE.call("svg", { src = ornament, height = height })
      else
        SILE.call("svg", { src = ornament, width = width })
      end
    end)
  end)
end

package.documentation = [[\begin{document}
\use[module=packages.url]
\use[module=packages.couyards]
\define[command=pkg-doc-dingbatfont]{\font[family=Symbola]{\process}}

Typographers of the past relied on a number of ornaments to make their books look nicer.

A \em{cul-de-lampe} (plural \em{culs-de-lampe}\kern[width=0.1em]) is a typographic ornament, sometimes called a
\em{pendant}, marking the end of a section of text. The term comes from French, for “bottom of
the lamp” (from the usual shape of the ornament). In French typography, they are also called
\em{couillards} or \em{couyards} (apparently named, erm… after a body part, really). It may be a
single illustration or assembled from fleurons.

A \em{fleuron} is a typographic element or glyph, used either as a punctuation mark or as an
ornament for typographic compositions. Fleurons, hence the name, which also derives from
French, are usually stylized forms of flowers or leaves. The Unicode standard defines several
such glyphs, as \pkg-doc-dingbatfont{❦} (U+2766, floral heart) and rotated versions of it,
\pkg-doc-dingbatfont{❧} (U+2767) and \pkg-doc-dingbatfont{☙} (U+2619). Unicode version 7 even defines many more
glyphs of that type.

In typography, these glyphs are also generically called \em{dingbats} or, when used as a section
divider, a \em{dinkus}. One usual glyph used in the latter case is the \em{asterism,} ⁂ (U+2042).

Whether fonts support these glyphs and how they render them is another topic.
(For instance, here above, we had to switch to the Symbola font for the so-called floral
hearts.)

This author, however, wanted a bit more variety with some old-fashioned ornaments independent
from the selected font. The present \autodoc:package{couyards} package
therefore defines a few such ornaments\footnote{The first seven were converted to SVG from
designs by Tartila \url{https://fr.freepik.com/vecteurs-libre/diviseurs-fleurs-calligraphiques_10837974.htm},
free for personal and commercial usage with proper attribution. Number 8 and 9 are public domain (CC0),
from \url{https://freesvg.org}, and look better at fixed width rather than height. There are hundreds
of similar designs there and this author does not intend to have more than what he requires. The last two were
actually added on a second thought only.},
with the command \autodoc:command{\couyard[type=<n>]}, where \em{n} is a number between 1 and 9.

Without any other option, the ornaments have a fixed height which can
be overridden with the \autodoc:parameter{height=<length>} option, the default
being 0.9em (also corresponding to \autodoc:parameter{height=default}). Showing only the first
seven:

\smallskip
\couyard[type=1]
\couyard[type=2]
\couyard[type=3]
\couyard[type=4]
\couyard[type=5]
\couyard[type=6]
\couyard[type=7]

\smallskip
Alternately, one can set a width with the \autodoc:parameter{width=<length>} option,
either to some length value or to \code{default} (7em).

\smallskip
\couyard[type=1,width=default]
\couyard[type=2,width=default]
\couyard[type=3,width=default]
\couyard[type=4,width=default]
\couyard[type=5,width=default]
\couyard[type=6,width=default]
\couyard[type=7,width=default]

\smallskip
\couyard[type=8,width=default]

\smallskip
\couyard[type=9,width=default]

\smallskip
These two options are exclusive, so as to keep a proper aspect ratio.

\end{document}]]

return package
