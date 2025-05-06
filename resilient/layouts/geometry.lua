--
-- Geometry page layout (explicit dimensions).
--
-- License: GPL-3.0-or-later
--
-- Copyright (C) 2023-2025 Didier Willis
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
local geometry = pl.class(base)

function geometry:_init (options)
  base._init(self, options)
  self.inner = SILE.types.measurement(options.inner)
  self.outer = SILE.types.measurement(options.outer)
  self.head = SILE.types.measurement(options.head)
  self.foot = SILE.types.measurement(options.foot)
end

return geometry
