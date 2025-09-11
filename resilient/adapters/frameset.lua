--- Lightweight frameset parser/solver.
--
-- Aimed at resolving a master frameset so as to render it graphically, etc.
--
-- The logic is mostly taken from SILE's core frame.
--
-- MIT licensed (c) Simon Cozens / The SILE Organization.
--
-- But the frames and frameParser in that implementation rely on several side effects
-- and global variables.
-- I extracted and refactored the minimal code for solving frame specifications
-- independently, so as to be able to resolve a full master layout and draw it.
--
-- @license MIT
-- @copyright (c) 2023-2025 Omikhkeia / Didier Willis
-- @module resilient.adapters.frameset

local cassowary = require("cassowary")
local lpeg = require("lpeg")
local P, C, V = lpeg.P, lpeg.C, lpeg.V

local widthdims = pl.Set { "left", "right", "width" }
local heightdims = pl.Set { "top", "bottom", "height" }
local alldims = widthdims + heightdims

--- Lightweight frame class.
--
-- Adapted from `SILE core.frame`.
--
-- Lightweight re-implementation of a frame.
--
-- @type frameAdapter

local frameAdapter = pl.class()

--- (Constructor) Create a new frameAdapter instance.
-- @tparam table spec Frame specification
-- @param frameParser Frame parser instance
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

--- Constrain a dimension of the frame.
-- @tparam string method The dimension to constrain
-- @tparam string|number|SILE.measurement dimension The dimension specification
function frameAdapter:constrain (method, dimension)
  self.constraints[method] = tostring(dimension)
end

--- Reify a constraint into the solver.
-- @tparam cassowary.SimplexSolver solver Cassowary solver instance
-- @tparam string method The dimension to reify
-- @tparam boolean stay Whether to add a "stay" constraint
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

--- Add width and height definitions to the solver.
-- @tparam cassowary.SimplexSolver solver Cassowary solver instance
function frameAdapter:addWidthHeightDefinitions (solver)
  local vars = self.variables
  local weq = cassowary.Equation(vars.width, cassowary.minus(vars.right, vars.left))
  local heq = cassowary.Equation(vars.height, cassowary.minus(vars.bottom, vars.top))
  solver:addConstraint(weq)
  solver:addConstraint(heq)
end

--- Lightweight frameset class.
--
-- It provides methodes for parsing and solving a frameset specification.
--
-- Adapted from `SILE core.frameparser`.
--
-- Lightweight re-implementation of a "master" frameset.
--
-- @type framesetAdapter

local framesetAdapter = pl.class()

--- (Constructor) Create a new framesetAdapter instance.
--
-- @tparam table frames Frameset specification
function framesetAdapter:_init (frames)
  self:initFrameParser()

  self.frames = {}
  for id, spec in pairs(frames) do
    spec.id = id
    self.frames[spec.id] = frameAdapter(spec, self.parser)
  end
end

--- Initialize the frame parser.
function framesetAdapter:initFrameParser()
  local number = SILE.parserBits.number
  local identifier = SILE.parserBits.identifier
  local measurement = SILE.parserBits.measurement / function (str)
    return SILE.types.measurement(str):tonumber()
  end
  -- Based on the frame grammar from SILE.
  -- I did not investigate the quality of the code, despite the fact that it seems weird
  -- that additive rules are taking precedence over multiplicative ones, and that a
  -- cassowary implementation would, if I am not mistaken, handle inequality constraints
  -- and not just equality ones. In other words, I have some doubts about the correctness
  -- of the whole frame thing, but I'll leave that to other people to check and clarify.
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

--- Solve the frameset.
--
-- Adapted from the constrain solver in `SILE core.frame`.
--
-- @treturn table Table of resolved frames
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
