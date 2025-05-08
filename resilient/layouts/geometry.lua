--
-- Geometry page layout (explicit dimensions).
--
-- License: MIT
-- Copyright (C) 2023-2025 Omikhleia / Didier Willis
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
