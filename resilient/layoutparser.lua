--
-- Parser for layout class options
-- 2023 Didier Willis
-- License: MIT
--
-- A bit quick and dirty.
--
local lpeg = require("lpeg")
local P, C, V = lpeg.P, lpeg.C, lpeg.V

local number = SILE.parserBits.number
local ws = P(":") + SILE.parserBits.ws

local layoutParser = P{
  "layout",
  layout  = (V"none" + V"canonical"
           + V"division" + V"honnecourt" + V"vencentinus"
           + V"ateliers"
           + V"marginal") * P(-1),
  none = P("none") / function ()
    local layout = require("resilient.layouts.base")
    return layout()
  end,
  canonical = P"canonical" / function ()
    local layout = require("resilient.layouts.canonical")
    return layout()
  end,
  honnecourt = P("honnecourt") / function()
    local layout = require("resilient.layouts.division")
    return layout({ n = 9, ratio = 2 })
  end,
  vencentinus = P("vencentinus") / function()
    local layout = require("resilient.layouts.division")
    return layout({ n = 6, ratio = 2 })
  end,
  division = P("division")
    * (
      (ws * number * ws * number)
      + (ws * number)
      + (lpeg.Cc(9))
    ) / function(n, ratio)
    local layout = require("resilient.layouts.division")
    return layout({ n = n, ratio = ratio })
  end,
  marginal = P("marginal")
    * (
      (ws * number * ws * number)
      + (ws * number)
      + (lpeg.Cc(8))
    ) / function(n, ratio)
    local layout = require("resilient.layouts.marginal")
    return layout({ n = n, ratio = ratio })
  end,
  ateliers = P("ateliers")
    * (
      (ws * C(V"quality") * ws * C(V"rule"))
      + (ws * C(V"quality"))
      + (lpeg.Cc("regular"))
    ) / function(q, r)
    local layout = require("resilient.layouts.frenchcanon")
    return layout({ quality = q, rule = r })
  end,
  quality = P"regular" + P"demiluxe" + P"deluxe",
  rule = P"12e" + P"10e" + P"halt" + P"valt"
}

return layoutParser
