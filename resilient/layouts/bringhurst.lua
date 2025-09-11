--- Bringhurst's layout for pages in 1:√3 ratio.
--
-- As used in his book "The Elements of Typographic Style".
--
-- Not supposed to be used with any other page size ratios.
--
-- @license MIT
-- @copyright (c) 2025 Omikhkeia / Didier Willis
-- @module resilient.layouts.bringhurst

--- Bringhurst layout class.
--
-- Extends `resilient.layouts.base`.
--
-- @type resilient.layouts.bringhurst

local base = require("resilient.layouts.base")
local layout = pl.class(base)

--- (Constructor) Create a new Bringhurst layout instance.
-- @tparam table options Options (none specific here)
function layout:_init (options)
  base._init(self, options)
  self.inner = "width(page) * " .. (1 / 9)
  self.outer = "width(page) * " .. (2 / 9)
  self.head = "height(page) * " .. (1 / 14)
  self.foot = "height(page) * " .. (1 / 6)
  -- With a page in 1:√3 ratio, the text area is 1:1.98 (= almost 1:2).
  -- This layout is obviously not suitable for other page formats.
end

return layout
