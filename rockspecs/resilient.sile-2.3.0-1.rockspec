rockspec_format = "3.0"
package = "resilient.sile"
version = "2.3.0-1"
source = {
  url = "git+https://github.com/Omikhleia/resilient.sile.git",
  tag = "v2.3.0",
}
description = {
  summary = "Advanced book classes and tools for the SILE typesetting system.",
  detailed = [[
    This collection of classes and packages for the SILE typesetter system provides
    advanced classes and tools for easier print-quality book production.
  ]],
  homepage = "https://github.com/Omikhleia/resilient.sile",
  license = "MIT",
}
dependencies = {
   "lua >= 5.1",
   "barcodes.sile >= 1.0.0",
   "couyards.sile >= 1.0.0",
   "embedders.sile >= 0.1.0",
   "fancytoc.sile >= 1.0.1",
   "labelrefs.sile >= 0.1.0",
   "printoptions.sile >= 1.0.0",
   "piecharts.sile >= 0.2.0",
   "ptable.sile >= 3.0.0",
   "qrcode.sile >= 1.0.0",
   "textsubsuper.sile >= 1.1.1",
   "markdown.sile >= 2.0.0",
   "silex.sile >= 0.5.0",
}
build = {
  type = "builtin",
  modules = {
    ["sile.classes.resilient.base"]    = "classes/resilient/base.lua",

    ["sile.classes.resilient.book"]    = "classes/resilient/book.lua",
    ["sile.classes.resilient.resume"]  = "classes/resilient/resume.lua",

    ["sile.packages.resilient.base"]            = "packages/resilient/base.lua",

    ["sile.packages.resilient.abbr"]            = "packages/resilient/abbr/init.lua",
    ["sile.packages.resilient.styles"]          = "packages/resilient/styles/init.lua",
    ["sile.packages.resilient.tableofcontents"] = "packages/resilient/tableofcontents/init.lua",
    ["sile.packages.resilient.sectioning"]      = "packages/resilient/sectioning/init.lua",
    ["sile.packages.resilient.poetry"]          = "packages/resilient/poetry/init.lua",
    ["sile.packages.resilient.footnotes"]       = "packages/resilient/footnotes/init.lua",
    ["sile.packages.resilient.lists"]           = "packages/resilient/lists/init.lua",
    ["sile.packages.resilient.headers"]         = "packages/resilient/headers/init.lua",
    ["sile.packages.resilient.epigraph"]        = "packages/resilient/epigraph/init.lua",
    ["sile.packages.resilient.bookmatters"]     = "packages/resilient/bookmatters/init.lua",
    ["sile.packages.resilient.verbatim"]        = "packages/resilient/verbatim/init.lua",
    ["sile.packages.resilient.defn"]            = "packages/resilient/defn/init.lua",
    ["sile.packages.resilient.liners"]          = "packages/resilient/liners/init.lua",

    ["sile.packages.resilient.bible.usx"]       = "packages/resilient/bible/usx/init.lua",
    ["sile.packages.resilient.bible.tei"]       = "packages/resilient/bible/tei/init.lua",

    ["sile.packages.autodoc-resilient"] = "packages/autodoc-resilient/init.lua",

    ["sile.resilient.utils"] = "resilient/utils.lua",
    ["sile.resilient.layoutparser"] = "resilient/layoutparser.lua",

    ["sile.resilient.layouts.base"]        = "resilient/layouts/base.lua",

    ["sile.resilient.layouts.canonical"]   = "resilient/layouts/canonical.lua",
    ["sile.resilient.layouts.division"]    = "resilient/layouts/division.lua",
    ["sile.resilient.layouts.frenchcanon"] = "resilient/layouts/frenchcanon.lua",
    ["sile.resilient.layouts.geometry"]    = "resilient/layouts/geometry.lua",
    ["sile.resilient.layouts.marginal"]    = "resilient/layouts/marginal.lua",

    ["sile.resilient.adapters.frameset"] = "resilient/adapters/frameset.lua",

    ["sile.inputters.silm"] = "inputters/silm.lua",

    ["sile.resilient-tinyyaml"]  = "lua-libraries/resilient-tinyyaml.lua",
  },
  install = {
    lua = {
      ["sile.packages.resilient.bible.tei.monograms.default"] = "packages/resilient/bible/tei/monograms/default.png",
      ["sile.packages.resilient.bible.tei.monograms.jn"]      = "packages/resilient/bible/tei/monograms/jn.png",
      ["sile.packages.resilient.bible.tei.monograms.mk"]      = "packages/resilient/bible/tei/monograms/mk.png",
      ["sile.packages.resilient.bible.tei.monograms.mt"]      = "packages/resilient/bible/tei/monograms/mt.png",
      ["sile.packages.resilient.bible.tei.monograms.lk"]      = "packages/resilient/bible/tei/monograms/lk.png",
      ["sile.packages.resilient.bible.tei.monograms.sign"]    = "packages/resilient/bible/tei/monograms/sign.png",

      ["sile.templates.halftitle-recto"] = "templates/halftitle-recto.djt",
      ["sile.templates.halftitle-verso"] = "templates/halftitle-verso.djt",
      ["sile.templates.title-recto"]     = "templates/title-recto.djt",
      ["sile.templates.title-verso"]     = "templates/title-verso.djt",
      ["sile.templates.endpaper-recto"]  = "templates/endpaper-recto.djt",
      ["sile.templates.endpaper-verso"]  = "templates/endpaper-verso.djt",
    }
  }
}
