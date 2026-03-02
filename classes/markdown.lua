--- A convenience class for processing Markdown, Djot and Pandoc ASTs.
--
-- It is a somewhat "stupid" class, so that processing Markdown, Djot and Pandoc AST is directly
-- available from command line, without having to write a SILE wrapper document.
--
-- @license MIT
-- @copyright (c) 2022-2026 Omikhleia / Didier Willis
-- @module classes.markdown

--- The markdown (book) convenience class.
--
-- Extends `classes.resilient.book`
--
-- @type classes.markdown

local book = require("classes.resilient.book")
local class = pl.class(book)
class._name = "markdown"

--- (Constructor) Initialize the markdown/djobook class.
--
-- It just initializes the class, and loads the packages that are needed to process Markdown, Djot and Pandoc ASTs.
--
-- @tparam table options Class options (passed to the superclass constructor)
function class:_init (options)
  book._init(self, options)
  -- Load all the packages: corresponding inputters are then also registered.
  -- Since we support switching between formats via "code blocks", we want
  -- to make it easier for the user and not have him bother about how to load
  -- the right inputter and appropriate packages.
  --
  -- Note: the resilient book class might also load some of these packages,
  -- but it doesn't matter within the re·sil·ient framework, since loading a package multiple times is not an issue.
  self:loadPackage("djot")
  self:loadPackage("markdown")
  self:loadPackage("pandocast")
  return self
end

return class
