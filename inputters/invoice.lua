--- An invoice support inputter for re·sil·ient.
--
-- The invoice document is a YAML file that describes the transaction details.
--
-- @license MIT
-- @copyright (c) 2025 Omikhleia / Didier Willis
-- @module inputters.invoice

local validate = require("resilient.schemas.validator").validate
local InvoiceSchema = require("resilient.schemas.invoice").InvoiceSchema

local CreateCommand = SU.ast.createCommand

-- I18N HELPERS FOR INVOICES

-- For everything related to localization/internationalization,
-- we extend the command environment later, to avoid having to pass
-- the invoice context around all the time.

local i18nResources = {}
local function I18n (key)
  local lang = invoice.language or "en" -- luacheck: ignore
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

local function Date (d)
  local dateFormat = I18n("date_format") or "%Y-%m-%d"
  return os.date(dateFormat, os.time(d))
end

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

-- NUMBER FORMATTING HELPERS (CURRENCY, PERCENT, DECIMAL)

-- TODO REPORT Low-level ICU access
-- We need percent etc. not exposed by SILE high-level API SU.formatNumber.
-- We'd also need to enforce the language in SU.formatNumber, currently,
-- to bypass using the "current document" (we are too early in the process for that,
-- and the workaround would be to wrap a command around the content, for no gain).
local icu = require("justenoughicu")

local knownISO4217CurrencySymbol = { -- Not exhaustive
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

local function Decimal (n)
  n = SU.cast("number", n)
  local formatted = icu.format_number(n, invoice.language, 1) -- 1 is UNUM_DECIMAL
  return formatted
end

local function Currency (n, currency)
  n = SU.cast("number", n)
  currency = knownISO4217CurrencySymbol[currency:upper()] or currency
  local formatted = icu.format_number(n, invoice.language, 10) -- 10 is UNUM_CURRENCY
    :gsub("[A-Z][A-Z][A-Z]", currency) -- replace currency symbol
  return formatted
end

local function Percent (n)
  local lang = invoice.language or "en" -- luacheck: ignore
  -- ICU is not reliable/sufficient here, it rounds percentages to integers
  -- but we can have taxes such as 5.5%...
  -- HACK: We'll do a ISO currency format and replace the symbol.
  n = SU.cast("number", n)
  n = n * 100
  local formatted = icu.format_number(n, lang, 10)
    :gsub("[A-Z][A-Z][A-Z]","") -- remove currency symbol,
    .. "%"                      -- and dd percent sign at the end.
  return formatted
end

-- FORMATTING HELPERS

local function Box (...)
  local c = {...}
  local elements = {}
  for _, v in pairs(c) do
    if v then
      elements[#elements+1] = v
      elements[#elements+1] = CreateCommand("par")
    end
  end
  return #elements > 0 and elements
end

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

local function Style(name, ...)
  return CreateCommand("style:apply", { name = name, discardable = "true" }, Span(...))
end

local function Symbol (sym)
  return Style("invoice-symbol", sym)
end

local function Skip ()
  return CreateCommand("medskip")
end

local function Row (...)
  return SU.ast.createStructuredCommand("row", {}, { ... })
end

local function Cell (options, ...)
  return CreateCommand("cell", options or {},
    Style("invoice-table-cell", Span(...))
  )
end

local function HeaderCell (options, ...)
  return CreateCommand("cell", options or {},
    Style("invoice-table-header", Span(...))
  )
end

local function Strong (text)
  if text then
    return CreateCommand("strong", {}, { type(text) == "table" and text or tostring(text) })
  end
end

local function Link (text)
  if not text then
    return -- Nil link will be ignored
  end
  local uri = text:match("^https?://") or text:match("^mailto:") and text or ("https://" .. text)
  print("URI:", uri, "text:", "[[" .. text .. "]]")
  if uri:match("^https?://") then
    return Box(
            CreateCommand("href", { src = uri }, CreateCommand("qrcode", { code = text, dotted = true, colored = true })),
            CreateCommand("href", { src = uri },
              CreateCommand("language", { main = "und" },
                CreateCommand("url", {}, { text })))
    )
  end
  return CreateCommand("href", { src = uri },
           CreateCommand("url", {}, { text }))
end

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

local function addressbox (it)
  if not it then
    return
  end
  return Box(
    addressLocations(it),
    Span(it["postal-code"], it.city),
    Span(it.country)
  )
end

-- FIXME: We'll also want resilient style eventually on links and sym...
local sym = {
  email = luautf8.char(0x1F4E7),
  phone = luautf8.char(0x2706),
  bullet = luautf8.char(0x2022),
}

local function contactBox (it)
  return Box(
    Span(it.name),
    it.department and Span(it.department),
    it.phone and Span(Symbol(sym.phone), it.phone),
    it.email and Span(Symbol(sym.email), Link("mailto:" .. it.email, it.email))
  )
end

local function tradePartyBox (it)
  return Box(
    Box(Strong(it.name)),
    addressbox(it.address),
    Link(it.uri),
    it.contact and Box(
      Skip(),
      Strong(I18n("contact")),
      contactBox(it.contact)
    )
  )
end


local function Table (rows)
  -- FIXME: No generic... And bad API
  -- Interesting challenge to also reconsider the ptable package API here...
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
    -- Hardcoded for invoice line items:
    -- Columns: ID, Description, Quantity, Unit Price, Tax Rate, Line Total HT, Line Total incl.
    -- Hence: 7 columns
    -- Appropriate % widths: 5%, 42%, 13%, 15%, 10%, 15%
    cols = "5%fw 44%fw 11%fw 15%fw 10%fw 15%fw",
    cellborder = 0,
    header =  true,
  }, rows2)
  return Style("invoice-table", t)
end

local function Table2 (rows)
  -- FIXME: No generic... see above
  local t = SU.ast.createStructuredCommand("ptable", {
    cols = "10%fw 25%fw 10%fw 15%fw 8%fw 17%fw 15%fw",
    cellborder = 0,
    header = false,
  }, rows)
  return Style("invoice-table", t)
end


local function lineItemBox (it, invoice, isLast)
  local border = isLast and "0 0.8pt 0 0" or nil
  return Row(
    Cell({ border = border, valign="middle", halign = "center" },
      Style("invoice-line-id", tostring(it.id))
    ),
    Cell({ border = border, valign="middle", halign = "left"   },
      --Support proper paragraph breaks at line breaks (let's avoid SILE's obey line weird settings)
      Style("invoice-line-description", it.description:gsub("\n+", "\n\n"):gsub("\n+$",""):gsub("^\n+",""))
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

local function lineItemsBox (lines, invoice)
  local items = {}
  for k, it in ipairs(lines) do
    items[#items+1] = lineItemBox(it, invoice, k == #lines)
  end
  return Table(items)
end


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
  return Table2({
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
      Cell({ span = 5 }, dueDate),
      Cell({ border = "1pt 1pt 1pt 0", background="whitesmoke", valign = "middle", halign = "left" },
        Style("invoice-table-header", I18n("total_amount_due"))
      ),
      Cell({ border = "1pt 1pt 0 1pt", padding="10pt 10pt 5pt 5pt", background="whitesmoke", valign = "middle", halign = "right" },
        Style("invoice-grand-total", Currency(netAmount + taxes, invoice.currency))
      )
    )
  })
end

-- INPUTTER

--- The "invoice" inputter for re·sil·ient.
--
-- Extends SILE's `inputters.base`.
--
-- @type inputters.silm

local base = require("inputters.base")

local inputter = pl.class(base)
inputter._name = "invoice"
inputter.order = 2

--- (Override) Whether this inputter is appropriate for the given file.
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

  local toFacturX = require("resilient.support.invoice.facturx").toFacturX

  local invoice = t.invoice

  -- Are we the root document, or some included subdocument?
  -- In a root standalone document, we'll want to generate a Factur-X compliant PDF,
  -- with proper XMP metadata and attachments.
  local isRoot = not SILE.documentState.documentClass

  local content = {}

  local neededPackages = {
    "packages.framebox",
    "packages.font-fallback",
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

  -- FIXME TODO: We don't do it on isRoot only, because we may want to
  -- include an invoice inside another document, and still have the proper fonts.
  -- I haven't checked the side effects of loading these packages multiple times,
  -- and declaring multiple font fallbacks.
  content[#content+1] = CreateCommand("font:add-fallback", {
    family = "Symbola", -- FIXME: Should use styles
  })
  content[#content+1] = CreateCommand("neverindent")

  if isRoot then
      content[#content+1] = CreateCommand("language", {
        main = invoice.language or "en",
      })
  end

  -- Wrapper to extend the environment of a function.
  -- We'll use it to provide some context to some of our helpers,
  -- so that not to have to explicitly pass the invoice object around all the time.
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
  I18n = extendFunctionEnvironment(I18n, { invoice = invoice }) -- Overkill. Actually we only need invoice.language here... FIXME
  Currency = extendFunctionEnvironment(Currency, { invoice = invoice })
  Percent = extendFunctionEnvironment(Percent, { invoice = invoice })
  Decimal = extendFunctionEnvironment(Decimal, { invoice = invoice })

  local logo = nil
  if invoice.seller and invoice.seller.logo then
    if SILE.resolveFile(invoice.seller.logo) == nil then
      SU.warn("Seller logo file '" .. invoice.seller.logo .. "' not found.")
    else
      logo =
        CreateCommand("img", {
          src = invoice.seller.logo,
          width = "100pt",
        })
    end
  end
  content[#content+1] = Style("invoice",
    Box(
      logo,
      Span(Strong(I18n("invoice")), invoice.id),

      invoice["issue-date"] and Span(Strong(I18n("invoice_issue_date")), Date(invoice["issue-date"])),
      invoice["delivery-date"] and Span(Strong(I18n("invoice_delivery_date")), Date(invoice["delivery-date"])),

      tradePartyBox(invoice.seller),
      tradePartyBox(invoice.buyer),

      lineItemsBox(invoice.lines, invoice),
      totalValuesBox(invoice.lines, invoice)
    )
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
    class = "resilient.base", -- FIXME temporary defaults
    papersize = "a4",
    --layout = "geometry 0.5in 0.5in",
    --headers = "none",
  }

  pl.pretty.dump(content, "INVOICE-CONTENT")

  local tree = {
    SU.ast.createStructuredCommand("document", options, content),
  }
  return tree
end

return inputter
