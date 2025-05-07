--
-- Base resilient class for SILE.
-- Following the resilient styling paradigm.
--
-- It provides a base class for document classes that want to use styles,
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
local parent = require("classes.resilient.override")
local class = pl.class(parent)
class._name = "resilient.base"
class.styles = nil

function class:_init (options)
  parent._init(self, options)

  self:loadPackage("resilient.styles")
  self.styles = self.packages["resilient.styles"]
  self:registerStyles()
end

-- Some core or 3rd-party packages may load a non-style-aware variant of
-- another package, and this would cause issues with the commands being
-- redefined to the non-style-aware variant.
-- E.g. in SILE 0.15.12, the "url" package loads the "verbatim" package
-- (despite not using it, and this was later fixed).
-- Let's assume we are compatible with those packages (though we cannot
-- guarantee it), and always silently load the resilient variant instead.
local styleAwareVariant = {
  lists = "resilient.lists",
  verbatim = "resilient.verbatim",
  tableofcontents = "resilient.tableofcontents",
  footnotes = "resilient.footnotes",
}

function class:loadPackage (packname, options, reload)
  if styleAwareVariant[packname] then
    SU.debug("resilient", "Loading the resilient variant of package", packname, "=", styleAwareVariant[packname],
    [[

This should be compatible, but there might be differences such as hooks not
being available, as the resilient version use styles instead.
Please consider using resilient-compatible style-aware packages when available!
]])
    packname = styleAwareVariant[packname]
  end
  return parent.loadPackage(self, packname, options, reload)
end

function class:registerStyle (name, opts, styledef)
  return self.styles:defineStyle(name, opts, styledef, self._name)
end

function class:resolveStyle (name, discardable)
  return self.styles:resolveStyle(name, discardable)
end

function class:hasStyle (name)
  return self.styles:hasStyle(name)
end

-- For overriding in any document subclass, as a convenient hook
-- where to register all styles.
function class:registerStyles () end

return class
