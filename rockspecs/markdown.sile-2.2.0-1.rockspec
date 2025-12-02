rockspec_format = "3.0"
package = "markdown.sile"
version = "2.2.0-1"
source = {
    url = "git+https://github.com/Omikhleia/markdown.sile.git",
    tag = "v2.2.0",
}
description = {
  summary = "Native Markdown support for the SILE typesetting system.",
  detailed = [[
    This package set for the SILE typesetting system provides a complete redesign
    of the native Markdown support for SILE, with a great set of Pandoc-like
    extensions and plenty of extra goodies.
  ]],
  homepage = "https://github.com/Omikhleia/markdown.sile",
  license = "MIT",
}
dependencies = {
   "lua >= 5.1",
   "embedders.sile >= 0.2.0",
   "labelrefs.sile >= 0.1.0",
   "ptable.sile >= 3.1.0",
   "smartquotes.sile >= 1.0.0",
   "textsubsuper.sile >= 1.2.0",
   "silex.sile >= 0.6.0, < 1.0",
   "lunajson",
}

build = {
   type = "builtin",
   modules = {
      ["sile.classes.markdown"]           = "classes/markdown.lua",
      ["sile.inputters.markdown"]         = "inputters/markdown.lua",
      ["sile.inputters.pandocast"]        = "inputters/pandocast.lua",
      ["sile.inputters.djot"]             = "inputters/djot.lua",
      ["sile.packages.markdown"]          = "packages/markdown/init.lua",
      ["sile.packages.markdown.cmbase"]   = "packages/markdown/cmbase.lua",
      ["sile.packages.markdown.commands"] = "packages/markdown/commands.lua",
      ["sile.packages.markdown.utils"]    = "packages/markdown/utils.lua",
      ["sile.packages.pandocast"]         = "packages/pandocast/init.lua",
      ["sile.packages.djot"]              = "packages/djot/init.lua",

      ["sile.lunamark"]                 = "lua-libraries/lunamark.lua",
      ["sile.lunamark.entities"]        = "lua-libraries/lunamark/entities.lua",
      ["sile.lunamark.reader"]          = "lua-libraries/lunamark/reader.lua",
      ["sile.lunamark.reader.markdown"] = "lua-libraries/lunamark/reader/markdown.lua",
      ["sile.lunamark.util"]            = "lua-libraries/lunamark/util.lua",
      ["sile.lunamark.writer"]          = "lua-libraries/lunamark/writer.lua",
      ["sile.lunamark.writer.generic"]  = "lua-libraries/lunamark/writer/generic.lua",
      ["sile.lunamark.writer.html"]     = "lua-libraries/lunamark/writer/html.lua",
      ["sile.lunamark.writer.html5"]    = "lua-libraries/lunamark/writer/html5.lua",

      ["sile.djot"]                     = "lua-libraries/djot.lua",
      ["sile.djot.attributes"]          = "lua-libraries/djot/attributes.lua",
      ["sile.djot.json"]                = "lua-libraries/djot/json.lua",
      ["sile.djot.block"]               = "lua-libraries/djot/block.lua",
      ["sile.djot.inline"]              = "lua-libraries/djot/inline.lua",
      ["sile.djot.html"]                = "lua-libraries/djot/html.lua",
      ["sile.djot.ast"]                 = "lua-libraries/djot/ast.lua",
      ["sile.djot.filter"]              = "lua-libraries/djot/filter.lua",
   }
}
