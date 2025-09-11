--- Jan Tschichold's canonical page layout.
--
-- The text block is placed onto the page in such a way as: (a) its diagonal
-- coincides with the page relevant diagonal, and (b) the circle inscribed
-- within the text block is tangent to the page sides.
--
-- The text block width to height ratio is kept equal to the page ratio, as
-- well as the inner to outer and the upper to lower margin ratios.
--
-- Sources:
--
--  - Jan TSCHICHOLD, _The Form of the Book: Essays on the Morality of Good Design,_ Hartley & Marks, Vancouver 1991.
--  - Jan TSCHICHOLD, _Livre et typographie,_ Éditions Allia, Paris, 1994.
--
-- Other references:
--
--  - Claudio BECCARI, Package **canoniclayout**, 2022 (<https://www.ctan.org/pkg/canoniclayout>)
--
-- @license MIT
-- @copyright (c) 2022-2025 Omikhkeia / Didier Willis
-- @module resilient.layouts.canonical

--- Canonical layout class.
--
-- Extends `resilient.layouts.base`.
--
-- @type resilient.layouts.canonical

local base = require("resilient.layouts.base")
local layout = pl.class(base)

--- (Constructor) Create a new Canonical layout instance.
-- @tparam table options Options (none specific here)
function layout:_init (options)
  base._init(self, options)
  -- Page shape ratio: x = w/h (1)
  -- Inner margin: I = wx(1 − x)/(1 + x) (2)
  -- External margin: E = w(1 − x)/(1 + x) (3)
  -- Top margin: T = hx(1 − x)/(1 + x) (4)
  -- Bottom margin: B = h(1 − x)/(1 + x) (5)
  -- Text width: W = xw (6)
  -- Text height: H = w (7)

  -- HACK/BUG: We precompute the ratios, meaning users cannot change
  -- the page dimensions afterwards in the course of the document...
  -- (Bad) rationale:
  --  - It makes computation faster than full formulas in page template syntax.
  --  - There seem to be some tricky bugs in the frame constraint solver and/or
  --    the twoside package, as full formulas where improperly solved.
  local x = 0.6666 -- HACK RECOMPUTELOW
  local xr = "((1 - ".. x ..") / (1 + ".. x .."))"

  self.inner = "width(page) * " .. xr .. " * " .. x
  self.outer = "width(page) * " .. xr
  self.head = "height(page) * " .. xr .. " * " .. x
  self.foot = "height(page) * " .. xr
end

--- (Override) Set the paper size.
--
-- @tparam SILE.types.measurement W Paper width
-- @tparam SILE.types.measurement H Paper height
function layout:setPaperHack (W, H)
  -- So recompute all.
  self.W = W
  self.H = H
  local x = self.W / self.H
  local xr = "((1 - ".. x ..") / (1 + ".. x .."))"

  self.inner = "width(page) * " .. xr .. " * " .. x
  self.outer = "width(page) * " .. xr
  self.head = "height(page) * " .. xr .. " * " .. x
  self.foot = "height(page) * " .. xr
end

return layout
