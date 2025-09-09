--- Geometry page layout (explicit dimensions).
--
-- @license MIT
-- @copyright (c) 2023-2025 Omikhkeia / Didier Willis
-- @module resilient.layouts.geometry

--- Geometry layout class.
--
-- Extends `resilient.layouts.base`.
--
-- @type resilient.layouts.geometry

local base = require("resilient.layouts.base")
local layout = pl.class(base)

--- (Constructor) Create a new Geometry layout instance.
-- @tparam {inner=string,outer=string,head=string,foot=string} options Options (explicit dimensions)
function layout:_init (options)
  base._init(self, options)
  self.inner = SILE.types.measurement(options.inner)
  self.outer = SILE.types.measurement(options.outer)
  self.head = SILE.types.measurement(options.head)
  self.foot = SILE.types.measurement(options.foot)
end

return layout
