std = "min+sile"
include_files = {
  "**/*.lua",
  "sile.in",
  "*.rockspec",
  ".busted",
  ".luacheckrc"
}
exclude_files = {
  "benchmark-*",
  "compare-*",
  "sile-*",
  "lua_modules",
  "lua-libraries",
  ".lua",
  ".luarocks",
  ".install"
}
files["**/*_spec.lua"] = {
  std = "+busted"
}
max_line_length = false
ignore = {
  "581" -- operator order warning doesn't account for custom table metamethods
}
-- vim: ft=lua
