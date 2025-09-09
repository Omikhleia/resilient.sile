--- French "Canon des Ateliers" page layout.
--
-- Sources:
--
--  - Pierre DUPLAN & Roger JAUNEAU, Maquette et mise en page, Éditions du Moniteur, Paris, 1986.
--
-- Other resources on usual variants, with examples:
--
--  - <http://indus.graph.free.fr/Cours%20PDF/T2%20PDF%2024-11-04.pdf>
--
-- Good general resource:
--
--  - Markus KOHM, "Étude comparative de différents modèles d’empagement", _Cahiers GUTenberg_ no. 42 (2003), pp. 4-25 (<http://www.numdam.org/item/CG_2003___42_4_0.pdf>)
--
-- @license MIT
-- @copyright (c) 2022-2025 Omikhkeia / Didier Willis
-- @module resilient.layouts.frenchcanon

--- French Canon layout class.
--
-- Extends `resilient.layouts.base`.
--
-- @type resilient.layouts.frenchcanon

local base = require("resilient.layouts.base")
local layout = pl.class(base)

local qualities = {
  regular = 1/4,
  demiluxe = 1/3,
  deluxe = 3/8
}
local rules = {
  ['12e'] = 1,
  ['10e'] = 2,
  -- Below: non-standard undocumented and we might change them
  halt =   3,
  valt =   4
}

--- (Constructor) Create a new French Canon layout instance.
-- @tparam {quality=string,rule=string} options Options (quality and rule)
function layout:_init (options)
  base._init(self, options)
  local N = qualities[options.quality or "regular"]
  local rule = rules[options.rule or "12e"]
  -- N = "Blanc" (white space) to distribute around the text block:
  -- "imprimé courant" (standard print) = 1/4
  --   demiluxe (a.k.a. demi-deluxe)    = 1/3
  --   deluxe                           = 3/8
  -- "Blanc de base" = 1/10 of the "Blanc", then usually multiplied by 4, 5, 6
  --  or 7 to provide the following dimensions, depending on a rule:
  --   PF "petit fond" (inner margin) = BW * 0.4
  --   GF "grand fond" (outer margin) = BW * 0.6
  --   BT "blanc de tête" (head margin) = ("règle du dixième") BH * 0.4
  --                                   or ("règle du 12/10e")  BW * 0.5
  --                                   or (other variants) PF or 0.5 BH
  --   BP "blanc de pied" (foot margin) = ("règle du dixième") BH * 0.6
  --                                   or ("règle du 12/10e")  BW * 0.7
  --                                   or (other variants) GF or 0.5 BH
  self.inner = "width(page) * " .. 0.4 * N
  self.outer = "width(page) * " .. 0.6 * N
  if rule == 1 then
    -- "règle du 10/12"
    -- BT = 0.5 BW
    -- GT = 0.7 BW
    self.head = "width(page) * " .. 0.5 * N
    self.foot = "width(page) * " .. 0.7 * N
  elseif rule == 2 then
    -- Canon des ateliers règle du dixième
    -- BT = 0.4 BH
    -- BP = 0.6 BH
    self.head = "height(page) * " .. 0.4 * N
    self.foot = "height(page) * " .. 0.6 * N
  elseif rule == 3 then
    -- BT = PF, BP = GF
    self.head = self.inner
    self.foot = self.outer
  else -- rule 4
    -- BT = BP = 0.5 BH
    self.head = "height(page) * " .. 0.5 * N
    self.foot = "height(page) * " .. 0.5 * N
  end
end

return layout
