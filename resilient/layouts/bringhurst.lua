--
-- Bringhurst's layout for pages in 1:√3 ratio.
-- As used in his book "The Elements of Typographic Style".
--
-- License: MIT
-- Copyright (C) 2025 Omikhleia / Didier Willis
--
local base = require("resilient.layouts.base")
local isophi = pl.class(base)

function isophi:_init (options)
  base._init(self, options)
  self.inner = "width(page) * " .. (1 / 9)
  self.outer = "width(page) * " .. (2 / 9)
  self.head = "height(page) * " .. (1 / 14)
  self.foot = "height(page) * " .. (1 / 6)
  -- With a page in 1:√3 ratio, the text area is 1:1.98 (= almost 1:2).
  -- This layout is obviously not suitable for other page formats.
end

return isophi
