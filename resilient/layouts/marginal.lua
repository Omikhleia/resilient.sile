--
-- Division-based layout with wide margin for annotations.
--
-- License: GPL-3.0-or-later
--
-- Copyright (C) 2022-2025 Didier Willis
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
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
