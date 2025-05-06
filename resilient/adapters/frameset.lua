--
-- Lightweight frameset parser/solver.
-- Aimed at resolving a master frameset so as to render it graphically, etc.
--
-- Logic mostly stolen from SILE's core, but the frames and frameParser there
-- rely on several side effects and global variables...
-- I extracted and refactored the minimal code for solving frame specifications
-- independently, so as to be able to resolve a full master layout and draw it.
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
local cassowary = require("cassowary")
local lpeg = require("lpeg")
local P, C, V = lpeg.P, lpeg.C, lpeg.V

-- Adapted from SILE core.frame:
-- Lightweight reimplementation of a frame.

local widthdims = pl.Set { "left", "right", "width" }
local heightdims = pl.Set { "top", "bottom", "height" }
local alldims = widthdims + heightdims

local frameAdapter = pl.class()

function frameAdapter:_init (spec, frameParser)
  self.frameParser = frameParser
  self.constraints = {}
  self.variables = {}
  self.id = spec.id
  for k, v in pairs(spec) do
    if not alldims[k] then self[k] = v end
  end

  for method in pairs(alldims) do
    self.variables[method] = cassowary.Variable({ name = spec.id .. "_" .. method })
    self[method] = function (instance_self)
      return SILE.types.measurement(instance_self.variables[method].value)
    end
  end
  -- Add definitions of width and height
  for method in pairs(alldims) do
    if spec[method] then
      self:constrain(method, spec[method])
    end
  end
end

function frameAdapter:constrain (method, dimension)
  self.constraints[method] = tostring(dimension)
end

function frameAdapter:reifyConstraint (solver, method, stay)
  local constraint = self.constraints[method]
  if not constraint then return end
  constraint = SU.type(constraint) == "measurement"
    and constraint:tonumber()
    or self.frameParser:match(constraint)
  SU.debug("resilient.adapters.frameset", "Adding constraint", self.id, function ()
    return "(" .. method .. ") = " .. tostring(constraint)
  end)
  local eq = cassowary.Equation(self.variables[method], constraint)
  solver:addConstraint(eq)
  if stay then solver:addStay(eq) end
end

function frameAdapter:addWidthHeightDefinitions (solver)
  local vars = self.variables
  local weq = cassowary.Equation(vars.width, cassowary.minus(vars.right, vars.left))
  local heq = cassowary.Equation(vars.height, cassowary.minus(vars.bottom, vars.top))
  solver:addConstraint(weq)
  solver:addConstraint(heq)
end

-- Adapted from SILE core.frameparser
-- Lightweight implementation of a master frameset.

local framesetAdapter = pl.class()

function framesetAdapter:_init (frames)
  self:initFrameParser()

  self.frames = {}
  for id, spec in pairs(frames) do
    spec.id = id
    self.frames[spec.id] = frameAdapter(spec, self.parser)
  end
end

function framesetAdapter:initFrameParser()
  local number = SILE.parserBits.number
  local identifier = SILE.parserBits.identifier
  local measurement = SILE.parserBits.measurement / function (str)
    return SILE.types.measurement(str):tonumber()
  end
  local ws = SILE.parserBits.ws
  local dims = P"top" + P"left" + P"bottom" + P"right" + P"width" + P"height"
  local relation = C(dims) * ws * P"(" * ws * C(identifier) * ws * P")" / function (dim, id)
    return self.frames[id].variables[dim]
  end
  local primary = relation + measurement + number
  self.parser = P{
    "additive",
    additive = V"plus" + V"minus" + V"multiplicative",
    multiplicative = V"times" + V"divide" + V"primary",
    primary = (ws * primary * ws) + V"braced",
    plus = ws * V"multiplicative" * ws * P"+" * ws * V"additive" * ws / cassowary.plus,
    minus = ws * V"multiplicative" * ws * P"-" * ws * V"additive" * ws / cassowary.minus,
    times = ws * V"primary" * ws * P"*" * ws * V"multiplicative" * ws / cassowary.times,
    divide = ws * V"primary" * ws * P"/" * ws * V"multiplicative" * ws / cassowary.divide,
    braced = ws * P"(" * ws * V"additive" * ws * P")" * ws
  }
end

-- Adapted from SILE core.frame
-- Constraint solver.

function framesetAdapter:solve ()
  SU.debug("resilient.adapters.frameset", "Solving...")
  local solver = cassowary.SimplexSolver()
  if self.frames.page then
    for method, _ in pairs(self.frames.page.constraints) do
      self.frames.page:reifyConstraint(solver, method, true)
    end
    self.frames.page:addWidthHeightDefinitions(solver)
  end
  for id, frame in pairs(self.frames) do
    if not (id == "page") then
      for method, _ in pairs(frame.constraints) do
        frame:reifyConstraint(solver, method)
      end
      frame:addWidthHeightDefinitions(solver)
    end
  end
  solver:solve()
  return self.frames
end

return framesetAdapter
