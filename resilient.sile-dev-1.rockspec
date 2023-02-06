package = "resilient.sile"
version = "dev-1"
source = {
  url = "git+https://github.com/Omikhleia/resilient.sile.git",
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
   "barcodes.sile",
   "couyards.sile",
   "embedders.sile",
   "fancytoc.sile",
   "labelrefs.sile",
   "printoptions.sile",
   "ptable.sile",
   "qrcode.sile",
   "textsubsuper.sile",
   "markdown.sile",
}
build = {
  type = "builtin",
  modules = {
    ["sile.classes.resilient.base"]    = "classes/resilient/base.lua",

    ["sile.classes.resilient.book"]    = "classes/resilient/book.lua",
    ["sile.classes.resilient.resume"]  = "classes/resilient/resume.lua",

    ["sile.classes.resilient.layouts.frenchcanon"] = "classes/resilient/layouts/frenchcanon.lua",
    ["sile.classes.resilient.layouts.canonical"]   = "classes/resilient/layouts/canonical.lua",
    ["sile.classes.resilient.layouts.division"]    = "classes/resilient/layouts/division.lua",

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
  }
}
