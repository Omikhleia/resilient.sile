local function canonical (width, height)
  -- The text block is placed onto the page in such a way as: (a) its diagonal
  -- coincides with the page relevant diagonal, and (b) the circle inscribed
  -- within the text block is tangent to the page sides.
  -- The text block width to height ratio is kept equal to the page ratio, as
  -- well as the inner to outer and the upper to lower margin ratios.

  -- Page shape ratio: x = w/h (1)
  -- Inner margin: I = wx(1 − x)/(1 + x) (2)
  -- External margin: E = w(1 − x)/(1 + x) (3)
  -- Top margin: T = hx(1 − x)/(1 + x) (4)
  -- Bottom margin: B = h(1 − x)/(1 + x) (5)
  -- Text width: W = xw (6)
  -- Text height: H = w (7)

  -- HACK/BUG: We precompute the ratios, meaning users cannot change
  -- the page dimensions afterwards in the course of the document.
  -- Two reasons:
  --  - It makes computation faster that full formulas in page template syntax,
  --  - There seem to be some tricky bugs in the frame constraint solver and/or
  --    the twoside package, as full formulas where improperly solved.
  local x = width / height
  local xr = (1 - x) / (1 + x)
  local I = xr * x .. " * 100%pw"
  local E = "100%pw * " .. xr
  local B = "100%ph * " .. xr
  local T = "100%ph * " .. xr * x

  return {
    content = {
      left = "left(page) + " .. I,
      top = "top(page) + " .. T,
      right = "left(page) + 100%pw - " .. E,
      bottom = "top(footnotes)"
    },
    folio = {
      left = "left(content)",
      right = "right(content)",
      top = "bottom(footnotes)+3%ph",
      bottom = "bottom(footnotes)+5%ph"
    },
    header = {
      left = "left(content)",
      right = "right(content)",
      top = "top(content)-5%ph",
      bottom = "top(content)-2%ph"
    },
    footnotes = {
      left = "left(content)",
      right = "right(content)",
      height = "0",
      bottom = "bottom(page) - " .. B
    }
  }
end

return canonical
