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
require("silex")

local parent = require("classes.base")
local class = pl.class(parent)
class._name = "resilient.base"
class.styles = nil

function class:_init (options)
  parent._init(self, options)

  -- We do not use SILE's plain class, so do here the minimal compatibility
  self:loadPackage("resilient.plain")
  self:loadPackage("bidi")

  -- An make us style-aware
  self:loadPackage("resilient.styles")
  self.styles = self.packages["resilient.styles"]
  self:registerStyles()
end

function class:declareOptions () -- Also from SILE's plain class
  self:declareOption("direction", function (_, value)
    if value then
        SILE.documentState.direction = value
        SILE.settings:set("font.direction", value, true)
        for _, frame in pairs(self.defaultFrameset) do
          if not frame.direction then
              frame.direction = value
          end
        end
    end
    return SILE.documentState.direction
  end)
end

local resilientAwareVariant = {
  lists = "resilient.lists",
  verbatim = "resilient.verbatim",
}

function class:loadPackage (packname, options)
  if resilientAwareVariant[packname] then
    packname = resilientAwareVariant[packname]
    SU.warn("Loading the resilient variant of package '" .. packname .. "'"
    .. [[

This should be compatible, but there might be differences such as hooks not
being available, as the resilient version use styles instead.
Please consider using resilient-compatible packages when available!
]])
  end
  return parent.loadPackage(self, packname, options)
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

function class:declareOptions ()
  parent.declareOptions(self)

  self:declareOption("resolution", function (_, value)
    if value then
      self.resolution = SU.cast("integer", value)
    end
    return self.resolution
  end)
end

function class:registerRawHandlers ()
  parent.registerRawHandlers(self)
end

function class:registerCommands ()
  parent.registerCommands(self)
end

-- For overriding in any document subclass, as a convenient hook
-- where to register all styles.
function class:registerStyles () end

return class
