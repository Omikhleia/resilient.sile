--- Common elements for schema validation in re·sil·ient.
--
-- @license MIT
-- @copyright (c) 2025 Omikhleia / Didier Willis
-- @module resilient.schemas.common

--- Date schema.
--
-- A date object is represented as a table with year, month, day,
-- hour, and min fields.
--
-- Aditional properties are allowed to accommodate with the `os.date()` Lua function
-- with the *t` format.
-- (tinyyaml converts dates to such os.date objects.)
--
-- @field type "object"
-- @table DateSchema
local DateSchema = {
  type = "object",
  -- We don't care about seconds, etc.
  additionalProperties = true,
  properties = {
    year = { type = "integer" },
    month = { type = "integer", minimum = 1, maximum = 12 },
    day = { type = "integer", minimum = 1, maximum = 31 },
    hour = { type = "integer", minimum = 0, maximum = 23 },
    min = { type = "integer", minimum = 0, maximum = 59 },
  },
  required = { "year", "month", "day" },
}

--- Primitive schema (string, number, boolean).
--
-- @field type "oneOf"
-- @table PrimitiveTypeSchema
local PrimitiveTypeSchema = {
  type = { -- oneOf
    { type = "string" },
    { type = "number" },
    { type = "boolean" },
  }
}

return {
  DateSchema = DateSchema,
  PrimitiveTypeSchema = PrimitiveTypeSchema,
}
