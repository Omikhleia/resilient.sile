rockspec_format = "3.0"
package = "resilient.sile"
version = "3.4.0-1"
source = {
  url = "git+https://github.com/Omikhleia/resilient.sile.git",
  tag = "v3.4.0",
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
   "mimetypes",
   "sha1",
   "barcodes.sile >= 2.1.0",
   "couyards.sile >= 1.0.0",
   "embedders.sile >= 1.1.0",
   "labelrefs.sile >= 0.1.0",
   "piecharts.sile >= 2.1.0",
   "ptable.sile >= 4.1.0",
   "qrcode.sile >= 2.1.0",
   "textsubsuper.sile >= 2.1.0",
   "smartquotes.sile >= 2.0.0",
   "markdown.sile >= 3.0.0",
}
build = {
  type = "builtin",
  modules = {
    ["sile.classes.resilient.override"]  = "classes/resilient/override.lua",
    ["sile.classes.resilient.base"]      = "classes/resilient/base.lua",

    ["sile.classes.resilient.book"]      = "classes/resilient/book.lua",
    ["sile.classes.resilient.resume"]    = "classes/resilient/resume.lua",

    ["sile.typesetters.silent"]                = "typesetters/silent.lua",
    ["sile.typesetters.algorithms.knuthplass"] = "typesetters/algorithms/knuthplass.lua",
    ["sile.typesetters.algorithms.bidi"]       = "typesetters/algorithms/bidi.lua",
    ["sile.typesetters.nodes.liners"]          = "typesetters/nodes/liners.lua",
    ["sile.typesetters.nodes.speaker"]         = "typesetters/nodes/speaker.lua",
    ["sile.typesetters.mixins.totext"]         = "typesetters/mixins/totext.lua",
    ["sile.typesetters.mixins.liners"]         = "typesetters/mixins/liners.lua",
    ["sile.typesetters.mixins.shaping"]        = "typesetters/mixins/shaping.lua",
    ["sile.typesetters.mixins.hbox"]           = "typesetters/mixins/hbox.lua",
    ["sile.typesetters.mixins.paragraphing"]   = "typesetters/mixins/paragraphing.lua",

    ["sile.pagebuilders.pageant"]              = "pagebuilders/pageant.lua",

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
    ["sile.packages.resilient.fancytoc"]        = "packages/resilient/fancytoc/init.lua",

    ["sile.packages.resilient.plain"]           = "packages/resilient/plain/init.lua",

    ["sile.packages.resilient.bible.usx"]       = "packages/resilient/bible/usx/init.lua",
    ["sile.packages.resilient.bible.tei"]       = "packages/resilient/bible/tei/init.lua",

    ["sile.packages.resilient.attachments"]     = "packages/resilient/attachments/init.lua",
    ["sile.packages.resilient.forms"]           = "packages/resilient/forms/init.lua",

    ["sile.packages.resilient.invoice"]         = "packages/resilient/invoice/init.lua",

    ["sile.packages.autodoc-resilient"]    = "packages/autodoc-resilient/init.lua",
    ["sile.packages.printoptions"]         = "packages/printoptions/init.lua",

    ["sile.resilient.utils"]     = "resilient/utils.lua",
    ["sile.resilient.uuid"]      = "resilient/uuid.lua",
    ["sile.resilient.bootstrap"] = "resilient/bootstrap.lua",

    ["sile.resilient.layoutparser"]        = "resilient/layoutparser.lua",
    ["sile.resilient.layouts.base"]        = "resilient/layouts/base.lua",

    ["sile.resilient.layouts.canonical"]   = "resilient/layouts/canonical.lua",
    ["sile.resilient.layouts.division"]    = "resilient/layouts/division.lua",
    ["sile.resilient.layouts.frenchcanon"] = "resilient/layouts/frenchcanon.lua",
    ["sile.resilient.layouts.geometry"]    = "resilient/layouts/geometry.lua",
    ["sile.resilient.layouts.marginal"]    = "resilient/layouts/marginal.lua",
    ["sile.resilient.layouts.isophi"]      = "resilient/layouts/isophi.lua",
    ["sile.resilient.layouts.bringhurst"]  = "resilient/layouts/bringhurst.lua",

    ["sile.resilient.adapters.frameset"] = "resilient/adapters/frameset.lua",

    ["sile.inputters.silm"] = "inputters/silm.lua",
    ["sile.inputters.invoice"] = "inputters/invoice.lua",

    ["sile.resilient.schemas.validator"] = "resilient/schemas/validator.lua",
    ["sile.resilient.schemas.common"]    = "resilient/schemas/common.lua",
    ["sile.resilient.schemas.invoice"]   = "resilient/schemas/invoice/init.lua",
    ["sile.resilient.schemas.silm"]      = "resilient/schemas/silm/init.lua",

    ["sile.resilient.support.invoice.facturx"] = "resilient/support/invoice/facturx.lua",
    ["sile.resilient.support.invoice.i18n.ca"] = "resilient/support/invoice/i18n/ca.lua",
    ["sile.resilient.support.invoice.i18n.de"] = "resilient/support/invoice/i18n/de.lua",
    ["sile.resilient.support.invoice.i18n.en"] = "resilient/support/invoice/i18n/en.lua",
    ["sile.resilient.support.invoice.i18n.es"] = "resilient/support/invoice/i18n/es.lua",
    ["sile.resilient.support.invoice.i18n.fr"] = "resilient/support/invoice/i18n/fr.lua",
    ["sile.resilient.support.invoice.i18n.is"] = "resilient/support/invoice/i18n/is.lua",
    ["sile.resilient.support.invoice.i18n.it"] = "resilient/support/invoice/i18n/it.lua",
    ["sile.resilient.support.invoice.i18n.nl"] = "resilient/support/invoice/i18n/nl.lua",
    ["sile.resilient.support.invoice.i18n.pt"] = "resilient/support/invoice/i18n/pt.lua",
    ["sile.resilient.support.invoice.i18n.ru"] = "resilient/support/invoice/i18n/ru.lua",

    ["sile.resilient.support.xmp"]             = "resilient/support/xmp.lua",

    ["sile.resilient-tinyyaml"]  = "lua-libraries/resilient-tinyyaml.lua",

    ["sile.resilient.patches.lang"]      = "resilient/patches/lang.lua",
    ["sile.resilient.patches.overhang"]  = "resilient/patches/overhang.lua",
  },
  install = {
    lua = {
      ["sile.packages.resilient.bible.tei.monograms.default"] = "packages/resilient/bible/tei/monograms/default.png",
      ["sile.packages.resilient.bible.tei.monograms.jn"]      = "packages/resilient/bible/tei/monograms/jn.png",
      ["sile.packages.resilient.bible.tei.monograms.mk"]      = "packages/resilient/bible/tei/monograms/mk.png",
      ["sile.packages.resilient.bible.tei.monograms.mt"]      = "packages/resilient/bible/tei/monograms/mt.png",
      ["sile.packages.resilient.bible.tei.monograms.lk"]      = "packages/resilient/bible/tei/monograms/lk.png",
      ["sile.packages.resilient.bible.tei.monograms.sign"]    = "packages/resilient/bible/tei/monograms/sign.png",

      ["sile.templates.cover"]           = "templates/cover.djt",
      ["sile.templates.halftitle-recto"] = "templates/halftitle-recto.djt",
      ["sile.templates.halftitle-verso"] = "templates/halftitle-verso.djt",
      ["sile.templates.title-recto"]     = "templates/title-recto.djt",
      ["sile.templates.title-verso"]     = "templates/title-verso.djt",
      ["sile.templates.endpaper-recto"]  = "templates/endpaper-recto.djt",
      ["sile.templates.endpaper-verso"]  = "templates/endpaper-verso.djt",
    }
  }
}
