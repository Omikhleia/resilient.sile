--- Division-based page layout with wide margin for annotations.
--
-- @license MIT
-- @copyright (c) 2022-2025 Omikhkeia / Didier Willis
-- @module resilient.layouts.marginal

--- Marginal layout class.
--
-- Extends `resilient.layouts.base`.
--
-- @type resilient.layouts.marginal

local base = require("resilient.layouts.base")
local layout = pl.class(base)

--- (Constructor) Create a new Marginal layout instance.
-- @tparam {n=number} options Options (base ratio)
function layout:_init (options)
  base._init(self, options)
  self.n = options.n

  local N = 1 / self.n
  self.inner = "width(page) * " .. N
  self.outer = "(width(page) * (1 - " .. N .. ")) / 2.618"
  self.head = "height(page) * " .. N
  self.foot = "height(page) * " .. N
end

function layout:header (odd)
  return {
    left = odd and "left(textblock)" or "left(margins)",
    right = odd and "right(margins)" or "right(textblock)",
    top = "top(page) + (" .. self.head .. ") / 1.618 - 8pt",
    bottom = "top(header) + 16pt"
  }
end

return layout
