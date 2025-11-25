--- An invoice support inputter for re·sil·ient.
--
-- The invoice document is a YAML file that describes the transaction details.
--
-- @license MIT
-- @copyright (c) 2025 Omikhleia / Didier Willis
-- @module inputters.invoice

local validate = require("resilient.schemas.validator").validate
local InvoiceSchema = require("resilient.schemas.invoice").InvoiceSchema
local toFacturX = require("resilient.support.invoice.facturx").toFacturX

local CreateCommand = SU.ast.createCommand

--- General I18n helpers
--
-- @section i18n

-- NOTE: For everything related to localization/internationalization,
-- we extend the command environment later, to avoid having to pass
-- the invoice context around all the time.

local i18nResources = {} -- cached loaded resources

--- Retrieves a localized string for the given key.
--
-- @tparam string key Key of the localized string
-- @treturn string Localized string
local function I18n (key)
  local lang = context.language or "en" -- luacheck: ignore
  if not i18nResources[lang] and i18nResources[lang] ~= false then
    local ok, langTable = pcall(require, "resilient.support.invoice.i18n." .. lang)
    if ok and type(langTable) == "table" then
      i18nResources[lang] = langTable
    else
      SU.warn("No localization data found for invoice language '" .. lang .. "'")
      i18nResources[lang] = false -- mark as not found
    end
  end
  return i18nResources[lang] and i18nResources[lang] ~= false and i18nResources[lang][key] or key
end

--- Formats a date as a localized date string.
--
-- @tparam table d Date table with year, month, day fields
-- @treturn string Localized date string
local function Date (d)
  local dateFormat = I18n("date_format") or "%Y-%m-%d"
  return os.date(dateFormat, os.time(d))
end

--- Formats a unit string, with localization when possible.
--
-- @tparam number qty Quantity
-- @tparam string unit Unit code (EA, HUR, etc.)
-- @treturn string Localized unit string
local function Unit (qty, unit)
  local n = tonumber(qty)
  local i18nUnit
  -- Unit ignored if unit is "EA" or absent,
  -- otherwise we try to localize it.
  if unit and unit ~= "EA" then
    local choice = I18n(unit)
    if type(choice) == "table" then
      -- Singular/plural form
      i18nUnit = n == 1 and choice[1] or choice[2]
    elseif type(choice) == "function" then
      -- Complex pluralization function (e.g. Russian)
      i18nUnit = choice(n)
    elseif type(choice) == "string" then
      i18nUnit = choice -- as is
    else
      i18nUnit = unit -- no localization available, use as is.
    end
  end
  return i18nUnit
end

--- Box and span formatting helpers
--
-- @section formatting

--- Creates a vertical box of elements.
--
-- @param ... Content
-- @treturn table Boxed content
local function Box (...)
  local c = {...}
  local elements = {}
  for _, v in pairs(c) do
    if v then
      elements[#elements+1] = v
      elements[#elements+1] = function ()
        -- HACK: Avoid inserting a "par" here, when we are already in vmode.
        if not SILE.typesetter:vmode() then
          SILE.typesetter:leaveHmode()
        end
      end
    end
  end
  return #elements > 0 and elements
end

--- Creates a horizontal span of space-separated elements.
--
-- @param ... Content
-- @treturn table Boxed content
local function Span (...)
  local c = {...}
  local sp = {}
  for _, v in pairs(c) do
    if type(v) == "table" then
      sp[#sp+1] = v
      sp[#sp+1] = " " -- space between items
    elseif v then
      sp[#sp+1] = tostring(v)
      sp[#sp+1] = " " -- space between items
    end
  end
  return #sp > 0 and sp
end

--- Creates a styled span.
--
-- @tparam string name Style name
-- @param ... Content
-- @treturn table Styled content
local function Style (name, ...)
  return CreateCommand("style:apply", { name = name, discardable = "true" }, { ... })
end

--- Creates a styled symbol (convenience function).
--
-- @tparam string sym Symbol character
-- @treturn table Styled symbol
local function Symbol (sym)
  return Style("invoice-symbol", sym)
end

--- Creates a vertical skip (convenience function).
--
-- @treturn table Vertical skip
local function Skip ()
  return CreateCommand("medskip")
end

--- Creates a table row (convenience function).
-- @param ... Cells
-- @treturn table Table row
local function Row (...)
  return SU.ast.createStructuredCommand("row", {}, { ... })
end

--- Creates a table cell (convenience function).
--
-- @tparam table options Cell options
-- @param ... Content of the cell
-- @treturn table Table cell
local function Cell (options, ...)
  return CreateCommand("cell", options or {}, {
    CreateCommand("neverindent"), -- Eventually ptable2 should not need this TODO
    Style(options.normsize and "invoice" or "invoice-table-cell", Span(...))
  })
end

--- Creates a table header cell (convenience function).
--
-- @tparam table options Cell options
-- @param text Header text
-- @treturn table Table header cell
local function HeaderCell (options, text)
  return CreateCommand("cell", options or {}, {
    CreateCommand("neverindent"), -- Eventually ptable2 should not need this TODO
    Style("invoice-table-header", text)
  })
end

--- Creates a paragraph box.
--
-- @tparam table options Parbox options
-- @param ... Content of the parbox
-- @treturn table Parbox
local function ParBox(options, ...)
  return CreateCommand("parbox", options or {}, {
    CreateCommand("neverindent"), -- Eventually ptable2 should not need this TODO
    ...
  })
end

--- Creates a hyperlink or mailto link.
--
-- Web links are also represented with a QR code and a clickable URL.
-- Mail links are represented as clickable email addresses.
--
-- @tparam string uri Link URI
-- @tparam[opt] string text Replacement text
local function Link (uri, text)
  if not uri then
    return -- Nil link will be ignored
  end
  uri = (uri:match("^https?://") or uri:match("^mailto:")) and uri or ("https://" .. uri)
  text = text or uri
  if uri:match("^https?://") then
    return Box(
            CreateCommand("href", { src = uri }, CreateCommand("qrcode", { code = uri, dotted = true })),
            CreateCommand("href", { src = uri },
              CreateCommand("language", { main = "und" },
                CreateCommand("url", {}, { text })))
    )
  end
  return CreateCommand("href", { src = uri },
           CreateCommand("url", {}, { text }))
end

--- Number formatting helpers (currency, percent, decimal)
--
-- @section numbers

-- TODO REPORT Low-level ICU access
-- We need percent etc. not exposed by SILE high-level API SU.formatNumber.
-- We'd also need to enforce the language in SU.formatNumber, currently,
-- to bypass using the "current document" (we are too early in the process for that,
-- and the workaround would be to wrap a command around the content, for no gain).
local icu = require("justenoughicu")

local knownISO4217CurrencySymbol = { -- Not exhaustive, TOTO move to a common module later
  -- Euros, Pounds
  EUR = "€",  -- Euro
  GBP = "£",  -- British pound
  -- Central and Eastern European currencies
  BGN = "лв",   -- Bulgarian lev
  CZK = "Kč",   -- Czech koruna
  HUF = "Ft",   -- Hungarian forint
  PLN = "zł",   -- Polish zloty
  RON = "lei",  -- Romanian leu
  RUB = "₽",    -- Russian ruble
  -- Scandinavian krona/krone are ambiguous, so commented out here.
  --   SEK = "kr",
  --   NOK = "kr",
  --   DKK = "kr",
  --   ISK = "kr",
  -- Dollars
  USD = "$",    -- US dollar
  ARS = "AR$",  -- Argentine peso
  AUD = "A$",   -- Australian dollar
  CLP = "CL$",  -- Chilean peso
  COP = "COP$", -- Colombian peso
  BRL = "R$",   -- Brazilian real
  CAD = "C$",   -- Canadian dollar
  HKD = "HK$",  -- Hong Kong dollar
  MXN = "MX$",  -- Mexican peso
  NIO = "NIO$", -- Nicaraguan córdoba
  NZD = "NZ$",  -- New Zealand dollar
  SGD = "S$",   -- Singapore dollar
  TWD = "NT$",  -- New Taiwan dollar
  UYU = "$U",   -- Uruguayan peso
  ZWD = "Z$" ,  -- Zimbabwean dollar
  ZWL = "Z$" ,  -- Zimbabwean dollar
  -- Others
  CNY = "CN¥",  -- Chinese yuan
  CRC = "₡",    -- Costa Rican colón
  GTQ = "Q",    -- Guatemalan quetzal
  HNL = "L" ,   -- Honduran lempira
  ILS = "₪",    -- Israeli new shekel
  INR = "₹",    -- Indian rupee
  JPY = "¥",    -- Japanese yen
  KRW = "₩",    -- South Korean won
  PEN = "S/",   -- Peruvian sol
  PHP = "₱",    -- Philippine peso
  PYG = "₲",    -- Paraguayan guaraní
  --SVC = "₡" ,   -- Salvadoran colón (deprecated, now uses USD)
  THB = "฿",    -- Thai baht
  TRY = "₺",    -- Turkish lira
  -- VES = "Bs.", -- Venezuelan bolívar
  -- BOB = "Bs.", -- Bolivian boliviano
  VND = "₫",    -- Vietnamese dong
  ZAR = "R",    -- South African rand
}

--- Formats a number as a decimal string.
--
-- The numerical value is formatted according to locale-dependent conventions.
--
-- @tparam number n Numerical value
-- @treturn string Formatted decimal number
local function Decimal (n)
  local lang = context.language or "en" -- luacheck: ignore
  n = SU.cast("number", n)
  local formatted = icu.format_number(n, lang, 1) -- 1 = UNUM_DECIMAL
  return formatted
end

--- Formats a number as a currency string.
--
-- The numerical value is formatted according to locale-dependent conventions.
-- The position of the currency symbol also depends on the language.
-- When known, the currency symbol is used instead of the ISO 4217 code.
--
-- @tparam number n Numerical value
-- @tparam string currency ISO 4217 currency code
-- @treturn string Formatted currency
local function Currency (n, currency)
  local lang = context.language or "en" -- luacheck: ignore
  n = SU.cast("number", n)
  currency = knownISO4217CurrencySymbol[currency:upper()] or currency
  local formatted = icu.format_number(n, lang, 10) -- 10 = UNUM_CURRENCY
    :gsub("[A-Z][A-Z][A-Z]", currency) -- replace ISO code by symbol
  return formatted
end

--- Formats a number as a percentage string.
--
-- The numerical value is formatted according to locale-dependent conventions.
--
-- @tparam number n Number between 0 and 1.
-- @treturn string Formatted perrcentage
local function Percent (n)
  local lang = context.language or "en" -- luacheck: ignore
  -- ICU is not reliable/sufficient here, it rounds percentages to integers
  -- but we can have taxes such as 5.5%...
  -- HACK: We'll do a ISO currency format and replace the symbol.
  n = SU.cast("number", n)
  n = n * 100
  local formatted = icu.format_number(n, lang, 10) -- 10 = UNUM_CURRENCY
    :gsub("[A-Z][A-Z][A-Z]","") -- remove currency ISO code,
    .. "%"                      -- and dd percent sign at the end.
  return formatted
end

local knownISO3166Country = { -- Not exhaustive, TODO move to a common module later
  -- In English and in their own language where possible
  FR = "France",
  DE = "Germany – Deutschland",
  ES = "Spain – España",
  IT = "Italy – Italia",
  PT = "Portugal",
  NL = "Netherlands – Nederland",
  BE = "Belgium – België – Belgique",
  IS = "Iceland – Ísland",
  GB = "United Kingdom",
  US = "United States",
  CA = "Canada",
  AU = "Australia",
  RU = "Russia – Россия",
}

--- Formats a country code as a country name.
--
-- @tparam string code ISO 3166-1 country code
-- @treturn string Country name
local function Country (code)
  local known = knownISO3166Country[code:upper()]
  return known and Span(known, "("  .. code:upper() .. ")") or code:upper()
end

--- Invoice-related formatting helpers
--
-- @section invoice

local sym = {
  email = luautf8.char(0x1F4E7),
  phone = luautf8.char(0x2706),
  bullet = luautf8.char(0x2022),
}

--- Creates address location lines.
--
-- @tparam table it Address table
-- @treturn table Boxed location lines
local function addressLocations (it)
  local location = {}
  if it.location then
    -- Note that Factur-X expects up to 3 location lines
    -- We allow any number here but only the first 3 will be used in Factur-X export,
    -- Should we warn, truncate silently, or consider it as a convenience feature?
    for _, line in ipairs(it.location) do
      location[#location+1] = Box(line)
    end
    return location
  end
end

--- Creates a postal trade address box.
--
-- @tparam table it Address table
-- @treturn table Boxed postal trade address
local function postalTradeAddress (it)
  if not it then
    return
  end
  return Box(
    addressLocations(it),
    Span(it["postal-code"], it.city),
    Country(it.country)
  )
end

--- Creates a defined trade contact box.
-- @tparam table it Contact table
-- @treturn table Boxed contact details
local function definedTradeContactBox (it)
  return Box(
    Span(it.name),
    it.department and Span(it.department),
    it.phone and Span(Symbol(sym.phone), it.phone),
    it.email and Span(Symbol(sym.email), Link("mailto:" .. it.email, it.email))
  )
end

--- Creates a trade party box (seller or buyer).
--
-- @tparam table it Trade party table
-- @treturn table Boxed trade party
local function tradePartyBox (it)
  return Box(
    Box(Style("invoice-company", it.name)),
    postalTradeAddress(it.address),
    it.uri and Style("invoice-website", Link(it.uri)),
    it.contact and Style("invoice-contact",
      Box(
        Skip(),
        Style("invoice-contact-header", I18n("contact")),
        definedTradeContactBox(it.contact)
      ),
      SU.ast.createCommand("par")
    )
  )
end

--- Creates address location on one line for footers.
--
-- @tparam table it Address table
-- @treturn table Boxed location lines
local function oneLineAddressLocations (it)
  local location = {}
  if it.location then
    -- Note that Factur-X expects up to 3 location lines
    -- We allow any number here but only the first 3 will be used in Factur-X export,
    -- Should we warn, truncate silently, or consider it as a convenience feature?
    for _, line in ipairs(it.location) do
      location[#location+1] = { " ", Symbol(sym.bullet), " ", line }
    end
    return location
  end
end

--- Creates a postal trade address box on one line for footers.
--
-- @tparam table it Address table
-- @treturn table Boxed postal trade address
local function oneLinePostalTradeAddress (it)
  if not it then
    return
  end
  return Span(
    oneLineAddressLocations(it),
    it.city and Symbol(sym.bullet),
    it["postal-code"] and it["postal-code"],
    it.city,
    Symbol(sym.bullet),
    Country(it.country)
  )
end

--- Creates a one-line trade party box for footers.
-- @tparam table it Trade party table
-- @treturn table Boxed trade party
local function oneLineTradePartyBox (it)
  return {
    it.name,
    oneLinePostalTradeAddress(it.address)
  }
end

--- Wrap a table of line items.
--
-- @tparam table rows Table rows
-- @treturn table Styled table
local function lnesTable (rows)
  -- TODO: Not generic... and bad table API usage...
  -- Interesting challenge to also reconsider when working on ptable2.
  local rows2 = pl.tablex.copy(rows)
  table.insert(rows2, 1,
    SU.ast.createStructuredCommand("row", {
    }, {
      HeaderCell({ border = "0.8pt 0.4pt 0 0", valign = "top", halign = "center" }, I18n("line_id")),
      HeaderCell({ border = "0.8pt 0.4pt 0 0", valign = "top", halign = "center" }, I18n("line_description")),
      HeaderCell({ border = "0.8pt 0.4pt 0 0", valign = "top", halign = "center" }, I18n("line_quantity")),
      HeaderCell({ border = "0.8pt 0.4pt 0 0", valign = "top", halign = "center" }, I18n("line_unit_price")),
      HeaderCell({ border = "0.8pt 0.4pt 0 0", valign = "top", halign = "center" }, I18n("line_tax_rate")),
      HeaderCell({ border = "0.8pt 0.4pt 0 0", valign = "top", halign = "center" }, I18n("line_gross_amount")),
    })
  )
  local t = SU.ast.createStructuredCommand("ptable", {
    -- Hardcoded for invoice line items...
    cols = "5%fw 44%fw 11%fw 15%fw 10%fw 15%fw",
    cellborder = 0,
    header =  true,
  }, rows2)
  return Style("invoice-table", t)
end

--- Wrap a table of computed total values.
--
-- @tparam table rows Table rows
-- @treturn table Styled table
local function totalTable (rows)
  -- TODO: As above, not generic...
  local t = SU.ast.createStructuredCommand("ptable", {
    cols = "10%fw 25%fw 10%fw 12%fw 8%fw 17%fw 18%fw",
    cellborder = 0,
    header = false,
  }, rows)
  return Style("invoice-table", t)
end

--- Creates a line item box.
--
-- @tparam table it Line item
-- @tparam table invoice Invoice context
-- @tparam boolean isLast Is this the last line item?
-- @treturn table Boxed line item
local function lineItemBox (it, invoice, isLast)
  local border = isLast and "0 0.8pt 0 0" or nil
  return Row(
    Cell({ border = border, valign="middle", halign = "center" },
      Style("invoice-line-id", tostring(it.id))
    ),
    Cell({ border = border, valign="middle", halign = "left"   },
      --Support proper paragraph breaks at line breaks (let's avoid SILE's obey line weird settings)
      Style("invoice-line-description", (it.description:gsub("\n+", "\n\n"):gsub("\n+$",""):gsub("^\n+","")))
    ),
    Cell({ border = border, valign="middle", halign = "right"  },
      Decimal(it.quantity), it.unit and it.unit ~= "EA" and Style("invoice-unit", Unit(it.quantity, it.unit))
    ),
    Cell({ border = border, valign="middle", halign = "right"  },
      Currency(it["unit-price"], invoice.currency)
    ),
    Cell({ border = border, valign="middle", halign = "right"  },
      Percent(it["tax-rate"])
    ),
    -- Computed column (tax, total amount incl. tax)
    Cell({ border = border, valign="middle", halign = "right"  },
      Style("invoice-line-total", Currency(it["unit-price"] * it.quantity * (1 + it["tax-rate"]), invoice.currency))
    )
  )
end

--- Wrap line items into a table.
--- @tparam table lines Line items
-- @tparam table invoice Invoice context
-- @treturn table Styled table of line items
local function lineItemsBox (lines, invoice)
  local items = {}
  for k, it in ipairs(lines) do
    items[#items+1] = lineItemBox(it, invoice, k == #lines)
  end
  return lnesTable(items)
end

--- Creates the total values box.
--
-- @tparam table lines Line items
-- @tparam table invoice Invoice context
-- @treturn table Styled table
local function totalValuesBox(lines, invoice)
  local dueDate
  if type(invoice["due-date"]) == "table" then
    -- date object
    dueDate = Span(Style("invoice-table-header", I18n("invoice_due_date")..":"), Date(invoice["due-date"]))
  elseif type(invoice["due-date"]) == "number" then
    -- number of days
    local ndays = invoice["due-date"]
    local paymentTermsSentence = Unit(ndays, "invoice_due_terms")
    local dayUnitInTerms = Unit(ndays, "day_terms")
    dueDate = Style("invoice-table-header",
      paymentTermsSentence:gsub("{day_terms}", dayUnitInTerms):gsub("{days}", ndays)
    )
  end

  local netAmount = 0
  local taxes = 0
  for _, it in ipairs(lines) do
    local lineTotal = (it["unit-price"] or 0) * (it.quantity or 0)
    netAmount = netAmount + lineTotal
    local lineTax = lineTotal * (it["tax-rate"] or 0)
    taxes = taxes + lineTax
  end
  return totalTable({
    Row(
      Cell({ span = 5 }, {}),
      Cell({ border = "0.8pt 0 0 0", valign = "middle", halign = "left"  },
        Style("invoice-table-header", I18n("total_net_amount"))),
      Cell({ border = "0.8pt 0 0 0", valign = "middle", halign = "right" },
        Style("invoice-grand-total", Currency(netAmount , invoice.currency))
      )
    ),
    Row(
      Cell({ span = 5 }, {}),
      Cell({ border = "0.4pt 0 0 0", valign = "middle", halign = "left" },
        Style("invoice-table-header", I18n("total_taxes"))
      ),
      Cell({ border = "0.4pt 0 0 0", valign = "middle", halign = "right" },
        Style("invoice-grand-total", Currency(taxes, invoice.currency))
      )
    ),
    Row(
      Cell({ span = 5, normsize = true, border = "1pt 1pt 1pt 0", background = "whitesmoke" }, dueDate),
      Cell({ border = "1pt 1pt 0pt 0", background="whitesmoke", valign = "middle", halign = "left" },
        Style("invoice-table-header", I18n("total_amount_due"))
      ),
      Cell({ border = "1pt 1pt 0 1pt", padding="10pt 10pt 5pt 5pt", background="whitesmoke", valign = "middle", halign = "right" },
        Style("invoice-grand-total", Currency(netAmount + taxes, invoice.currency))
      )
    )
  })
end

--- Creates the payment means box.
--
-- @tparam table it Payment means table
-- @tparam table seller Seller trade party
-- @treturn table Boxed payment means
local function paymentMeansBox (it, seller)
  if not it then
    return
  end
  local means = {}
  if it.bank then
    local rows = {
      Row(
        Cell({ valign = "middle", halign = "left" },
          "IBAN"
        ),
        Cell({ valign = "middle", halign = "left" },
          Style("invoice-bank-account", it.bank.iban)
        )
      )
    }
    if it.bank.bic then
      rows[#rows+1] = Row(
        Cell({ valign = "middle", halign = "left" },
          "BIC"
        ),
        Cell({ valign = "middle", halign = "left" },
          Style("invoice-bank-account", it.bank.bic)
        )
      )
    end
    if it.bank.name then
      rows[#rows+1] = Row(
        Cell({ span = 2, valign = "middle", halign = "left" },
          it.bank.name
        )
      )
    end
    means[#means+1] = Box(
      I18n("payment_bank"),
      SU.ast.createStructuredCommand("ptable", { cols = "10%fw 90%fw", cellborder = 0 }, rows)
    )
  end
  if it.cheque then
    local payee = it.cheque.name or seller.name
    means[#means+1] = Box(
      (I18n("payment_cheque"):gsub("{payee}", payee))
    )
  end
  return #means > 0 and means or nil
end

--- Main invoice box.
--
-- @tparam table invoice Invoice data
-- @treturn table Boxed invoice
local function mainInvoiceBox (invoice)
    local logo = nil
  if invoice.seller and invoice.seller.logo then
    if SILE.resolveFile(invoice.seller.logo) == nil then
      SU.warn("Seller logo file '" .. invoice.seller.logo .. "' not found.")
    else
      logo =
        CreateCommand("img", {
          src = invoice.seller.logo,
          width = "50pt",
        })
    end
  end
  return Style("invoice",
    CreateCommand("neverindent"),
    Box(
      {
        ParBox({ width = "60pt", minimize = true, valign = "middle" }, {
          logo,
        }),
        CreateCommand("quad"),
        ParBox({ width = "60%pw", valign = "middle" },
          CreateCommand("raggedright", {}, {
            Style("invoice-company-header", {
              invoice.seller.name,
              --CreateCommand("par") -- Leaking paragraph due to color handling? TODO
            }),
          })
        )
      },
      Skip(),
      Skip(),
      CreateCommand("center", {}, {
        Style("invoice-id", Span(I18n("invoice"), invoice.id)),
      }),
      Skip(),
      CreateCommand("center", {}, {
        Box(
          Span(Style("invoice-date-label", I18n("invoice_issue_date") .. ":"), Date(invoice["issue-date"])),
          invoice["delivery-date"] and Span(Style("invoice-date-label", I18n("invoice_delivery_date") .. ":"), Date(invoice["delivery-date"]))
        ),
      }),
      Skip(),
      Skip(),
      {
        CreateCommand("roundbox", { border = "0.6pt", padding = "6pt", shadow = true, shadowcolor = "lightgray" },
          Style("invoice-buyer-block",
            ParBox({ width = "45%pw", valign = "middle" }, {
              Style("invoice-buyer", tradePartyBox(invoice.buyer)),
            })
          )
        ),
        CreateCommand("hfill"),
        Style("invoice-seller-block",
          ParBox({ width = "30%pw", valign = "middle", minimize = true }, {
            Style("invoice-seller", tradePartyBox(invoice.seller)),
        })
      ),
      },
      Skip(),
      lineItemsBox(invoice.lines, invoice),
      totalValuesBox(invoice.lines, invoice),
      paymentMeansBox(invoice.payment, invoice.seller),
      Skip(),
      -- Support proper paragraph breaks at line breaks (let's avoid SILE's obey line weird settings)
      invoice.note and Style("invoice-note", (invoice.note:gsub("\n+", "\n\n"):gsub("\n+$",""):gsub("^\n+","")))
    )
  )
end

--- Misceallaneous helpers
--
-- @section misc

-- COOL TRICK: Wrapper to extend the environment of a function.
-- We'll use it to provide a "context" to some of our helpers,
-- so that not to have to explicitly pass the invoice object around all the time.

--- Extends the environment of a function with extra variables.
--
-- It's a cool Lua trick to extend the environment of a function.
-- We'll use it to provide a "context" to some of our i18n helpers,
-- so that not to have to explicitly pass the invoice object around all the time.
--
-- @tparam function fn Function to extend
-- @tparam table extras Extra variables to add to the function environment
-- @treturn function Extended function
local function extendFunctionEnvironment(fn, extras)
  local env = setmetatable(extras or {}, { __index = _G })
  if _VERSION == "Lua 5.1" then
    -- Strategies differ between Lua 5.1 and later versions.
    -- In Lua 5.1 we can use setfenv.
    -- luacheck: push globals setfenv
    setfenv(fn, env)
    -- luacheck: pop
    return fn
  end
  -- In Lua 5.2+ we need to create a closure.
  -- _ENV is a special upvalue recognized by the compiler.
  return function(...)
    local _ENV = env -- luacheck: ignore
    return fn(...)
  end
end

--- Inputter implementation (appropriation, parsing, generation)
--
-- @section inputter

--- The "invoice" inputter for re·sil·ient.
--
-- Extends SILE's `inputters.base`.
--
-- @type inputters.silm

local base = require("inputters.base")

local inputter = pl.class(base)
inputter._name = "invoice"
inputter.order = 2

--- (Override) Whether this inputter is appropriate for a given file.
--
-- @tparam number round Detection round (1 = by extension, etc.)
-- @tparam string filename Filename
-- @tparam string doc Document content (not used here)
-- @treturn boolean Whether this inputter is appropriate
function inputter.appropriate (round, filename, doc)
   if round == 1 then
      local promising = filename:match(".yml$") or filename:match(".yaml$")
      return promising and inputter.appropriate(2, filename, doc) or false
   elseif round == 2 then
      local sniff = doc:sub(1, 100)
      local promising = sniff:match("^invoice:") ~= nil
      return promising and inputter.appropriate(3, filename, doc) or false
   elseif round == 3 then
      -- Try to parse as YAML
      local yaml = require("resilient-tinyyaml")
      local t = yaml.parse(doc)
      if type(t) ~= "table" or not t.invoice then
        return false
      end
      return true -- further validation will be done at parsing time, and has no impact on appropriateness
   end
end

--- (Override) Parse the given document and return a SILE AST.
--
-- @tparam string doc Document content
function inputter:parse (doc)
  local yaml = require("resilient-tinyyaml")
  local t = yaml.parse(doc)
  if type(t) ~= "table" then
    SU.error("Invalid document (not a table)")
  end
  local ok, err = validate(t, InvoiceSchema)
  if not ok then
    SU.error("Invalid document (" .. err .. ")")
  end
  local invoice = t.invoice

  -- Extend function environments for i18n and number formatting
  local context = { context = { language = invoice.language or "en" } }
  I18n     = extendFunctionEnvironment(I18n, context)
  Currency = extendFunctionEnvironment(Currency, context)
  Percent  = extendFunctionEnvironment(Percent, context)
  Decimal  = extendFunctionEnvironment(Decimal, context)

  local content = {}

  -- Are we the root document, or some included subdocument?
  -- In a root standalone document, we'll want to generate a Factur-X compliant PDF,
  -- with proper XMP metadata and attachments.
  local isRoot = not SILE.documentState.documentClass

   -- Load needed packages
  local neededPackages = {
    "packages.background",
    "packages.framebox",
    "packages.image",
    "packages.ptable",
    "packages.qrcode",
    "packages.resilient.attachments",
    "packages.resilient.invoice",
  }
  for _, pkg in ipairs(neededPackages) do
    content[#content+1] = CreateCommand("use", {
      module = pkg
    })
  end

  if isRoot then
      content[#content+1] = CreateCommand("invoice-footer", {},
        oneLineTradePartyBox(invoice.seller)
      )
    end

  content[#content+1] =  CreateCommand("language", { main =  invoice.language or "en" },
    mainInvoiceBox(invoice)
  )

  if isRoot then
    local documentKey = "invoice_" .. tostring(invoice.id) .. string.format("_%04d%02d%02d",
       invoice["issue-date"].year,
       invoice["issue-date"].month,
       invoice["issue-date"].day
     )

    content[#content+1] = CreateCommand("xmp-set-document", {
      key = documentKey,
      type = "facturx",
    })
    content[#content+1] = CreateCommand("raw", {
      type = "attachment",
      src = "factur-x.xml",
      description = "Factur-X 1.07.2 ZUGFeRD 2.3.2 EN16931 invoice XML",
      relation = "Alternative",
    }, toFacturX(invoice) )

    content[#content+1] = CreateCommand("raw", {
      type = "attachment",
      src = "invoice.yaml",
      mime = "application/yaml", -- MIME type is not guessed from extension correctly
      description = "Original invoice YAML source file",
      relation = "Source",
    }, doc )

    if invoice.seller.logo and SILE.resolveFile(invoice.seller.logo) then
      content[#content+1] = CreateCommand("attachment", {
        src = invoice.seller.logo,
        description = invoice.seller.name .. " logo image",
        relation = "Supplement",
      })
    end
    if invoice.buyer.logo and SILE.resolveFile(invoice.buyer.logo) then
      content[#content+1] = CreateCommand("attachment", {
        src = invoice.buyer.logo,
        description = invoice.buyer.name .. " logo image",
        relation = "Supplement",
      })
    end
    local styleFname = SILE.masterFilename and SILE.masterFilename .. '-styles.yml'
    if styleFname and SILE.resolveFile(styleFname) then
      content[#content+1] = CreateCommand("attachment", {
        src = styleFname,
        mime = "application/yaml", -- MIME type is not guessed from extension correctly
        description = "Invoice YAML style file for re·sil·ient",
        relation = "Source",
      })
    else
      SU.warn("No invoice styles YAML file found alongside the main document; skipping attachment.")
    end

    content[#content+1] = CreateCommand("pdf:metadata", {
      key = "Author",
      value = invoice.seller.name,
    })
    local title = I18n("invoice") .. " " .. tostring(invoice.id)
    content[#content+1] = CreateCommand("pdf:metadata", {
      key = "Title",
      value = title,
    })
    content[#content+1] = CreateCommand("pdf:metadata", {
      key = "Subject",
      value = title, -- Using same as title
    })
  end

  -- Document wrap-up
  local options = {
    class = "resilient.base", -- Minimal base class
    papersize = "a4",
  }

  local tree = {
    SU.ast.createStructuredCommand("document", options, content),
  }
  return tree
end

return inputter
