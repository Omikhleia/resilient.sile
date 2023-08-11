rockspec_format = "3.0"
package = "resilient.sile"
version = "2.1.0-1"
source = {
  url = "git+https://github.com/Omikhleia/resilient.sile.git",
  tag = "v2.1.0",
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
   "fancytoc.sile >= 1.0.0",
   "labelrefs.sile >= 0.1.0",
   "printoptions.sile >= 1.0.0",
   "ptable.sile >= 2.0.0",
   "qrcode.sile >= 1.0.0",
   "textsubsuper.sile >= 1.0.0",
   "markdown.sile >= 1.4.1",
   "silex.sile >= 0.2.0",
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

    ["sile.packages.autodoc-resilient"] = "packages/autodoc-resilient/init.lua",

    ["sile.resilient.utils"] = "resilient/utils.lua",
    ["sile.resilient.layoutparser"] = "resilient/layoutparser.lua",

    ["sile.resilient.layouts.base"]        = "resilient/layouts/base.lua",

    ["sile.resilient.layouts.canonical"]   = "resilient/layouts/canonical.lua",
    ["sile.resilient.layouts.division"]    = "resilient/layouts/division.lua",
    ["sile.resilient.layouts.frenchcanon"] = "resilient/layouts/frenchcanon.lua",
    ["sile.resilient.layouts.marginal"]    = "resilient/layouts/marginal.lua",

    ["sile.resilient.adapters.frameset"] = "resilient/adapters/frameset.lua",

    ["sile.inputters.silm"] = "inputters/silm.lua",

    ["sile.resilient-tinyyaml"]  = "lua-libraries/resilient-tinyyaml.lua",
  }
}
