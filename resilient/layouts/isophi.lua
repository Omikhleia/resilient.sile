--- Bringhurst's proposed page layout for ISO formats.
--
-- Not supposed to be used with any other non ISO page sizes (1:√2 ratio).
--
-- @license MIT
-- @copyright (c) 2025 Omikhkeia / Didier Willis
-- @module resilient.layouts.isophi

--- ISO-phi layout class.
--
-- Extends `resilient.layouts.base`.
--
-- @type resilient.layouts.isophi

local base = require("resilient.layouts.base")
local layout = pl.class(base)

--- (Constructor) Create a new ISO-phi layout instance.
-- @tparam {n=8}|{n=9} options Options (base ratio)
function layout:_init (options)
  base._init(self, options)
  self.n = options.n
  if self.n == 8 then
    local N1 = 1 / 8
    local N2 = 15 / 72 -- That's actually 2/9 - (1/8 - 1/9)
    self.inner = "width(page) * " .. N1
    self.outer = "width(page) * " .. N2
    self.head = self.inner
    self.foot = self.outer
  elseif self.n == 9 then
    local N = 1 / 9
    self.inner = "width(page) * " .. N
    self.outer = "width(page) * " .. 2 * N
    self.head = self.inner
    self.foot = self.outer
  else
    SU.error("Layout 'isophi' only supports a base ratio of 8 or 9")
  end
end

return layout
