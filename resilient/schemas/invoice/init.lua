--- An invoice schema for re·sil·ient.
--
-- The invoice document is a YAML file that describes the transaction details.
--
-- The structure is inspired by the Factur-X / ZUGFeRD standard, but simplified.
--
-- @license MIT
-- @copyright (c) 2025 Omikhleia / Didier Willis
-- @module resilient.schemas.invoice

local DateSchema = require("resilient.schemas.common").DateSchema

--- A postal trade address schema.
--
-- Represents a postal address for a trade party.
--
-- @field type "object"
-- @table PostalTradeAddressSchema
local PostalTradeAddressSchema = {
  type = "object",
  properties = {
    location = {
      type = "array",
      items = { type = "string" }
    },
    ["postal-code"] = {
      type = { -- oneOf
        { type = "string" },
        { type = "number" },
      },
    },
    city = { type = "string" },
    country = { type = "string" },
  },
  required = { "country" }, -- At least country is required
}

--- A defined trade contact schema.
---
-- Represents a contact person for a trade party.
--
-- @field type "object"
-- @table DefinedTradeContactSchema
local DefinedTradeContactSchema = {
  type = "object",
  properties = {
    name = { type = "string" },
    department = { type = "string" },
    phone = { type = "string" },
    email = { type = "string" },
  }
}

--- A trade party schema.
--
-- Represents a party in the invoice (seller or buyer).
--
-- @field type "object"
-- @table TradePartySchema
local TradePartySchema = {
  type = "object",
  properties = {
    name = { type = "string" },
    logo = { type = "string" },
    uri = { type = "string" },
    ["tax-registration"] = { type = "string" },
    address = PostalTradeAddressSchema,
    contact = DefinedTradeContactSchema,
  },
  required = { "name" },
}

local SpecifiedTradeSettlementPaymentMeans = {
  type = "object",
  properties = {
    bank = {
      type = "object",
      properties = {
        iban = { type = "string" },
        bic = { type = "string" },
        name = { type = "string" },
      },
      required = { "iban" }
    },
    cheque = {
      type = "object",
      properties = {
        name = { type = "string" },
      }
    }
  }
}

--- An included supply chain trade line item schema.
--
-- Represents a line item in the invoice.
--
-- @field type "object"
-- @table IncludedSupplyChainTradeLineItemSchema
local IncludedSupplyChainTradeLineItemSchema = {
  type = "object",
  properties = {
    id = {
      type = { -- oneOf
        { type = "string" },
        { type = "number" },
      },
    },
    description = { type = "string" },
    quantity = { type = "number" },
    unit = { type = "string", default = "EA" },
    ["unit-price"] = { type = "number" },
    ["tax-rate"] = { type = "number" },
  },
  required = { "id", "description", "quantity", "unit-price", "tax-rate" },
}

--- The invoice content node schema.
--
-- @field type "object"
-- @table InvoiceContentSchema
local InvoiceContentSchema = {
  type = "object",
  properties = {
    id = {
      type = { -- oneOf
        { type = "string" },
        { type = "number" },
      },
    },
    language = {  -- Not from Factur-X, but we use it for localization
      type = "string",
      default = "en",
    },
    note = { type = "string" }, -- Not from Factur-X, but free text note for presentation
    ["issue-date"] = DateSchema,
    ["due-date"] = { type = {
        DateSchema,
        { type = "number" }, -- number of days for payment terms
      },
    },
    ["delivery-date"] = DateSchema,
    currency = { type = "string" },
    ["type-code"] = {
      type = { -- oneOf
        { type = "string" },
        { type = "number" },
      },
      default = "380", -- Standard invoice
    },
    seller = TradePartySchema,
    buyer = TradePartySchema,
    payment = SpecifiedTradeSettlementPaymentMeans,
    lines = {
      type = "array",
      items = IncludedSupplyChainTradeLineItemSchema
    }
  },
  required = { "id", "issue-date", "due-date", "currency", "seller", "buyer", "lines" },
}

--- The top-level invoice document schema.
--
-- @field type "object"
-- @table InvoiceSchema
local InvoiceSchema = {
  ["$id"] = "urn:example:omikhleia:resilient:invoice",
  type = "object",
  properties = {
    invoice = InvoiceContentSchema
  },
  required = { "invoice" },
}

return {
  PostalTradeAddressSchema = PostalTradeAddressSchema,
  DefinedTradeContactSchema = DefinedTradeContactSchema,
  TradePartySchema = TradePartySchema,
  SpecifiedTradeSettlementPaymentMeans = SpecifiedTradeSettlementPaymentMeans,
  IncludedSupplyChainTradeLineItemSchema = IncludedSupplyChainTradeLineItemSchema,
  InvoiceContentSchema = InvoiceContentSchema,
  InvoiceSchema = InvoiceSchema,
}
