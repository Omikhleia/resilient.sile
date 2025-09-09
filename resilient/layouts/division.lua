--- Division-based page layouts.
--
-- Sources:
--
--   - Alain HURTGIG, <http://www.alain.les-hurtig.org/varia/empagement.html>.
--   - Jan TSCHICHOLD, _Livre et typographie,_ Éditions Allia, Paris, 1994.
--   - Division by 6: used Marcus Vencentinus (15th century) in a prayer book.
--   - Division by 9: Method proposed by Villard de Honnecourt (13th century).
--   - Olivier RANDIER's general method: Olivier RANDIER, Mail to the Typographie mailing-list, April 8, 2002.
--
-- @license MIT
-- @copyright (c) 2022-2025 Omikhkeia / Didier Willis
-- @module resilient.layouts.division

--- Division layout class.
--
-- Extends `resilient.layouts.base`.
--
-- @type resilient.layouts.division

local base = require("resilient.layouts.base")
local layout = pl.class(base)

--- (Constructor) Create a new Division layout instance.
-- @tparam {n=number,ratio=number} options Options (base ratio and optional ratio)
function layout:_init (options)
  base._init(self, options)
  self.n = options.n
  self.R = options.ratio
  -- n = 6, 9, 12 (usual number of divisions)
  -- Optional ratio v:
  --    2 in historical methods (Honnecourt, Vencentinus).
  --    If unset, defaults to PH/PW for Randier's method.
  local N = 1 / self.n
  local R = self.R or "100%ph / 100%pw" -- SEE HACK can't use height(page)/width(page)
  -- PF = PW * N
  -- GF = v * PW * N
  -- BT = PH * N
  -- BP = v * PH * N
  self.inner = "width(page) * " .. N
  self.outer = "width(page) * " .. N .. " * " .. R
  self.head = "height(page) * " .. N
  self.foot = "height(page) * " .. N .. " * " .. R
end

--- (Override) Set the paper size.
-- @tparam SILE.types.measurement W Paper width
-- @tparam SILE.types.measurement H Paper height
function layout:setPaperHack (W, H)
  -- So recompute all.
  self.W = W
  self.H = H
  local N = 1 / self.n
  local R = self.R or H/W
  -- PF = PW * N
  -- GF = v * PW * N
  -- BT = PH * N
  -- BP = v * PH * N
  self.inner = "width(page) * " .. N
  self.outer = "width(page) * " .. N .. " * " .. R
  self.head = "height(page) * " .. N
  self.foot = "height(page) * " .. N .. " * " .. R
end

return layout
