--
-- Common utilities for RESILIENT
--
-- License: GPL-3.0-or-later
--
-- Copyright (C) 2023-2025 Didier Willis
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
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
