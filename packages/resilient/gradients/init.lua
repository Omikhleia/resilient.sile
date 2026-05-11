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

--- (Constructor) Initialize the package.
--
-- @tparam table options Package options (none currently defined)
function package:_init (options)
  base._init(self, options)

  self._shadingFunctions = {} -- Cache of shading functions for gradients
  self._objectsToRelease = {} -- List of lingering PDF objects to release at end

  if SILE.outputter._name ~= "libtexpdf" then
    SU.warn("The resilient.forms package only does something with the libtexpdf backend.")
    self._hasGradientsSupport = false
  else
    pdf = require("justenoughlibtexpdf")
    if not pdf.get_page_resources then
      SU.warn("The resilient.gradients package requires a recent version of SILE.")
      self._hasGradientsSupport = false
    else
      self._hasGradientsSupport = true
      SU.debug("resilient.gradients", "PDF outputter supports gradients, package enabled.")
    end
  end
  local this = self
  SILE.outputter:registerHook("prefinish", function ()
    -- Use a closure to access 'this', check support and release lingering PDF objects.
    if this._hasGradientsSupport then
      this:_releasePdfObjects()
    end
  end)
end

--- (Private) Release PDF objects that were kept until the end.
--
-- Some re-usable objects need to be kept alive until the end of the document,
-- and released after the PDF is finished.
-- In this implementation, these are the shading functions, which we also keep
-- cached for reuse, but for separation of concerns, we keep a list of objects
-- to release in the order they were created.
-- (The order doesn't really matter, but it makes debugging easier.)
--
function package:_releasePdfObjects ()
  SU.debug("resilient.gradients", "Releasing", #self._objectsToRelease, "lingering PDF objects")
  for _, obj in ipairs(self._objectsToRelease) do
    pdf.release(obj)
  end
  -- CODE SMELL
  -- We don't expect the method to be called multiple times,
  -- but with SILE's plain class (i.e. not in resilient, which cancels "multiple" package re-loads),
  -- this is possible... So we clear our list of objects to release, just in case.
  self._objectsToRelease = {}
end

--- (Private) Insert a pattern dictionary in the current page.
--
-- @tparam PdfDict patternDict Pattern dictionary to insert
-- @tparam GradientRef gradient Grail gradient reference
function package:_insertPatternInPage (patternDict, gradient)
  local resources = pdf.get_page_resources()
  local patterns = pdf.lookup_dictionary(resources, "Pattern")
  if not patterns then
    SU.debug("resilient.gradients", "Creating /Pattern dictionary in /Resources on current page for pattern insertion")
    patterns = pdf.parse("<< >>")
    pdf.add_dict(resources, pdf.parse("/Pattern"), patterns)
  end

  local patternName = gradient.name
  pdf.add_dict(patterns, pdf.parse("/" .. patternName), pdf.reference(patternDict))
  pdf.release(patternDict) -- Release the pattern dictionary, no longer needed
  SU.debug("resilient.gradients", "Inserting pattern dictionary for gradient", gradient.name)
end

--- (Private) Build the shading function for a gradient.
--
-- Shading functions are coordinate-independent, so we can build them once per gradient
-- and reuse them for multiple insertions.
--
-- @tparam GradientRef gradient Grail gradient reference
function package:_buildShadingFunction (gradient)
  if self._shadingFunctions[gradient.gradient.name] then
    SU.debug("resilient.gradients", "Using cached shading function for gradient", gradient.gradient.name)
    return self._shadingFunctions[gradient.gradient.name]
  end

  local n = #gradient.gradient.stops - 1
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
    local c0 = gradient.gradient.stops[i]
    local c1 = gradient.gradient.stops[i + 1]
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
  SU.debug("resilient.gradients", "Created shading function for gradient", gradient.gradient.name)
  self._shadingFunctions[gradient.gradient.name] = shadingFunction
  return shadingFunction
end

--- Output a gradient in the PDF document.
--
-- This is the public-facing method that other packages can call to insert a gradient.
--
-- @tparam GradientRef gradient Grail gradient reference
-- @tparam number x0 Start X coordinate
-- @tparam number y0 Start Y coordinate
-- @tparam number x1 End X coordinate
-- @tparam number y1 End Y coordinate
function package:outputGradient (gradient, x0, y0, x1, y1)
  SILE.outputter:_ensureInit()
  local shadingFunction = self:_buildShadingFunction(gradient)

  -- 1. Define the shading dictionary.
  -- <<
  --   /ShadingType 2          % Type 2 = axial shading (linear gradient)
  --   /Extend[true true]      % Whether to extend the shading past the start and ending points
  --   /ColorSpace /DeviceRGB  % Color space for the gradient
  --   /Coords [X0 Y0 X1 Y1]   % Coordinates defining the gradient vector
  --   /Function REF           % Reference to the shading function
  -- >>

  -- Handle the gradient vector:
  -- The rectangle defined by (x0, y0) and (x1, y1) in global (print sheet) coordinates,
  -- but /Coords is in local coordinates (assumiing, as does the outputter, that the shapes are
  -- positionned xith a cm transformation matrix.
  -- CAVEAT: This author has a hard time with rotation matrices and coordinate spaces.
  -- This does seem correct, but it would be good to have a second pair of eyes on this.
  local angle = (gradient.angle or 0) % 360
  local width  = x1 - x0
  local height = y1 - y0
  -- Center in local coordinates
  local cx, cy = width * 0.5, height * 0.5
  -- Half-dimensions of the rectangle
  local hx, hy = math.abs(width) * 0.5, math.abs(height) * 0.5
  -- Unit vector in the direction of the gradient
  local dx = math.cos(math.rad(angle))
  local dy = math.sin(math.rad(angle))
  -- Avoid division by zero on straight gradients angles
  local tx = (dx ~= 0) and (hx / math.abs(dx)) or nil
  local ty = (dy ~= 0) and (hy / math.abs(dy)) or nil
  -- Distance from the center to the intersection with the rectangle edge along the gradient direction
  local t = (tx and ty) and math.min(tx, ty) or (tx or ty)
  -- Gradient vector coordinates in local space, relative to the rectangle center
  local coords = {
    cx - t * dx, cy - t * dy,
    cx + t * dx, cy + t * dy
  }

  local shadingDictSpec = string.format([[<<
    /ShadingType 2
    /Extend [true true]
    /ColorSpace /DeviceRGB
    /Coords [%f %f %f %f]
  >>]],
    coords[1], coords[2], coords[3], coords[4]
  )
  local shaderDict = pdf.parse(shadingDictSpec)
  pdf.add_dict(shaderDict, pdf.parse("/Function"), pdf.reference(shadingFunction))

  -- 2. Define the shading pattern.
  -- <<
  --   /Type /Pattern
  --   /PatternType 2          % Type 2 = shading pattern
  --   /Shading REF            % Reference to the shading dictionary
  --   /Matrix [ a b c d e f ] % Transformation matrix for the pattern
  --                           % Where:
  --                           %   a, d = scale factors for X and Y (width and height of the rectangle)
  --                           %   b, c = rotation/skew factors (0 for no rotation/skew)
  --                           %   e, f = translation (x0, y0)
  -- >>

  -- SILE frame coordinates are relative to the page area (a.k.a paper),
  -- but the PDF coordinates needs to be relative to the actual media (print sheet).
  local deltaX = SILE.documentState.sheetSize and (SILE.documentState.sheetSize[1] - SILE.documentState.paperSize[1]) / 2 or 0
  local deltaY = SILE.documentState.sheetSize and (SILE.documentState.sheetSize[2] - SILE.documentState.paperSize[2]) / 2 or 0

  -- PDF coordinates are bottom-left origin, SILE's are top-left
  local Y0 = SILE.documentState.paperSize[2] - y0

  local patternDictSpec = string.format([[<<
    /Type /Pattern
    /PatternType 2
    /Matrix [%f %f %f %f %f %f]
  >>]],
    1, 0, 0, 1, x0 + deltaX, Y0 + deltaY
  )
  local patternDict = pdf.parse(patternDictSpec)
  pdf.add_dict(patternDict, pdf.parse("/Shading"), pdf.reference(shaderDict))
  pdf.release(shaderDict)

  -- 3. Insert the pattern in the page resources and release the pattern dictionary.
  self:_insertPatternInPage(patternDict, gradient)
end

--- (Override) Register all commands provided by this package.
--
function package:registerCommands ()

  self:registerCommand("gradients:demo", function ()
    if not self._hasGradientsSupport then
      SU.error("The resilient.gradients package requires the libtexpdf outputter to create gradients.")
      return
    end
    self:loadPackage("framebox")
    self:loadPackage("leaders")
    self:loadPackage("struts")
    self:loadPackage("parbox")
    SILE.call("smallskip")
    SILE.call("noindent")
    SILE.call("raggedleft", {}, function ()
      for _, name in ipairs({
          "viridis", "cividis",
          "plasma", "inferno", "magma", "rocket",
          "turbo", "spectral", "vlag",
          "crest",
          "flare", "mako",
        }) do
        SILE.typesetter:typeset(" ")
        SILE.call("framebox", { fillcolor = name, padding = "0.8em" }, function ()
          SILE.call("parbox", { width = "25%lw" }, function ()
            SILE.call("center", {}, function ()
              SILE.call("font", { size = "0.8em", family = "Libertinus Sans" }, { name })
              SILE.call("strut")
            end)
          end)
        end)
      end
      SILE.call("smallskip")
      SILE.call("noindent")
      for _, name in ipairs({
          "firebricks", "forestgreens", "steelblues"
        }) do
        SILE.typesetter:typeset(" ")
        SILE.call("framebox", { fillcolor = name, padding = "0.8em" }, function ()
          SILE.call("parbox", { width = "25%lw" }, function ()
            SILE.call("center", {}, function ()
              SILE.call("font", { size = "0.8em", family = "Libertinus Sans" }, { name })
              SILE.call("strut")
            end)
          end)
        end)
      end
      SILE.call("smallskip")
      SILE.call("noindent")
      for _, name in ipairs({
          "omissible", "omissiblesilver", "omissiblegold",
          "omissiblecopper", "omissiblebrass", "omissiblebronze",
          "omissibleruby", "omissibleemerald", "omissiblesapphire"
        }) do
        SILE.typesetter:typeset(" ")
        SILE.call("framebox", { fillcolor = name .. " 90", padding = "0.8em" }, function ()
          SILE.call("parbox", { width = "25%lw" }, function ()
            SILE.call("center", {}, function ()
              SILE.call("font", { size = "0.8em", family = "Libertinus Sans" }, { name })
              SILE.call("strut")
            end)
          end)
        end)
      end
      SILE.call("smallskip")
      SILE.call("noindent")
      for _, name in ipairs({
            "metallicsteel", "metallicsilver", "metallicgold",
            "metalliccopper", "metallicbrass", "metallicbronze"
        }) do
        SILE.typesetter:typeset(" ")
        SILE.call("framebox", { fillcolor = name .. " 90", padding = "0.8em" }, function ()
          SILE.call("parbox", { width = "25%lw" }, function ()
            SILE.call("center", {}, function ()
              SILE.call("font", { size = "0.8em", family = "Libertinus Sans" }, { name })
              SILE.call("strut")
            end)
          end)
        end)
      end
    end)
    SILE.call("smallskip")
  end)

end


package.documentation = [[\begin{document}
The experimental \autodoc:package{resilient.gradients} package allows the creation of color gradients in PDF documents.

It does not provide any user-level command, but other packages can rely on it.
For instance, packages \autodoc:package{framebox} and \autodoc:package{resilient.background} accept a gradient name in all their color-accepting options.

Named gradients provided out of the box include:
\begin{itemize}
\item{Some usual gradients (\code{viridis}, etc.),}
\item{The plural form of a named color as 2-stop gradients that go from a slightly darker to a lighter shade of the corresponding color,}
\item{This authors’s own gradient families.}
\end{itemize}

The gradient name may be suffixed with an angle (e.g. \code{omissible 90}).

\gradients:demo

Note that gradients are only supported with SILE’s \code{libtexpdf} outputter, and are ignored otherwise.

\end{document}]]

return package
