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

  self:loadPackage("folio")
  self:loadPackage("url")
  self:registerCommand("urlstyle", function (_, content)
    SILE.process(content) -- Just process the content as is for now, style handling is done elsewhere
  end)
end

--- (Override) Register all commands provided by this package.
function package:registerCommands ()
  self:registerCommand("invoice-footer", function (_, content)
    -- Override the standard urlstyle hook to rely on styles + use our footer
    self:registerCommand("foliostyle", function (_, folioContent)
      SILE.call("style:apply", { name = "invoice-footer" }, {
        SU.ast.createCommand("hbox"),
        SU.ast.createCommand("hfill"),
        SU.ast.subContent(content),
        SU.ast.createCommand("hfill"),
        SU.ast.subContent(folioContent)
      })
    end)
  end)
end

--- (Override) Register all styles provided by this package.
function package:registerStyles ()
  self:registerStyle("invoice", {}, {
    font = {
      family = "Libertinus Serif",
      size = "10pt",
    },
  })
  self:registerStyle("invoice-theme", {}, {
    color = "#204080",
  })
  self:registerStyle("invoice-company-header", { inherit = "invoice-theme" }, {
    font = {
      family = "Libertinus Sans",
      weight = 700,
      size = "2em",
    },
  })
  self:registerStyle("invoice-date-label", { inherit = "invoice-theme" }, {
    font = {
      weight = 700,
    },
  })
  self:registerStyle("invoice-id", { inherit = "invoice-theme" }, {
    font = {
      family = "Lato",
      size = "2em",
      weight = 700,
    },
    properties = {
      case = "upper",
    },
  })
  self:registerStyle("invoice-company", {}, {
    font = {
      family = "Libertinus Sans",
      weight = 700,
    },
  })
  self:registerStyle("invoice-contact", {}, {
    font = {
      size = "0.9em",
    },
  })
  self:registerStyle("invoice-buyer-block", {}, {
  })
  self:registerStyle("invoice-seller-block", {}, {
    color = "#606060",
  })
  self:registerStyle("invoice-buyer", { inherit = "invoice" }, {
  })
  self:registerStyle("invoice-seller", { inherit = "invoice" }, {
    font = {
      size = "0.8em",
    },
  })
  self:registerStyle("invoice-bank-account", {}, {
    font = {
      family = "Hack",
      adjust = "ex-height",
    },
  })
  self:registerStyle("invoice-contact-header", {}, {
    font = {
      style = "italic",
      weight = 700,
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
  self:registerStyle("invoice-website", {}, {
    font = {
      size = "0.8em",
    },
  })
  self:registerStyle("invoice-symbol", { inherit = "invoice-theme" }, {
    font = {
      family = "Symbola",
    },
  })
  self:registerStyle("invoice-note", { inherit = "invoice-theme" }, {
    font = {
      family = "Mynerve",
    },
  })
  self:registerStyle("invoice-footer", {}, {
    font = {
      family = "Lato",
      size = "0.75em",
    },
  })
end

package.documentation = [[
\begin{document}
The \autodoc:package{resilient.invoiice} is currently for internal use only.

\end{document}
]]

return package
