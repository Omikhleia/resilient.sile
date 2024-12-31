--
-- Some common shorthands and abbreviations
-- 2021-2023, Didier Willis
-- License: MIT
--
local base = require("packages.base")

local package = pl.class(base)
package._name = "resilient.abbr"

function package:_init (options)
  base._init(self, options)
  self.class:loadPackage("textsubsuper")
end

function package:registerCommands ()
  self:registerCommand("abbr:nbsp", function (options, _)
    local fixed = SU.boolean(options.fixed, false)
    local widthsp = SILE.shaper:measureSpace(SILE.font.loadDefaults({}))
    if fixed then
      SILE.call("kern", { width = widthsp.length })
    else
      SILE.call("kern", { width = widthsp })
    end
  end, "Inserts a non-breakable inter-word space (by default shrinkable and stretchable, unless fixed=true)")

  self:registerCommand("abbr:no:fr", function (_, content)
    SILE.typesetter:typeset("n")
    SILE.call("textsuperscript", {}, { "o" })
    SILE.call("abbr:nbsp")
    SILE.process(content)
  end, "Formats an French number as, in n° 5 (but properly typeset)")

  self:registerCommand("abbr:no:en", function (_, content)
    SILE.typesetter:typeset("no.")
    SILE.call("abbr:nbsp")
    SILE.process(content)
  end, "Formats an English number, as in no. 5")

  self:registerCommand("abbr:no", function (_, content)
    local lang = SILE.settings:get("document.language")
    -- We only need the language code, so truncate any BCP-47 tag
    lang = lang:match("([^%-_]+)")
    if lang and SILE.Commands["abbr:no:"..lang] then
      SILE.call("abbr:no:"..lang, {}, content)
    else
      SU.warn("Language not supported for abbr:no, fallback to English")
      SILE.call("abbr:no:en", {}, content)
    end
  end, "Formats an number, as in no. 5, but depending on language")

  self:registerCommand("abbr:nos:fr", function (_, content)
    SILE.typesetter:typeset("n")
    SILE.call("textsuperscript", {}, { "os" })
    SILE.call("abbr:nbsp")
    SILE.process(content)
  end, "Formats French numbers (pluralized)")

  self:registerCommand("abbr:nos:en", function (_, content)
    SILE.typesetter:typeset("nos.")
    SILE.call("abbr:nbsp")
    SILE.process(content)
  end, "Formats English numbers (pluralized)")

  self:registerCommand("abbr:nos", function (_, content)
    local lang = SILE.settings:get("document.language")
    -- We only need the language code, so truncate any BCP-47 tag
    lang = lang:match("([^%-_]+)")
    if lang and SILE.Commands["abbr:nos:"..lang] then
      SILE.call("abbr:nos:"..lang, {}, content)
    else
      SU.warn("Language not supported for abbr:nos, fallback to English")
      SILE.call("abbr:nos:en", {}, content)
    end
  end, "Formats numbers, as in nos. 5-6, but depending on language")

  self:registerCommand("abbr:vol", function (_, content)
    SILE.typesetter:typeset("vol.")
    SILE.call("abbr:nbsp")
    SILE.process(content)
  end, "Formats a volume reference, as in vol. 3")

  self:registerCommand("abbr:page", function (options, content)
    SILE.typesetter:typeset("p.")
    SILE.call("abbr:nbsp", {}, {})
    SILE.process(content)
    if SU.boolean(options.sq) then
      -- Latin sequiturque ("and next page")
      SILE.call("font", { style = "italic", language = "und" }, { " sq." })
    elseif SU.boolean(options.sqq) then
      -- Latin sequiturque, plural ("and following pages")
      SILE.call("font", { style = "italic", language = "und" }, { " sqq." })
    elseif SU.boolean(options.suiv) then
      -- French ("et suivant") for those finding the latin sequiturque pedantic
      -- as Lacroux in his Orthotypographie book..
      SILE.typesetter:typeset(" et suiv.")
    end
  end, "Formats a page reference, as in p. 153, possibly followed by an option-dependent flag for subsequent pages")

  self:registerCommand("abbr:siecle", function (_, content)
    local century = (type(content[1]) == "string") and content[1]
      or SU.error("Expected a string for abbr:siecle")

    if tonumber(century) ~= nil then
      century = SU.formatNumber(century, { system = "roman" })
    elseif century:match("^[IVX]+$") ~= nil then
      century = string.lower(century)
    elseif century:match("^[ivx]+$") == nil then
      SU.error("Not a valid century '"..century.. "' in abbr:siecle")
    end
    SILE.call("font", { features = "+smcp" }, { century })
    if century == "i" then
      SILE.call("textsuperscript", {}, { "er" })
    else
      SILE.call("textsuperscript", {}, { "e" })
    end
  end, "Formats an French century (siècle) as in IVe (but properly typeset)")
end

package.documentation = [[\begin{document}
The \autodoc:package{resilient.abbr} package defines a few shorthands and abbreviations
that its author often uses in articles or book chapters.

The \autodoc:command{\abbr:nbsp} command inserts a non-breakable space.
It is stretchable and shrinkable as a normal inter-word space by default,
unless setting the \autodoc:parameter{fixed} option to true.

The \autodoc:command{\abbr:no:fr} and \autodoc:command{\abbr:no:en} commands prepend a
correctly typeset issue number, for French and English respectively,
that is \abbr:no:fr{5} and \abbr:no:en{5}.

The \autodoc:command{\abbr:nos:fr} and \autodoc:command{\abbr:nos:en} commands are the same
as the previous commands, but for the plural, as in
\abbr:nos:fr{5–6} and \abbr:nos:en{5–6}.

The \autodoc:command{\abbr:no} and \autodoc:command{\abbr:nos} invoke the appropriate
command depending on the current language, \abbr:nos{12, 13}.

The \autodoc:command{\abbr:vol} acts similarly for volume references, that
is \abbr:vol{4}, just ensuring the space in between is unbreakable.

The \autodoc:command{\abbr:page} does the same for page references, as in
\abbr:page{159}, but also supports one of the following boolean
options: \autodoc:parameter{sq}, \autodoc:parameter{sqq} and \autodoc:parameter{suiv},
to indicate subsequent page(s) in the usual manner in English or French, as
in \abbr:page[sq=true]{159}, \abbr:page[sqq=true]{159} or
\abbr:page[suiv=true]{159}
Note that in these cases, a period is automatically added.

The \autodoc:command{\abbr:siecle} command formats a century according to
the French typographic rules, as in \abbr:siecle{i} or
\abbr:siecle{iv}, \abbr:siecle{15} and \abbr:siecle{XIX}.
\end{document}]]

return package
