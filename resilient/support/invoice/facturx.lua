--- Factur-X/ZUGFeRD XML generation for re·sil·ient invoices.
--
-- A re·sil·ient invoice is a YAML document, or a Lua table representation of it,
-- This module generates the corresponding Factur-X/ZUGFeRD XML representation.
--
-- The validity of the input table is not checked here, it is assumed to conform to
-- the appropriate schema defined in `resilient/schemas/invoice/init.lua`.
--
-- References:
--
--  - XSD Schemas: <https://www.einlassband.eu/libs/horstoeko/zugferd/schema/>
--  - A validator: <https://validator.invoice-portal.de/index.php>
--  - Another validator: <https://xrechnung.avvaneo.com/>
--
-- Factur-X 1.07.2 ZUGFeRD 2.3.2 EN16931 compliance is targeted.
--
-- @license MIT
-- @copyright (c) 2025 Omikhleia / Didier Willis
-- @module resilient.support.invoice.facturx

local Err = SU and SU.error or error -- Nothing really specific to SILE here, so let's be generic.

-- Helper functions
-- FIXME repeated from resilient/support/xmp.lua

local function xmlEscape (s)
  s = tostring(s)
  s = s:gsub("&", "&amp;")
  s = s:gsub("<", "&lt;")
  s = s:gsub(">", "&gt;")
  s = s:gsub("'", "&apos;")
  s = s:gsub('"', "&quot;")
  return s
end

local function xmlTagHelper(tag, attributes, value)
  if not value then
    return "" -- Assumption: omit empty tags.
  end
  if type(value) == "table" then
    if value.year then
      -- Assume it's a date that was parsed with os.date(().
      -- (This is what the tinyyaml module we use for parsing does.)
      value = os.date("%Y%m%d", os.time(value)) -- Format "102" in Factur-X
    else
      Err("Factur-X XML generation: unsupported table value for tag " .. tag)
    end
  end
  local attributesStrs = {}
  for k, v in pairs(attributes) do
    attributesStrs[#attributesStrs+1] = k .. '="' .. v .. '"'
  end
  local sattributes = ""
  if #attributesStrs > 0 then
    sattributes = " " .. table.concat(attributesStrs, " ")
  end
  return "<" .. tag .. sattributes .. ">" .. xmlEscape(value) .. "</" .. tag .. ">"
end

-- Factur-X/Zugferd construction functions

local LINETAGS = { "ram:LineOne", "ram:LineTwo", "ram:LineThree" }
local function LocationLines (it)
  local lines = {}
  if it then
    -- Factur-X expects up to 3 location lines
    for i = 1, math.min(#it, 3) do
      lines[#lines+1] = xmlTagHelper(LINETAGS[i], {}, it[i])
    end
    return table.concat(lines)
  end
end

local function PostalTradeAddress (it)
  if not it then -- omit if no address
    return ""
  end
  return table.concat({
    '<ram:PostalTradeAddress>',
      xmlTagHelper("ram:PostcodeCode", {}, tostring(it["postal-code"])),
      LocationLines(it.location),
      xmlTagHelper("ram:CityName", {}, it.city),
      xmlTagHelper("ram:CountryID", {}, it.country), -- ISO 3166-1 code, mandatory
      -- CountrySubDivisionName
    '</ram:PostalTradeAddress>'
  })
end

local function ExchangedDocument (it)
  return table.concat({
    '<rsm:ExchangedDocument>',
      xmlTagHelper("ram:ID", {}, it.id),
      -- Name
      xmlTagHelper("ram:TypeCode", {}, tostring(it["type-code"] or 380)), -- default to 380 (invoice)
      '<ram:IssueDateTime>',
        xmlTagHelper("udt:DateTimeString", { format = "102" }, it["issue-date"]),
      '</ram:IssueDateTime>',
      -- CopyIndicator
      -- xmlTagHelper("ram:LanguageID", {}, it.language), -- Warning [CII-SR-019] - LanguageID should not be present
      --                                                  -- So maybe we should omit it.
      --                                                  -- See SpecifiedTradePaymentTerms/Description below.
      -- IncludedNote
      -- EffectiveSpecifiedPeriod
    '</rsm:ExchangedDocument>'
  })
end

local function TradeContact (it)
  if not it then
    return "" -- omit if no contact
  end
  return table.concat({
    '<ram:DefinedTradeContact>',
      xmlTagHelper("ram:PersonName", {}, it.name),
      xmlTagHelper("ram:DepartmentName", {}, it.department),
      -- TypeCode
      it.phone
        and table.concat({
          '<ram:TelephoneUniversalCommunication>',
            xmlTagHelper("ram:CompleteNumber", {}, it.phone:gsub("%D", "")), -- Remove non digit characters from phone number
          '</ram:TelephoneUniversalCommunication>'
        }) or "",
      -- FaxUniversalCommunication
      it.email
        and table.concat({
          '<ram:EmailURIUniversalCommunication>',
            xmlTagHelper("ram:URIID", {}, it.email),
          '</ram:EmailURIUniversalCommunication>'
        }) or "",
    '</ram:DefinedTradeContact>'
  })
end

local function TradeParty (it)
  return table.concat({
    -- ID
    -- GlobalID
    xmlTagHelper("ram:Name", {}, it.name),
    -- RoleCode
    -- Description
    -- SpecifiedLegalOrganization
    TradeContact(it.contact),
    PostalTradeAddress(it.address),
    -- [BR-CL-25] - Endpoint identifier scheme identifier MUST belong to the CEF EAS code list
    -- Soe there does not seem to be a way for including the mere website URI of the party.
    -- it.uri and table.concat({
    --   '<ram:URIUniversalCommunication>',
    --     xmlTagHelper("ram:URIID", { schemeID = "URI" }, it.uri),
    --   '</ram:URIUniversalCommunication>'
    -- }) or "",
    it["tax-registration"] and table.concat({
      '<ram:SpecifiedTaxRegistration>',
        xmlTagHelper("ram:ID", { schemeID = "VA" }, it["tax-registration"]),
      '</ram:SpecifiedTaxRegistration>'
    }) or "",
  })
end

local function IncludedSupplyChainTradeLineItem (it)
  return table.concat({
    '<ram:IncludedSupplyChainTradeLineItem>',
      '<ram:AssociatedDocumentLineDocument>',
        xmlTagHelper("ram:LineID", {}, tostring(it.id)),
        -- ParentLineID
        -- LineStatusCode
        -- LineStatusReasonCode
        -- IncludedNote
      '</ram:AssociatedDocumentLineDocument>',
      '<ram:SpecifiedTradeProduct>',
        -- ID
        -- GlobalID
        -- SellerAssignedID
        -- BuyerAssignedID
        -- IndustryAssignedID
        -- ModelID
        xmlTagHelper("ram:Name", {}, it.description), -- Name is mandatory, our YAML has it but as "description"...
        -- Description (optional)
        -- BatchID
        -- BrandName
        -- ModelName
        -- ApplicableProductCharacteristic
        -- DesignatedProductClassification
        -- IndividualTradeProductInstance
        -- OriginTradeCountry
        -- IncludedReferencedProduct
      '</ram:SpecifiedTradeProduct>',
      '<ram:SpecifiedLineTradeAgreement>',
        -- SellerOrderReferencedDocument
        -- BuyerOrderReferencedDocument
        -- QuotationReferencedDocument
        -- ContractReferencedDocument
        -- AdditionalReferencedDocument
        -- GrossPriceProductTradePrice
        '<ram:NetPriceProductTradePrice>',
          xmlTagHelper("ram:ChargeAmount", {}, string.format("%.2f", it["unit-price"])),
          -- BasisQuantity
          -- AppliedTradeAllowanceCharge
          -- IncludedTradeTax
        '</ram:NetPriceProductTradePrice>',
        -- UltimateCustomerOrderReferencedDocument
      '</ram:SpecifiedLineTradeAgreement>',
      '<ram:SpecifiedLineTradeDelivery>',
        xmlTagHelper("ram:BilledQuantity", { unitCode = it.unit }, tostring(it.quantity)),
        -- ChargeFreeQuantity
        -- PackageQuantity
        -- ShipToTradeParty
        -- UltimateShipToTradeParty
        -- ActualDeliverySupplyChainEvent
        -- DespatchAdviceReferencedDocument
        -- ReceivingAdviceReferencedDocument
        -- DeliveryNoteReferencedDocument
      '</ram:SpecifiedLineTradeDelivery>',
      '<ram:SpecifiedLineTradeSettlement>',
        '<ram:ApplicableTradeTax>',
          -- CalculatedAmount
          xmlTagHelper("ram:TypeCode", {}, "VAT"),
          -- ExemptionReason
          -- BasisAmount
          -- LineTotalBasisAmount
          -- AllowanceChargeBasisAmount
          xmlTagHelper("ram:CategoryCode", {}, it['tax-rate'] == 0 and "Z" or "S"), -- Zero or Standard
          -- ExemptionReasonCode
          -- TaxPointDate
          -- DueDateTypeCode
          xmlTagHelper("ram:RateApplicablePercent", {}, string.format("%.2f", it["tax-rate"] * 100)),
        '</ram:ApplicableTradeTax>',
        -- BillingSpecifiedPeriod
        -- SpecifiedTradeAllowanceCharge
        '<ram:SpecifiedTradeSettlementLineMonetarySummation>',
          xmlTagHelper("ram:LineTotalAmount", {}, string.format("%.2f", it["quantity"] * it["unit-price"])),
          -- ChargeTotalAmount
          -- AllowanceTotalAmount
          -- TaxTotalAmount = it["quantity"] * it["unit-price"] * it["tax-rate"] -- But Factur-X considers it should not be here at line level
          -- GrandTotalAmount" = it["quantity"] * it["unit-price"] * (1 + it["tax-rate"]), -- But Factur-X considers it should not be here at line level
          -- TotalAllowanceChargeAmount
        '</ram:SpecifiedTradeSettlementLineMonetarySummation>',
        -- InvoiceReferencedDocument
        -- AdditionalReferencedDocument
        -- ReceivableSpecifiedTradeAccountingAccount
      '</ram:SpecifiedLineTradeSettlement>',
    '</ram:IncludedSupplyChainTradeLineItem>'
  })
end

local function IncludedSupplyChainTradeLineItems (it)
  local lineItems = {}
  for _, item in ipairs(it) do
    lineItems[#lineItems+1] = IncludedSupplyChainTradeLineItem(item)
  end
  return table.concat(lineItems)
end

local function ApplicableHeaderTradeDelivery (it)
  return table.concat({
    '<ram:ApplicableHeaderTradeDelivery>',
      -- RelatedSupplyChainConsignment
      -- ShipToTradeParty
      -- UltimateShipToTradeParty
      -- ShipFromTradeParty
      it["delivery-date"] and table.concat({
        '<ram:ActualDeliverySupplyChainEvent>',
          '<ram:OccurrenceDateTime>',
            xmlTagHelper("udt:DateTimeString", { format = "102" }, it["delivery-date"]),
          '</ram:OccurrenceDateTime>',
        '</ram:ActualDeliverySupplyChainEvent>'
      }) or "",
      -- DespatchAdviceReferencedDocument
      -- ReceivingAdviceReferencedDocument
      -- DeliveryNoteReferencedDocument
    '</ram:ApplicableHeaderTradeDelivery>'
  })
end

local function computeLineTotals (it)
  local netTotal = 0
  local taxTotal = 0
  for _, line in ipairs(it.lines) do
    local lineNet = line["quantity"] * line["unit-price"]
    local lineTax = lineNet * line["tax-rate"]
    netTotal = netTotal + lineNet
    taxTotal = taxTotal + lineTax
  end
  return netTotal, taxTotal
end

local function SpecifiedTradeSettlementHeaderMonetarySummation (it)
  local netTotal, taxTotal = computeLineTotals(it)
  local net = string.format("%.2f", netTotal)
  local tax = string.format("%.2f", taxTotal)
  local gross = string.format("%.2f", netTotal + taxTotal)
  return table.concat({
    '<ram:SpecifiedTradeSettlementHeaderMonetarySummation>',
      xmlTagHelper("ram:LineTotalAmount", {}, net),
      -- ChargeTotalAmount
      -- AllowanceTotalAmount
      xmlTagHelper("ram:TaxBasisTotalAmount", {}, net), -- same as LineTotalAmount if no Allowance or Charge
      xmlTagHelper("ram:TaxTotalAmount", { currencyID = it.currency }, tax),
      -- RoundingAmount
      xmlTagHelper("ram:GrandTotalAmount", {}, gross),
      -- TotalPrepaidAmount
      xmlTagHelper("ram:DuePayableAmount", {}, gross),-- same as GrandTotalAmount if no TotalPrepaidAmount
    '</ram:SpecifiedTradeSettlementHeaderMonetarySummation>'
  })
end

-- This function computes the tax summary per rate.
--  - Groups lines by tax rate
--  - Sums the net amounts for each rate -> BasisAmount
--  - Sums the tax amounts for each rate -> CalculatedAmount
local function computeTaxSummary (it)
  local taxSummary = {}
  for _, line in ipairs(it.lines) do
    local rate = line["tax-rate"]
    if not taxSummary[rate] then
      taxSummary[rate] = { basis = 0, calculated = 0 }
    end
    local lineNet = line["quantity"] * line["unit-price"]
    local lineTax = lineNet * rate
    taxSummary[rate].basis = taxSummary[rate].basis + lineNet
    taxSummary[rate].calculated = taxSummary[rate].calculated + lineTax
  end
  return taxSummary
end

local function ApplicableTradeTaxEntries (it)
  local taxSummary = computeTaxSummary(it)
  local entries = {}
  -- Create one ApplicableTradeTax entry per tax rate
  -- N.B. I had add currencyID on CalculatedAmount and BasisAmount, but validators
  -- reported [CII-DT-031] - currencyID should not be present.
  -- Maybe because we have it on InvoiceCurrencyCode globally.
  for rate, amounts in pairs(taxSummary) do
    entries[#entries+1] = table.concat({
      '<ram:ApplicableTradeTax>',
        xmlTagHelper("ram:CalculatedAmount", {}, string.format("%.2f", amounts.calculated)),
        xmlTagHelper("ram:TypeCode", {}, "VAT"),
        -- ExemptionReason
        xmlTagHelper("ram:BasisAmount", {}, string.format("%.2f", amounts.basis)),
        xmlTagHelper("ram:CategoryCode", {}, rate == 0 and "Z" or "S"),
        -- ExemptionReasonCode
        -- DueDateTypeCode
        xmlTagHelper("ram:RateApplicablePercent", {}, string.format("%.2f", rate * 100)),
      '</ram:ApplicableTradeTax>'
    })
  end
  return table.concat(entries)
end

local function SpecifiedTradeSettlementPaymentMeans (it)
  local entries = {}
  if it.payment then
    if it.payment.bank and it.payment.bank.iban then
      entries[#entries+1] = table.concat({
        '<ram:SpecifiedTradeSettlementPaymentMeans>',
          '<ram:TypeCode>42</ram:TypeCode>', -- 42 = Bank transfer
          '<ram:Information>Bank transfer</ram:Information>',
          '<ram:PayeePartyCreditorFinancialAccount>',
            xmlTagHelper("ram:IBANID", {}, it.payment.bank.iban:gsub("%s+", "")), -- Remove spaces from IBAN
            it.payment.bank.name
              and xmlTagHelper("ram:AccountName", {}, it.payment.bank.name)
              or "",
          '</ram:PayeePartyCreditorFinancialAccount>',
          it.payment.bank.bic
            and table.concat({
              '<ram:PayeeSpecifiedCreditorFinancialInstitution>',
                xmlTagHelper("ram:BICID", {}, it.payment.bank.bic),
              '</ram:PayeeSpecifiedCreditorFinancialInstitution>'
            }) or "",
        '</ram:SpecifiedTradeSettlementPaymentMeans>'
      })
    end
    if it.payment.cheque then
      local account = it.payment.cheque.name or it.seller.name
      entries[#entries+1] = table.concat({
        '<ram:SpecifiedTradeSettlementPaymentMeans>',
          '<ram:TypeCode>20</ram:TypeCode>', -- 20 = Cheque
          xmlTagHelper('ram:Information', {}, "Cheque payable to " .. account),
          it.payment.cheque.name
            and table.concat({
              '<ram:PayeePartyCreditorFinancialAccount>',
                xmlTagHelper("ram:AccountName", {}, account),
              '</ram:PayeePartyCreditorFinancialAccount>'
            }) or "",
        '</ram:SpecifiedTradeSettlementPaymentMeans>'
      })
    end
  end
  return table.concat(entries)
end

local function ApplicableHeaderTradeSettlement (it)
  local paymentMeans = SpecifiedTradeSettlementPaymentMeans(it)
  return table.concat({
    '<ram:ApplicableHeaderTradeSettlement>',
      -- CreditorReferenceID
      -- PaymentReference
      -- TaxCurrencyCode
      xmlTagHelper("ram:InvoiceCurrencyCode", {}, it.currency), -- mandatory
      -- TaxApplicableTradeCurrencyExchange
      paymentMeans,
      ApplicableTradeTaxEntries(it), -- mandatory
      -- BillingSpecifiedPeriod
      -- SpecifiedTradeAllowanceCharge
      -- SpecifiedLogisticsServiceCharge
      '<ram:SpecifiedTradePaymentTerms>', -- mandatory for most Factur-X validators
        type(it["due-date"]) == "number"
          -- "Payment within N days": We don't localize the informal text here.
          -- See above, validators warn if we put LanguageID in ExchangedDocument.
          -- Better not make any assumption about the language to use for now...
          and xmlTagHelper("ram:Description", {}, "Payment within " .. tostring(it["due-date"]) .. " days")
          -- Explicit due date
          or table.concat({
          '<ram:DueDateDateTime>',
            xmlTagHelper("udt:DateTimeString", { format = "102" }, it["due-date"]),
          '</ram:DueDateDateTime>'
        }),
        -- DirectDebitMandateID
      '</ram:SpecifiedTradePaymentTerms>',
      SpecifiedTradeSettlementHeaderMonetarySummation(it), -- mandatory
      -- InvoiceReferencedDocument
      -- ReceivableSpecifiedTradeAccountingAccount
      -- SpecifiedAdvancePayment
    '</ram:ApplicableHeaderTradeSettlement>'
  })
end

--- Transform a re·sil·ient invoice table into its Factur-X/Zugferd XML representation.
--
-- @tparam table it The re·sil·ient invoice table.
-- @treturn string The Factur-X/Zugferd XML representation of the invoice.
local function toFacturX (it)
  return table.concat(
   {
    '<?xml version="1.0" encoding="UTF-8"?>',
    table.concat({
      '<rsm:CrossIndustryInvoice',
        'xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100"',
        'xmlns:a="urn:un:unece:uncefact:data:standard:QualifiedDataType:100"',
        'xmlns:qdt="urn:un:unece:uncefact:data:standard:QualifiedDataType:10"',
        'xmlns:ram="urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100"',
        'xmlns:udt="urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100"',
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
    }, " "),
      '<!-- Created with the SILE typesetting system and the re·sil·ient collection of modules -->',
      '<rsm:ExchangedDocumentContext>',
        '<ram:GuidelineSpecifiedDocumentContextParameter>',
          '<ram:ID>urn:cen.eu:en16931:2017</ram:ID>',
        '</ram:GuidelineSpecifiedDocumentContextParameter>',
      '</rsm:ExchangedDocumentContext>',
      ExchangedDocument(it),
      '<rsm:SupplyChainTradeTransaction>',
        IncludedSupplyChainTradeLineItems(it.lines),
        '<ram:ApplicableHeaderTradeAgreement>',
          '<ram:SellerTradeParty>',
            TradeParty(it.seller),
          '</ram:SellerTradeParty>',
          '<ram:BuyerTradeParty>',
            TradeParty(it.buyer),
          '</ram:BuyerTradeParty>',
        '</ram:ApplicableHeaderTradeAgreement>',
        ApplicableHeaderTradeDelivery(it),
        ApplicableHeaderTradeSettlement(it),
      '</rsm:SupplyChainTradeTransaction>',
    '</rsm:CrossIndustryInvoice>\n'
  })
end

--- @export
return {
  toFacturX = toFacturX
}
