--
-- Division-based layout with wide margin for annotations.
--
-- License: MIT
-- Copyright (C) 2022-2025 Omikhleia / Didier Willis
--
local base = require("resilient.layouts.base")
local marginal = pl.class(base)

function marginal:_init (options)
  base._init(self, options)
  self.n = options.n

  local N = 1 / self.n
  self.inner = "width(page) * " .. N
  self.outer = "(width(page) * (1 - " .. N .. ")) / 2.618"
  self.head = "height(page) * " .. N
  self.foot = "height(page) * " .. N
end

function marginal:header (odd)
  return {
    left = odd and "left(textblock)" or "left(margins)",
    right = odd and "right(margins)" or "right(textblock)",
    top = "top(page) + (" .. self.head  .. ") / 1.618 - 8pt",
    bottom = "top(header) + 16pt"
  }
end

return marginal
