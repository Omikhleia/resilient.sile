--
-- Resilient base for style-enabled packages for SILE
--
-- It provides a base class for packages that want to use styles,
-- and a few convenience methods hide the internals.
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
local base = require("packages.base")
local package = pl.class(base)
package._name = "resilient.base"
package.styles = nil

function package:_init (options)
  base._init(self, options)

  self:loadPackage("resilient.styles")
  self.styles = self.class.packages["resilient.styles"]
  self:registerStyles()
end

function package:registerStyle (name, opts, styledef)
  return self.styles:defineStyle(name, opts, styledef, self._name)
end

function package:resolveStyle (name, discardable)
  return self.styles:resolveStyle(name, discardable)
end

function package:hasStyle (name)
  return self.styles:hasStyle(name)
end

-- For overriding in any package subclass, as a convenient hook
-- where to register all styles.
function package:registerStyles () end

return package
