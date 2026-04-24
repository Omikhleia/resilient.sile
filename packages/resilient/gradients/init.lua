--- Gradients package for re·sil·ient.
--
-- This package allows using gradients in PDF documents generated with the `libtexpdf` outputter.
-- in PDF documents generated with the `libtexpdf` outputter.
--
-- @license MIT
-- @copyright (c) 2026 Omikhkeia / Didier Willis
-- @module packages.resilient.gradients

--- The "resilient.gradients" package.
--
-- Extends `packages.base`.
--
-- @type packages.resilient.gradients

local base = require("packages.base")
local package = pl.class(base)
package._name = "resilient.gradients"

local pdf -- Loaded later only if needed

-- HACK
-- Adjust coordinates to take into account possible sheet size.
-- Copied from the internals (locals) of the libtexpdf outputter.
local deltaX
local deltaY
local function trueXCoord (x)
   if not deltaX then
      local sheetSize = SILE.documentState.sheetSize or SILE.documentState.paperSize
      deltaX = (sheetSize[1] - SILE.documentState.paperSize[1]) / 2
   end
   return x + deltaX
end
local function trueYCoord (y)
   if not deltaY then
      local sheetSize = SILE.documentState.sheetSize or SILE.documentState.paperSize
      deltaY = (sheetSize[2] - SILE.documentState.paperSize[2]) / 2
   end
   return y + deltaY
end

--- (Constructor) Initialize the package.
--
-- @tparam table options Package options (none currently defined)
function package:_init (options)
  base._init(self, options)

  self._objectsToRelease = {} -- List of PDF objects to release at end

  if SILE.outputter._name ~= "libtexpdf" then
    SU.warn("The resilient.forms package only does something with the libtexpdf backend.")
    self._hasGradientsSupport = false
  else
    self._hasGradientsSupport = true
    pdf = require("justenoughlibtexpdf")
  end
  local this = self
  SILE.outputter:registerHook("prefinish", function ()
    -- Use a closure to access 'this', check support and release PDF objects.
    if this._hasGradientsSupport then
      this:_releasePdfObjects()
    end
  end)
end

--- (Private) Release PDF objects that were kept until the end.
--
-- Some objects (appearances, parent field dictionaries) need to be
-- released after the PDF is finished:
-- They are only referenced indirectly in other objects as we build
-- them one by one.
--
function package:_releasePdfObjects ()
  SU.debug("resilient.gradients", "Releasing", #self._objectsToRelease, "PDF objects (gradients)")
  for _, obj in ipairs(self._objectsToRelease) do
    pdf.release(obj)
  end

end

--- (Private) Insert pattern dictionary in the current page
--
-- @tparam PdfDict patternDict Pattern dictionary to insert
-- @tparam Gradient gradient Gradient definition (with a name)
function package:_InsertInPage (patternDict, gradient)
  local page = pdf.get_dictionary("@THISPAGE")
  local resources = pdf.lookup_dictionary(page, "Resources")
  if not resources then
    SU.debug("resilient.gradients", "Creating /Resources dictionary on current page for pattern insertion")
    resources = pdf.parse("<< >>")
    pdf.add_dict(page, pdf.parse("/Resources"), resources)
  end
  local patterns = pdf.lookup_dictionary(resources, "Pattern")
  if not patterns then
    SU.debug("resilient.gradients", "Creating /Pattern dictionary in /Resources on current page for pattern insertion")
    patterns = pdf.parse("<< >>")
    pdf.add_dict(resources, pdf.parse("/Pattern"), patterns)
  end

  -- FIXME: Does not work, /Resources are reset by libtexpdf at the end of the page,
  -- so we need add_resource from PR https://github.com/sile-typesetter/sile/pull/2308
  local patternName = gradient.name
  pdf.add_dict(patterns, pdf.parse("/" .. patternName), pdf.reference(patternDict))
  pdf.release(patternDict) -- Release the pattern dictionary, no longer needed
  SU.debug("resilient.gradients", "Inserting pattern dictionary for gradient", gradient.name)
end

--- (Private) Build the shading function for a gradient.
--
-- The Gradient definition is expected to have a "stops" field, which is an array of `{r, g, b}` color stops
-- with values between 0 and 1, and at least two stops.
--
-- @tparam Gradient gradient Gradient definition
function package:_buildShadingFunction (gradient)
  local n = #gradient.stops - 1
  if n < 1 then
    SU.error("Gradient definition must have at least two color stops.")
  end

  local functionRefs = pdf.parse("[]")

  -- 1. Define interpolation functions
  -- For each adjacent pair of color stops (c1, c2), create an interpolation function.
  -- <<
  --   /FunctionType 2   % Type 2 is an exponential interpolation function, linear if N=1
  --   /Domain [0 1]     % Input range for the interpolation (0 to 1)
  --   /N 1              % Linear interpolation
  --   /C0 [R1 G1 B1]    % Starting color
  --   /C1 [R2 G2 B2]    % Ending color
  -- >>
  for i = 1, n do
    local c0 = gradient.stops[i]
    local c1 = gradient.stops[i + 1]
      local interpFunctionSpec = string.format([[<<
        /FunctionType 2
        /Domain [0 1]
        /N 1
        /C0 [%f %f %f]
        /C1 [%f %f %f]
      >>]],
        c0.r or 0, c0.g or 0, c0.b or 0,
        c1.r or 0, c1.g or 0, c1.b or 0
    )
    local interpFunction = pdf.parse(interpFunctionSpec)
    local interpFunctionRef = pdf.reference(interpFunction)
    pdf.release(interpFunction)
    pdf.push_array(functionRefs, interpFunctionRef)
  end

  -- Split points
  local bounds = {}
  for i = 1, n - 1 do
    bounds[i] = i / n
  end

  -- 2. Define the shading function.
  -- <<
  --   /FunctionType 3        % Type 3 = stitching function (combines multiple functions)
  --   /Domain[0 1]           % Input range for the entire gradient (0 to 1)
  --   /Bounds[B1 ... Bn]     % Split points not including the first (0) and last (1)
  --   /Encode[0 1 ... 0 1]   % Encoding for each function, 0 1 for linear interpolation
  --   /Functions [R1 ... Rn] % Array of interpolation function references
  -- >>
  local shadingFunctionSpec = string.format([[<<
    /FunctionType 3
    /Domain [0 1]
    /Bounds [%s]
    /Encode [%s]
  >>]],
    table.concat(bounds, " "),
    string.rep("0 1 ", n)
  )
  local shadingFunction = pdf.parse(shadingFunctionSpec)
  pdf.add_dict(shadingFunction, pdf.parse("/Functions"), functionRefs)

  table.insert(self._objectsToRelease, shadingFunction)
  return shadingFunction
end

-- @tparam Gradient gradient Gradient definition
-- @tparam number x0 Start X coordinate
-- @tparam number y0 Start Y coordinate
-- @tparam number x1 End X coordinate
-- @tparam number y1 End Y coordinate
function package:_createG (gradient, x0, y0, x1, y1)
  local shadingFunction = self:_buildShadingFunction(gradient)

  -- 1. Define the shading dictionary.
  -- <<
  --   /ShadingType 2          % Type 2 = axial shading (linear gradient)
  --   /Extend[true true]      % Whether to extend the shading past the start and ending points.
  --   /ColorSpace /DeviceRGB  % Color space for the gradient
  --   /Coords [x0 y0 x1 y1]   % Coordinates defining the gradient vector. TODO rotation by angle
  --   /Function REF           % Reference to the shading function
  -- >>
  local shadingDictSpec = string.format([[<<
    /ShadingType 2
    /Extend [true true]
    /ColorSpace /DeviceRGB
    /Coords [%f %f %f %f]
  >>]],
    0, 0,
    x1 - x0, y1 - y0
  )
  local shaderDict = pdf.parse(shadingDictSpec)
  pdf.add_dict(shaderDict, pdf.parse("/Function"), pdf.reference(shadingFunction))

  -- 2. Define the shading pattern.
  -- <<
  --   /Type /Pattern
  --   /PatternType 2          % Type 2 = shading pattern
  --   /Shading REF            % Reference to the shading dictionary
  --   /Matrix [ 1 0 0 1 x0 y0 ] % Matrix to translate the pattern to the correct position ?????????? FIXME
  -- >>
  local patternDictSpec = string.format([[<<
    /Type /Pattern
    /PatternType 2
  >>]]
  --   x0, y0
  )
  local patternDict = pdf.parse(patternDictSpec)
  pdf.add_dict(patternDict, pdf.parse("/Shading"), pdf.reference(shaderDict))
  pdf.release(shaderDict)

  -- 3. Insert the pattern in the page resources and release the pattern dictionary.
  self:_InsertInPage(patternDict, gradient)
end

local Color = SILE.types.color

--- (Override) Register all commands provided by this package.
--
-- Currently provides "checkbox", "radiobutton", "textfield", and "choicemenu" commands.
--
function package:registerCommands ()
  local VIRIDIS = { Color("#fde725"), Color("#5ec962"), Color("#21918c"), Color("#3b528b"), Color("#440154") }

  -- FIXME DEMO COMMAND.
  self:registerCommand("gradientbox", function (options, content)
    if not self._hasGradientsSupport then
      SU.warn("The resilient.gradients package requires the libtexpdf outputter to create gradients.")
      SILE.process(content)
      return
    end
    local gradient = {
      name = SU.required(options, "name", "gradientbox"),
      stops = VIRIDIS,
    }
    SILE.typesetter:pushHbox({
      value = nil,
      width = SILE.types.length("5em"),
      height = SILE.types.length("3em"),
      depth = SILE.types.length("0pt"),
      outputYourself = function (this, typesetter)
        local x0 = typesetter.frame.state.cursorX:tonumber()
        local y0 = typesetter.frame.state.cursorY:tonumber()

        self:_createG(gradient, x0, y0 - this.depth:tonumber(), x0 + this.width:tonumber(), y0 + this.height:tonumber())

        local rect = string.format("/Pattern cs /%s scn /Pattern CS /%s SCN 0 0 %f %f re 0.5 w B", gradient.name, gradient.name, this.width:tonumber(), this.height:tonumber())

        SILE.outputter:drawSVG(rect,
          x0, y0, this.width:tonumber(), this.height:tonumber(), 1)
        typesetter.frame:advanceWritingDirection(this.width)
      end,
    })
  end)

end


package.documentation = [[\begin{document}
FIXME

\medskip
Note that gradients are only supported with SILE’s \code{libtexpdf} outputter, and are ignored otherwise.

\end{document}]]

return package
