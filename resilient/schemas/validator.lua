--- Simple and naive schema validator for re·sil·ient.
--
-- @license MIT
-- @copyright (c) 2023-2025 Omikhleia / Didier Willis
-- @module resilient.schemas.validator

--- Naive recursive schema validation.
--
-- The validator takes a table (for instance, parsed from YAML)
-- and a schema definition.
--
-- The schema defintion is a table of rules, loosely inspired from JSON Schema
-- and OpenAPI specifications.
--
-- @tparam table obj Object to validate
-- @tparam table schema Schema to validate against
-- @tparam[opt] table context Parent schema context for error messages
-- @treturn boolean Whether the object is valid as per the schema
-- @treturn string|nil Error message if invalid
local function validate (obj, schema, context)
  context = context or "doc"
  if schema["$id"] then
    SU.debug("resilient.schemas", "Validating", context, "against schema", schema["$id"])
  end

  if type(schema.type) == "table" then -- oneOf type
    local oneOfMatched = false
    SU.debug("resilient.schemas", "Validating", context, "as oneOf types")
    for _, v in ipairs(schema.type) do
      oneOfMatched = validate(obj, v, context)
      if oneOfMatched then
        break
      end
    end
    if not oneOfMatched then
      local ts = pl.tablex.map(function (t)
        return t.type == "array" and "array of " .. t.items.type or t.type
      end, schema.type)
      return false, context .. " must match one of " .. table.concat(ts, ", ")
    end
    return true
  end

  if schema.type == "array" then
    SU.debug("resilient.schemas", "Validating", context, "as array")
    -- array type
    if type(obj) ~= "table" then
      return false, context .. " must be an array"
    end
    for key, val in pairs(obj) do
      if type(key) ~= "number" then
        return false, context .. "." .. key .. " is invalid ("
          .. context .. " must be an array)"
      end
      local ok, err = validate(val, schema.items, context .. "." .. key)
      if not ok then
        return false, err
      end
    end
    return true
  end

  if schema.type == "object" then
    SU.debug("resilient.schemas", "Validating", context, "as object")
    if type(obj) ~= "table" then
      return false, context .. " must be an object"
    end
    -- Apply default values
    for key, prop in pairs(schema.properties) do
      if obj[key] == nil and prop.default ~= nil then
        obj[key] = prop.default
        SU.debug("resilient.schemas", "Applying default value to", context .. "." .. key)
      end
    end
    -- Validate properties
    for key, val in pairs(obj) do
      local field = context .. "." .. key or key
      if not schema.properties[key] then
        if not schema.additionalProperties then
          return false, field .. " is not expected in " .. context
        elseif type(schema.additionalProperties) == "table" then
          SU.debug("resilient.schemas", "Validating", field, "with additional properties schema")
          local ok, err = validate(val, schema.additionalProperties, field)
          if not ok then
            return false, err
          end
        end
      else
        local ok, err = validate(val, schema.properties[key], field)
        if not ok then
          return false, err
        end
      end
    end
    -- Check required fields
    if schema.required then
      for _, reqKey in ipairs(schema.required) do
        local field = context .. "." .. reqKey
        SU.debug("resilient.schemas", "Checking required", field, "is present")
        if obj[reqKey] == nil then
          return false, field .. " is required"
        end
      end
    end
    return true
  end

  if schema.type == "integer" then
    SU.debug("resilient.schemas", "Validating", context, "as integer")
    if type(obj) ~= "number" or obj % 1 ~= 0 then
      return false, context .. " must be an integer"
    end
    if schema.minimum and obj < schema.minimum then
      return false, context .. " must be >= " .. schema.minimum
    end
    if schema.maximum and obj > schema.maximum then
      return false, context .. " must be <= " .. schema.maximum
    end
    return true
  end

  if type(obj) == schema.type then -- primitive type (string, number, boolean)
    SU.debug("resilient.schemas", "Validating", context, "as", schema.type)
    return true
  end

  return false, context .. " must be of type " .. (schema.type or "unknown")
end


--- @export
return {
  validate = validate,
}
