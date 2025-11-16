--- Convenience support package for invoices made with re·sil·ient.
--
-- This internal package is used by the "invoice" inputter for styling invoice content.
--
-- @license MIT
-- @copyright (c) 2024-2025 Omikhkeia / Didier Willis
-- @module packages.resilient.invoice

--- The "resilient.invoice" package.
--
-- Extends SILE's `packages..resilient.base`.
--
-- @type packages.resilient.invoice

local base = require("packages.resilient.base")
local package = pl.class(base)
package._name = "resilient.invoice"

--- (Constructor) Initialize the package.
-- @tparam table _ Package options (not used here)
function package:_init ()
  base._init(self)

  self:loadPackage("url")
  -- Override the standard urlstyle hook to rely on styles
  -- N.B. Package "url" is loaded by the markdown package.
  self:registerCommand("urlstyle", function (_, content)
    print("Styling URL content:", content)
    SILE.call("style:apply", { name = "invoice-uri" }, content)
  end)
end

-- None for now.
-- (Override) Register all commands provided by this package.
-- function package:registerCommands ()
-- end

--- (Override) Register all styles provided by this package.
function package:registerStyles ()
  self:registerStyle("invoice", {}, {
    font = {
      family = "Libertinus Serif",
      size = "10pt",
    },
  })
  self:registerStyle("invoice-grand-total", {}, {
    font = {
      weight = 700,
      size = "1.1em",
      color = "red",
    },
  })
  self:registerStyle("invoice-line-description", {}, {
  })
  self:registerStyle("invoice-line-id", {}, {
    font = {
      weight = 700,
    },
  })
  self:registerStyle("invoice-line-total", {}, {
  })
  self:registerStyle("invoice-table", { inherit = "invoice" }, {
    font = {
      size = "0.95em",
    },
  })
  self:registerStyle("invoice-table-cell", { inherit = "invoice-table" }, {
  })
  self:registerStyle("invoice-table-header", { inherit = "invoice-table" }, {
    font = {
      weight = 700,
    },
  })
  self:registerStyle("invoice-unit", {}, {
    font = {
      size = "0.6em",
      style = "italic",
    },
  })
  self:registerStyle("invoice-uri", {}, {
  })
  self:registerStyle("invoice-symbol", {}, {
    font = {
      family = "Symbola",
    },
    color = "#4080bf",
  })

end

package.documentation = [[
\begin{document}
The \autodoc:package{resilient.invoiice} is currently for internal use only.

\end{document}
]]

return package
