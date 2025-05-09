--
-- Common utilities for RESILIENT
--
-- License: MIT
-- Copyright (C) 2023-2025 Omikhleia / Didier Willis
--

--- Measure an inter-word space (which, depending on settings, might be variable
-- and thus have stretch/shrink).
-- @treturn length interwordSpace
local function interwordSpace()
  return SILE.shaper:measureSpace(SILE.font.loadDefaults({}))
end

--- Cast a kern length (e.g. in styles), also supporting the special "iwsp"
-- pseudo unit for interword space.
-- @tparam string|length kern The kern value to cast
-- @treturn length The kern value as a length
local function castKern (kern)
  if type(kern) == "string" then
    local value, rest = kern:match("^(%d*)iwsp[ ]*(.*)$")
    if value then
      if rest ~= "" then
        SU.error("Could not parse kern '" .. kern .. "'")
      end
      return (tonumber(value) or 1) * interwordSpace()
    end
  end
  return SU.cast("length", kern)
end

--- Merge two tables.
-- It turns out that pl.tablex.union() does not recurse into the table,
-- so let's do it the proper way.
-- N.B. modifies t1 (and t2 wins on "leaves" existing in both tables)
-- @tparam table t1 The first table
-- @tparam table t2 The second table
-- @treturn table The merged table
local function recursiveTableMerge(t1, t2)
  for k, v in pairs(t2) do
    if (type(v) == "table") and (type(t1[k]) == "table") then
      recursiveTableMerge(t1[k], t2[k])
    else
      t1[k] = v
    end
  end
end

return {
  castKern = castKern,
  interwordSpace = interwordSpace,
  recursiveTableMerge = recursiveTableMerge,
}
