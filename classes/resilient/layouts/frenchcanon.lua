--
-- "Canon des ateliers"
-- Main source : Pierre DUPLAN & Roger JAUNEAU, Maquette et mise en page, Éditions du Moniteur, Paris, 1986.
-- Other resources on usual variants, with examples:
--   http://indus.graph.free.fr/Cours%20PDF/T2%20PDF%2024-11-04.pdf
-- Good general resource:
--   http://www.numdam.org/item/CG_2003___42_4_0.pdf
--     i.e. Markus Kohm, Étude comparative de différents modèles d’empagement, Cahiers GUTenberg n° 42 (2003), p. 4-25
local function frenchcannon (N, rule)
  -- N = "Blanc" to distribute around the text block:
  -- "imprimé courant" (current) = 1/4
  --   demi-deluxe = 1/3
  --   deluxe = 3/8
  -- "Blanc de base" = 1/10 of the "Blanc", then usually multiplied by 4, 5, 6 or 7 to
  -- provide the following dimensions, depending on a rule:
  --   PF "petit fond" (inner margin) = BW * 0.4
  --   GF "grand fond" (outer margin) = BW * 0.6
  --   BT "blanc de tête" (head margin) = BH * 0.4 or ("règle du 12/10e") BW * 0.5 or (other variants) PF or 0.5 BH
  --   BP "blanc de pied" (foot margin) = BH * 0.6 or ("règle du 12/10e") BW * 0.7 or (other variants) GF or 0.5 BH
  local inner = "width(page) * " .. 0.4 * N
  local outer = "width(page) * " .. 0.6 * N
  local head, foot
  if rule == 1 then
    -- "règle du 10/12"
    -- BT = 0.5 BW
    -- GT = 0.7 BW
    head = "width(page) * " .. 0.5 * N
    foot = "width(page) * " .. 0.7 * N
  elseif rule == 2 then
    -- Canon des ateliers
    -- BT = 0.4 BH
    -- BP = 0.6 BH
    head = "height(page) * " .. 0.4 * N
    foot = "height(page) * " .. 0.6 * N
  elseif rule == 3 then
    -- BT = PF, BP = GF
    head = inner
    foot = outer
  else -- rule 4
    -- BT = BP = 0.5 BH
    head = "height(page) * " .. 0.5 * N
    foot = "height(page) * " .. 0.5 * N
  end
  return {
    content = {
      left = "left(page) + " .. inner,
      right = "right(page) - " .. outer,
      top = "top(page) + " .. head,
      bottom = "top(footnotes)",
    },
    folio = {
      left = "left(content)",
      right = "right(content)",
      top = "bottom(footnotes)+3%ph",
      bottom = "bottom(footnotes)+5%ph",
    },
    header = {
      left = "left(content)",
      right = "right(content)",
      top = "top(content)-5%ph",
      bottom = "top(content)-2%ph",
    },
    footnotes = {
      left = "left(content)",
      right = "right(content)",
      height = "0",
      bottom = "bottom(page) - " .. foot,
    }
  }
end

return frenchcannon
