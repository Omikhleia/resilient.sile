-- Sources
--   http://www.alain.les-hurtig.org/varia/empagement.html
--   (Source : Jan TSCHICHOLD, Livre et typographie, Éditions Allia, Paris, 1994.)
--   Division by 6: used Marcus Vencentinus (15th century) in a prayer book
--   Division by 9: Method proposed by Villard de Honnecourt (13th century).
--   Olivier Randier's general method: Olivier RANDIER, Mail to the Typographie mailing-list, April 8, 2002.

local function division (n, v)
  -- n = 6, 9, 12 (number of divisions)
  -- Optional v = 2 in Honnecourt, Vencentinus. If unset, defaults to PH/PW for Randier's method.

  local N = 1 / n
  v = v or "(100%ph / 100%pw)" -- SHOULD WORK, though sometimes the frame spec parser is weird.
  -- PF = PW * N
  -- GF = v * PW * N
  -- BT = PH * N
  -- BP = v * PH * N
  local x = "0.5in"
  local GF = "33%pw * (1 - " .. N .. ')  +  0.66 * ' ..  x
  local x = "0.5in"
  return {
    contentx = {
      left = "left(page) + width(page) * " .. N,
      -- right = "right(page) - width(page) * " .. v .. " * " .. N,
      right = "right(page) - " .. GF,
      top = "top(page) + height(page) * " .. N,
      bottom = "bottom(page) - height(page) * "  .. v .. " * " .. N,
    },
    content = {
      left = "left(page) + width(page) * " .. N,
      -- right = "right(page) - width(page) * " .. v .. " * " .. N,
      right = "right(page) - " .. GF,
      top = "top(page) + height(page) * " .. N,
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
      bottom = "bottom(page) - height(page) * "  .. v .. " * " .. N,
    },
    margins = {
      top = "top(content)",
      bottom = "bottom(page) - height(page) * "  .. v .. " * " .. N,
      left = "right(content) + 2.1%pw",
      right = "right(page) - 0.5in",
    },
  }
end

return division
