--- "Stupid" class so that processing Markdown, Djot and Pandoc AST is directly
-- available from command line, without having to write a SILE document.
-- It also aims at overriding the legacy markdown class from SILE, as long as
-- it is shipped with the core distribution.
--
local book = require("classes.book")
local class = pl.class(book)
class._name = "markdown"

function class:_init (options)
  book._init(self, options)
  -- Load all the packages: corresponding inputters are then also registered.
  -- Since we support switching between formats via "code blocks", we want
  -- to make it easier for the user and not have him bother about how to load
  -- the right inputter and appropriate packages.
  self:loadPackage("djot")
  self:loadPackage("markdown")
  self:loadPackage("pandocast")
  return self
end

return class
