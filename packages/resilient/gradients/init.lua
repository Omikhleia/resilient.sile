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

  self._objectsToRelease = {} -- List of PDF objects to release at end

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
  --   /Coords [X0 Y0 X1 Y1]   % Coordinates defining the gradient vector.
  --   /Function REF           % Reference to the shading function
  -- >>
  local angle = gradient.angle or 0
  local coords =
    angle == 0 and {0, 0, x1 - x0, 0} or
    angle == 90 and {0, 0, 0, y1 - y0} or
    SU.error("Only angles of 0 and 90 degrees are currently supported for gradients.\n" .. [[
  I am a bit lost at /Coords, /Matrix, the cm matrix that ends up where the
  drawing is inserted, and how to do rotations...
  If this is something you need, please study the code, the PDF specification,
  and consider contributing a patch to support other angles and/or radial gradients.
]])
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
  local Y0 = SILE.documentState.paperSize[2] - y0 -- PDF coordinates are bottom-left origin, SILE's are top-left
  local patternDictSpec = string.format([[<<
    /Type /Pattern
    /PatternType 2
    /Matrix [%f %f %f %f %f %f]
  >>]],
    1, 0, 0, 1, x0, Y0
  )
  local patternDict = pdf.parse(patternDictSpec)
  pdf.add_dict(patternDict, pdf.parse("/Shading"), pdf.reference(shaderDict))
  pdf.release(shaderDict)

  -- 3. Insert the pattern in the page resources and release the pattern dictionary.
  self:_InsertInPage(patternDict, gradient)
end

local Color = SILE.types.color

local GRADIENTS = {
  turbo = {
    Color("#23171b"), Color("#271a28"), Color("#2b1c33"), Color("#2f1e3f"), Color("#32204a"), Color("#362354"),
    Color("#39255f"), Color("#3b2768"), Color("#3e2a72"), Color("#402c7b"), Color("#422f83"), Color("#44318b"),
    Color("#453493"), Color("#46369b"), Color("#4839a2"), Color("#493ca8"), Color("#493eaf"), Color("#4a41b5"),
    Color("#4a44bb"), Color("#4b46c0"), Color("#4b49c5"), Color("#4b4cc8"), Color("#4b4ecf"), Color("#4b51d3"),
    Color("#4a54d7"), Color("#4a56db"), Color("#4959de"), Color("#495ce2"), Color("#485fe5"), Color("#4761e7"),
    Color("#4664ea"), Color("#4567ec"), Color("#446aee"), Color("#446df0"), Color("#426ff2"), Color("#4172f3"),
    Color("#4075f5"), Color("#3f78f6"), Color("#3e7af7"), Color("#3d7df7"), Color("#3c80f8"), Color("#3a83f9"),
    Color("#3985f9"), Color("#3888f9"), Color("#378bf9"), Color("#368df9"), Color("#3590f8"), Color("#3393f8"),
    Color("#3295f7"), Color("#3198f7"), Color("#309bf6"), Color("#2f9df5"), Color("#2ea0f4"), Color("#2da2f3"),
    Color("#2ca5f1"), Color("#2ba7f0"), Color("#2aaaef"), Color("#2aaced"), Color("#29afec"), Color("#28b1ea"),
    Color("#28b4e8"), Color("#27b6e6"), Color("#27b8e5"), Color("#26bbe3"), Color("#26bde1"), Color("#26bfdf"),
    Color("#25c1dc"), Color("#25c3da"), Color("#25c6d8"), Color("#25c8d6"), Color("#25cad3"), Color("#25ccd1"),
    Color("#25cecf"), Color("#26d0cc"), Color("#26d2ca"), Color("#26d4c8"), Color("#27d6c5"), Color("#27d8c3"),
    Color("#28d9c0"), Color("#29dbbe"), Color("#29ddbb"), Color("#2adfb8"), Color("#2be0b6"), Color("#2ce2b3"),
    Color("#2de3b1"), Color("#2ee5ae"), Color("#30e6ac"), Color("#31e8a9"), Color("#32e9a6"), Color("#34eba4"),
    Color("#35eca1"), Color("#37ed9f"), Color("#39ef9c"), Color("#3af09a"), Color("#3cf197"), Color("#3ef295"),
    Color("#40f392"), Color("#42f490"), Color("#44f58d"), Color("#46f68b"), Color("#48f788"), Color("#4af786"),
    Color("#4df884"), Color("#4ff981"), Color("#51fa7f"), Color("#54fa7d"), Color("#56fb7a"), Color("#59fb78"),
    Color("#5cfc76"), Color("#5efc74"), Color("#61fd71"), Color("#64fd6f"), Color("#66fd6d"), Color("#69fd6b"),
    Color("#6cfd69"), Color("#6ffe67"), Color("#72fe65"), Color("#75fe63"), Color("#78fe61"), Color("#7bfe5f"),
    Color("#7efd5d"), Color("#81fd5c"), Color("#84fd5a"), Color("#87fd58"), Color("#8afc56"), Color("#8dfc55"),
    Color("#90fb53"), Color("#93fb51"), Color("#96fa50"), Color("#99fa4e"), Color("#9cf94d"), Color("#9ff84b"),
    Color("#a2f84a"), Color("#a6f748"), Color("#a9f647"), Color("#acf546"), Color("#aff444"), Color("#b2f343"),
    Color("#b5f242"), Color("#b8f141"), Color("#bbf03f"), Color("#beef3e"), Color("#c1ed3d"), Color("#c3ec3c"),
    Color("#c6eb3b"), Color("#c9e93a"), Color("#cce839"), Color("#cfe738"), Color("#d1e537"), Color("#d4e336"),
    Color("#d7e235"), Color("#d9e034"), Color("#dcdf33"), Color("#dedd32"), Color("#e0db32"), Color("#e3d931"),
    Color("#e5d730"), Color("#e7d52f"), Color("#e9d42f"), Color("#ecd22e"), Color("#eed02d"), Color("#f0ce2c"),
    Color("#f1cb2c"), Color("#f3c92b"), Color("#f5c72b"), Color("#f7c52a"), Color("#f8c329"), Color("#fac029"),
    Color("#fbbe28"), Color("#fdbc28"), Color("#feb927"), Color("#ffb727"), Color("#ffb526"), Color("#ffb226"),
    Color("#ffb025"), Color("#ffad25"), Color("#ffab24"), Color("#ffa824"), Color("#ffa623"), Color("#ffa323"),
    Color("#ffa022"), Color("#ff9e22"), Color("#ff9b21"), Color("#ff9921"), Color("#ff9621"), Color("#ff9320"),
    Color("#ff9020"), Color("#ff8e1f"), Color("#ff8b1f"), Color("#ff881e"), Color("#ff851e"), Color("#ff831d"),
    Color("#ff801d"), Color("#ff7d1d"), Color("#ff7a1c"), Color("#ff781c"), Color("#ff751b"), Color("#ff721b"),
    Color("#ff6f1a"), Color("#fd6c1a"), Color("#fc6a19"), Color("#fa6719"), Color("#f96418"), Color("#f76118"),
    Color("#f65f18"), Color("#f45c17"), Color("#f25916"), Color("#f05716"), Color("#ee5415"), Color("#ec5115"),
    Color("#ea4f14"), Color("#e84c14"), Color("#e64913"), Color("#e44713"), Color("#e24412"), Color("#df4212"),
    Color("#dd3f11"), Color("#da3d10"), Color("#d83a10"), Color("#d5380f"), Color("#d3360f"), Color("#d0330e"),
    Color("#ce310d"), Color("#cb2f0d"), Color("#c92d0c"), Color("#c62a0b"), Color("#c3280b"), Color("#c1260a"),
    Color("#be2409"), Color("#bb2309"), Color("#b92108"), Color("#b61f07"), Color("#b41d07"), Color("#b11b06"),
    Color("#af1a05"), Color("#ac1805"), Color("#aa1704"), Color("#a81604"), Color("#a51403"), Color("#a31302"),
    Color("#a11202"), Color("#9f1101"), Color("#9d1000"), Color("#9b0f00"), Color("#9a0e00"), Color("#980e00"),
    Color("#960d00"), Color("#950c00"), Color("#940c00"), Color("#930c00"), Color("#920c00"), Color("#910b00"),
    Color("#910c00"), Color("#900c00")
  },
  cividis = {
    Color("#002051"), Color("#002153"), Color("#002255"), Color("#002356"), Color("#002358"), Color("#002459"),
    Color("#00255a"), Color("#00255c"), Color("#00265d"), Color("#00275e"), Color("#00275f"), Color("#002860"),
    Color("#002961"), Color("#002962"), Color("#002a63"), Color("#002b64"), Color("#012b65"), Color("#022c65"),
    Color("#032d66"), Color("#042d67"), Color("#052e67"), Color("#052f68"), Color("#063069"), Color("#073069"),
    Color("#08316a"), Color("#09326a"), Color("#0b326a"), Color("#0c336b"), Color("#0d346b"), Color("#0e346b"),
    Color("#0f356c"), Color("#10366c"), Color("#12376c"), Color("#13376d"), Color("#14386d"), Color("#15396d"),
    Color("#17396d"), Color("#183a6d"), Color("#193b6d"), Color("#1a3b6d"), Color("#1c3c6e"), Color("#1d3d6e"),
    Color("#1e3e6e"), Color("#203e6e"), Color("#213f6e"), Color("#23406e"), Color("#24406e"), Color("#25416e"),
    Color("#27426e"), Color("#28436e"), Color("#29436e"), Color("#2b446e"), Color("#2c456e"), Color("#2e456e"),
    Color("#2f466e"), Color("#30476e"), Color("#32486e"), Color("#33486e"), Color("#34496e"), Color("#364a6e"),
    Color("#374a6e"), Color("#394b6e"), Color("#3a4c6e"), Color("#3b4d6e"), Color("#3d4d6e"), Color("#3e4e6e"),
    Color("#3f4f6e"), Color("#414f6e"), Color("#42506e"), Color("#43516d"), Color("#44526d"), Color("#46526d"),
    Color("#47536d"), Color("#48546d"), Color("#4a546d"), Color("#4b556d"), Color("#4c566d"), Color("#4d576d"),
    Color("#4e576e"), Color("#50586e"), Color("#51596e"), Color("#52596e"), Color("#535a6e"), Color("#545b6e"),
    Color("#565c6e"), Color("#575c6e"), Color("#585d6e"), Color("#595e6e"), Color("#5a5e6e"), Color("#5b5f6e"),
    Color("#5c606e"), Color("#5d616e"), Color("#5e616e"), Color("#60626e"), Color("#61636f"), Color("#62646f"),
    Color("#63646f"), Color("#64656f"), Color("#65666f"), Color("#66666f"), Color("#67676f"), Color("#686870"),
    Color("#696970"), Color("#6a6970"), Color("#6b6a70"), Color("#6c6b70"), Color("#6d6c70"), Color("#6d6c71"),
    Color("#6e6d71"), Color("#6f6e71"), Color("#706f71"), Color("#716f71"), Color("#727071"), Color("#737172"),
    Color("#747172"), Color("#757272"), Color("#767372"), Color("#767472"), Color("#777473"), Color("#787573"),
    Color("#797673"), Color("#7a7773"), Color("#7b7774"), Color("#7b7874"), Color("#7c7974"), Color("#7d7a74"),
    Color("#7e7a74"), Color("#7f7b75"), Color("#807c75"), Color("#807d75"), Color("#817d75"), Color("#827e75"),
    Color("#837f76"), Color("#848076"), Color("#858076"), Color("#858176"), Color("#868276"), Color("#878376"),
    Color("#888477"), Color("#898477"), Color("#898577"), Color("#8a8677"), Color("#8b8777"), Color("#8c8777"),
    Color("#8d8877"), Color("#8e8978"), Color("#8e8a78"), Color("#8f8a78"), Color("#908b78"), Color("#918c78"),
    Color("#928d78"), Color("#938e78"), Color("#938e78"), Color("#948f78"), Color("#959078"), Color("#969178"),
    Color("#979278"), Color("#989278"), Color("#999378"), Color("#9a9478"), Color("#9b9578"), Color("#9b9678"),
    Color("#9c9678"), Color("#9d9778"), Color("#9e9878"), Color("#9f9978"), Color("#a09a78"), Color("#a19a78"),
    Color("#a29b78"), Color("#a39c78"), Color("#a49d78"), Color("#a59e77"), Color("#a69e77"), Color("#a79f77"),
    Color("#a8a077"), Color("#a9a177"), Color("#aaa276"), Color("#aba376"), Color("#aca376"), Color("#ada476"),
    Color("#aea575"), Color("#afa675"), Color("#b0a775"), Color("#b2a874"), Color("#b3a874"), Color("#b4a974"),
    Color("#b5aa73"), Color("#b6ab73"), Color("#b7ac72"), Color("#b8ad72"), Color("#baae72"), Color("#bbae71"),
    Color("#bcaf71"), Color("#bdb070"), Color("#beb170"), Color("#bfb26f"), Color("#c1b36f"), Color("#c2b46e"),
    Color("#c3b56d"), Color("#c4b56d"), Color("#c5b66c"), Color("#c7b76c"), Color("#c8b86b"), Color("#c9b96a"),
    Color("#caba6a"), Color("#ccbb69"), Color("#cdcc68"), Color("#cebc68"), Color("#cfbd67"), Color("#d1be66"),
    Color("#d2bf66"), Color("#d3c065"), Color("#d4c164"), Color("#d6c263"), Color("#d7c363"), Color("#d8c462"),
    Color("#d9c561"), Color("#dbc660"), Color("#dcc660"), Color("#ddc75f"), Color("#dec85e"), Color("#e0c95d"),
    Color("#e1ca5c"), Color("#e2cb5c"), Color("#e3cc5b"), Color("#e4cd5a"), Color("#e6ce59"), Color("#e7cf58"),
    Color("#e8d058"), Color("#e9d157"), Color("#ead256"), Color("#ebd355"), Color("#ecd454"), Color("#edd453"),
    Color("#eed553"), Color("#f0d652"), Color("#f1d751"), Color("#f1d850"), Color("#f2d950"), Color("#f3da4f"),
    Color("#f4db4e"), Color("#f5dc4d"), Color("#f6dd4d"), Color("#f7de4c"), Color("#f8df4b"), Color("#f8e04b"),
    Color("#f9e14a"), Color("#fae249"), Color("#fae349"), Color("#fbe448"), Color("#fbe548"), Color("#fce647"),
    Color("#fce746"), Color("#fde846"), Color("#fde946"), Color("#fdea45")
  },
  spectral = {
    Color("#9e0142"), Color("#d53e4f"), Color("#f46d43"), Color("#fdae61"), Color("#fee08b"), Color("#ffffbf"),
    Color("#e6f598"), Color("#abdda4"), Color("#66c2a5"), Color("#3288bd"), Color("#5e4fa2")
  },
  viridis = {
    Color("#440154"), Color("#482777"), Color("#3f4a8a"), Color("#31678e"), Color("#26838f"), Color("#1f9d8a"),
    Color("#6cce5a"), Color("#b6de2b"), Color("#fee825")
  },
  inferno = {
    Color("#000004"), Color("#170b3a"), Color("#420a68"), Color("#6b176e"), Color("#932667"), Color("#bb3654"),
    Color("#dd513a"), Color("#f3771a"), Color("#fca50a"), Color("#f6d644"), Color("#fcffa4")
  },
  magma = {
    Color("#000004"), Color("#140e37"), Color("#3b0f70"), Color("#641a80"), Color("#8c2981"), Color("#b63679"),
    Color("#de4968"), Color("#f66f5c"), Color("#fe9f6d"), Color("#fece91"), Color("#fcfdbf")
  },
  plasma = {
    Color("#0d0887"), Color("#42039d"), Color("#6a00a8"), Color("#900da3"), Color("#b12a90"), Color("#cb4678"),
    Color("#e16462"), Color("#f1834b"), Color("#fca636"), Color("#fccd25"), Color("#f0f921")
  },
  rocket = {
    Color("#100b23"), Color("#110c24"), Color("#130d25"), Color("#140e26"), Color("#160e27"),
    Color("#170f28"), Color("#180f29"), Color("#1a102a"), Color("#1b112b"), Color("#1d112c"), Color("#1e122d"),
    Color("#20122e"), Color("#211330"), Color("#221331"), Color("#241432"), Color("#251433"), Color("#271534"),
    Color("#281535"), Color("#2a1636"), Color("#2b1637"), Color("#2d1738"), Color("#2e1739"), Color("#30173a"),
    Color("#31183b"), Color("#33183c"), Color("#34193d"), Color("#35193e"), Color("#37193f"), Color("#381a40"),
    Color("#3a1a41"), Color("#3c1a42"), Color("#3d1a42"), Color("#3f1b43"), Color("#401b44"), Color("#421b45"),
    Color("#431c46"), Color("#451c47"), Color("#461c48"), Color("#481c48"), Color("#491d49"), Color("#4b1d4a"),
    Color("#4c1d4b"), Color("#4e1d4b"), Color("#501d4c"), Color("#511e4d"), Color("#531e4d"), Color("#541e4e"),
    Color("#561e4f"), Color("#581e4f"), Color("#591e50"), Color("#5b1e51"), Color("#5c1e51"), Color("#5e1f52"),
    Color("#601f52"), Color("#611f53"), Color("#631f53"), Color("#641f54"), Color("#661f54"), Color("#681f55"),
    Color("#691f55"), Color("#6b1f56"), Color("#6d1f56"), Color("#6e1f57"), Color("#701f57"), Color("#711f57"),
    Color("#731f58"), Color("#751f58"), Color("#761f58"), Color("#781f59"), Color("#7a1f59"), Color("#7b1f59"),
    Color("#7d1f5a"), Color("#7f1e5a"), Color("#811e5a"), Color("#821e5a"), Color("#841e5a"), Color("#861e5b"),
    Color("#871e5b"), Color("#891e5b"), Color("#8b1d5b"), Color("#8c1d5b"), Color("#8e1d5b"), Color("#901d5b"),
    Color("#921c5b"), Color("#931c5b"), Color("#951c5b"), Color("#971c5b"), Color("#981b5b"), Color("#9a1b5b"),
    Color("#9c1b5b"), Color("#9e1a5b"), Color("#9f1a5b"), Color("#a11a5b"), Color("#a3195b"), Color("#a4195b"),
    Color("#a6195a"), Color("#a8185a"), Color("#aa185a"), Color("#ab185a"), Color("#ad1759"), Color("#af1759"),
    Color("#b01759"), Color("#b21758"), Color("#b41658"), Color("#b51657"), Color("#b71657"), Color("#b91657"),
    Color("#ba1656"), Color("#bc1656"), Color("#bd1655"), Color("#bf1654"), Color("#c11754"), Color("#c21753"),
    Color("#c41753"), Color("#c51852"), Color("#c71951"), Color("#c81951"), Color("#ca1a50"), Color("#cb1b4f"),
    Color("#cd1c4e"), Color("#ce1d4e"), Color("#cf1e4d"), Color("#d11f4c"), Color("#d2204c"), Color("#d3214b"),
    Color("#d5224a"), Color("#d62449"), Color("#d72549"), Color("#d82748"), Color("#d92847"), Color("#db2946"),
    Color("#dc2b46"), Color("#dd2c45"), Color("#de2e44"), Color("#df2f44"), Color("#e03143"), Color("#e13342"),
    Color("#e23442"), Color("#e33641"), Color("#e43841"), Color("#e53940"), Color("#e63b40"), Color("#e73d3f"),
    Color("#e83f3f"), Color("#e8403e"), Color("#e9423e"), Color("#ea443e"), Color("#eb463e"), Color("#eb483e"),
    Color("#ec4a3e"), Color("#ec4c3e"), Color("#ed4e3e"), Color("#ed503e"), Color("#ee523f"), Color("#ee543f"),
    Color("#ef5640"), Color("#ef5840"), Color("#ef5a41"), Color("#f05c42"), Color("#f05e42"), Color("#f06043"),
    Color("#f16244"), Color("#f16445"), Color("#f16646"), Color("#f26747"), Color("#f26948"), Color("#f26b49"),
    Color("#f26d4b"), Color("#f26f4c"), Color("#f3714d"), Color("#f3734e"), Color("#f37450"), Color("#f37651"),
    Color("#f37852"), Color("#f47a54"), Color("#f47c55"), Color("#f47d57"), Color("#f47f58"), Color("#f4815a"),
    Color("#f4835b"), Color("#f4845d"), Color("#f4865e"), Color("#f58860"), Color("#f58a61"), Color("#f58b63"),
    Color("#f58d64"), Color("#f58f66"), Color("#f59067"), Color("#f59269"), Color("#f5946b"), Color("#f5966c"),
    Color("#f5976e"), Color("#f59970"), Color("#f69b71"), Color("#f69c73"), Color("#f69e75"), Color("#f6a077"),
    Color("#f6a178"), Color("#f6a37a"), Color("#f6a47c"), Color("#f6a67e"), Color("#f6a880"), Color("#f6a981"),
    Color("#f6ab83"), Color("#f6ad85"), Color("#f6ae87"), Color("#f6b089"), Color("#f6b18b"), Color("#f6b38d"),
    Color("#f6b48f"), Color("#f6b691"), Color("#f6b893"), Color("#f6b995"), Color("#f6bb97"), Color("#f6bc99"),
    Color("#f6be9b"), Color("#f6bf9d"), Color("#f6c19f"), Color("#f7c2a2"), Color("#f7c4a4"), Color("#f7c6a6"),
    Color("#f7c7a8"), Color("#f7c9aa"), Color("#f7caac"), Color("#f7ccaf"), Color("#f7cdb1"), Color("#f7cfb3"),
    Color("#f7d0b5"), Color("#f8d1b8"), Color("#f8d3ba"), Color("#f8d4bc"), Color("#f8d6be"), Color("#f8d7c0"),
    Color("#f8d9c3"), Color("#f8dac5"), Color("#f8dcc7"), Color("#f9ddc9"), Color("#f9dfcb"), Color("#f9e0cd"),
    Color("#f9e2d0"), Color("#f9e3d2"), Color("#f9e5d4"), Color("#fae6d6"), Color("#fae8d8"), Color("#fae9da"),
    Color("#faebdd")
  },


  vlag = {
    Color("#2369bd"), Color("#266abd"), Color("#296cbc"), Color("#2c6dbc"), Color("#2f6ebc"), Color("#316fbc"),
    Color("#3470bc"), Color("#3671bc"), Color("#3972bc"), Color("#3b73bc"), Color("#3d74bc"), Color("#3f75bc"),
    Color("#4276bc"), Color("#4477bc"), Color("#4678bc"), Color("#4879bc"), Color("#4a7bbc"), Color("#4c7cbc"),
    Color("#4e7dbc"), Color("#507ebc"), Color("#517fbc"), Color("#5380bc"), Color("#5581bc"), Color("#5782bc"),
    Color("#5983bd"), Color("#5b84bd"), Color("#5c85bd"), Color("#5e86bd"), Color("#6087bd"), Color("#6288bd"),
    Color("#6489be"), Color("#658abe"), Color("#678bbe"), Color("#698cbe"), Color("#6a8dbf"), Color("#6c8ebf"),
    Color("#6e90bf"), Color("#6f91bf"), Color("#7192c0"), Color("#7393c0"), Color("#7594c0"), Color("#7695c1"),
    Color("#7896c1"), Color("#7997c1"), Color("#7b98c2"), Color("#7d99c2"), Color("#7e9ac2"), Color("#809bc3"),
    Color("#829cc3"), Color("#839dc4"), Color("#859ec4"), Color("#87a0c4"), Color("#88a1c5"), Color("#8aa2c5"),
    Color("#8ba3c6"), Color("#8da4c6"), Color("#8fa5c7"), Color("#90a6c7"), Color("#92a7c8"), Color("#93a8c8"),
    Color("#95a9c8"), Color("#97abc9"), Color("#98acc9"), Color("#9aadc9"), Color("#9baecb"), Color("#9dafcb"),
    Color("#9fb0cc"), Color("#a0b1cc"), Color("#a2b2cd"), Color("#a3b4cd"), Color("#a5b5ce"), Color("#a7b6ce"),
    Color("#a8b7cf"), Color("#aab8d0"), Color("#abb9d0"), Color("#adbbd1"), Color("#afbcd1"), Color("#b0bdd2"),
    Color("#b2bed3"), Color("#b3bfd3"), Color("#b5c0d4"), Color("#b7c2d5"), Color("#b8c3d5"), Color("#bac4d6"),
    Color("#bbc5d7"), Color("#bdc6d7"), Color("#bfc8d8"), Color("#c0c9d9"), Color("#c2cada"), Color("#c3cbda"),
    Color("#c5cddb"), Color("#c7cedc"), Color("#c8cfdd"), Color("#cad0dd"), Color("#cbd1de"), Color("#cdd3df"),
    Color("#cfd4e0"), Color("#d0d5e0"), Color("#d2d7e1"), Color("#d4d8e2"), Color("#d5d9e3"), Color("#d7dae4"),
    Color("#d9dce5"), Color("#dadde5"), Color("#dcdee6"), Color("#dde0e7"), Color("#dfe1e8"), Color("#e1e2e9"),
    Color("#e2e3ea"), Color("#e4e5eb"), Color("#e6e6ec"), Color("#e7e7ec"), Color("#e9e9ed"), Color("#ebeaee"),
    Color("#ecebef"), Color("#eeedf0"), Color("#efeef1"), Color("#f1eff2"), Color("#f2f0f2"), Color("#f3f1f3"),
    Color("#f5f2f4"), Color("#f6f3f4"), Color("#f7f4f4"), Color("#f8f4f5"), Color("#f9f5f5"), Color("#f9f5f5"),
    Color("#faf5f5"), Color("#faf5f5"), Color("#faf5f4"), Color("#faf5f4"), Color("#faf4f3"), Color("#faf3f3"),
    Color("#faf3f2"), Color("#faf2f1"), Color("#faf0ef"), Color("#f9efee"), Color("#f9eeed"), Color("#f8edeb"),
    Color("#f7ebe8"), Color("#f7eae7"), Color("#f6e8e7"), Color("#f5e7e5"), Color("#f5e5e4"), Color("#f4e3e2"),
    Color("#f3e2e0"), Color("#f2e0df"), Color("#f2dfdd"), Color("#f1dddb"), Color("#f0dbda"), Color("#efd8d6"),
    Color("#eed7d5"), Color("#edd5d3"), Color("#ecd3d2"), Color("#ebd0ce"), Color("#eacfcd"), Color("#eacdcb"),
    Color("#e9cbc9"), Color("#e8cac8"), Color("#e7c8c6"), Color("#e7c7c5"), Color("#e6c5c3"), Color("#e5c3c1"),
    Color("#e5c2c0"), Color("#e4c0be"), Color("#e3bfbd"), Color("#e3bdbb"), Color("#e2bcb9"), Color("#e1bab8"),
    Color("#e1b9b6"), Color("#e0b7b5"), Color("#dfb5b3"), Color("#dfb4b2"), Color("#deb2b0"), Color("#deb1ae"),
    Color("#ddafad"), Color("#dcaeab"), Color("#dcacaa"), Color("#dbaba8"), Color("#daa9a7"), Color("#daa8a5"),
    Color("#d9a6a4"), Color("#d9a5a2"), Color("#d8a3a0"), Color("#d7a29f"), Color("#d7a09d"), Color("#d69f9c"),
    Color("#d59d9a"), Color("#d59c99"), Color("#d49a97"), Color("#d49896"), Color("#d39794"), Color("#d29593"),
    Color("#d29491"), Color("#d19290"), Color("#d1918e"), Color("#d08f8d"), Color("#cf8e8b"), Color("#cf8c8a"),
    Color("#ce8b88"), Color("#cd8987"), Color("#cd8885"), Color("#cc8784"), Color("#cc8582"), Color("#cb8481"),
    Color("#ca827f"), Color("#ca817e"), Color("#c97f7d"), Color("#c87e7b"), Color("#c87c7a"), Color("#c77b78"),
    Color("#c77977"), Color("#c67875"), Color("#c57674"), Color("#c57572"), Color("#c47371"), Color("#c3726f"),
    Color("#c3706e"), Color("#c26f6d"), Color("#c16d6b"), Color("#c16c6a"), Color("#c06a68"), Color("#c06967"),
    Color("#bf6765"), Color("#be6664"), Color("#be6463"), Color("#bd6361"), Color("#bc6160"), Color("#bc605e"),
    Color("#bb5e5d"), Color("#ba5d5c"), Color("#b95b5a"), Color("#b95a59"), Color("#b85857"), Color("#b75756"),
    Color("#b75555"), Color("#b65453"), Color("#b55252"), Color("#b55151"), Color("#b44f4f"), Color("#b34d4e"),
    Color("#b24c4c"), Color("#b24a4b"), Color("#b1494a"), Color("#b04748"), Color("#af4647"), Color("#af4446"),
    Color("#ae4244"), Color("#ad4143"), Color("#ac3f42"), Color("#ac3e40"), Color("#ab3c3f"), Color("#aa3a3e"),
    Color("#a9393c"), Color("#a9373b")
  },
  flare = {
    Color("#edb081"), Color("#edaf80"), Color("#edae7f"), Color("#edad7f"), Color("#edac7e"), Color("#edab7e"),
    Color("#ecaa7d"), Color("#eca97c"), Color("#eca87c"), Color("#eca77b"), Color("#eca67b"), Color("#eca57a"),
    Color("#eca479"), Color("#eca379"), Color("#eca278"), Color("#eca178"), Color("#eca077"), Color("#ec9f76"),
    Color("#eb9e76"), Color("#eb9d75"), Color("#eb9c75"), Color("#eb9b74"), Color("#eb9a73"), Color("#eb9973"),
    Color("#eb9972"), Color("#eb9872"), Color("#eb9771"), Color("#ea9671"), Color("#ea9570"), Color("#ea946f"),
    Color("#ea936f"), Color("#ea926e"), Color("#ea916e"), Color("#ea906d"), Color("#ea8f6c"), Color("#ea8e6c"),
    Color("#e98d6b"), Color("#e98c6b"), Color("#e98b6a"), Color("#e98a6a"), Color("#e98969"), Color("#e98868"),
    Color("#e98768"), Color("#e98667"), Color("#e88567"), Color("#e88466"), Color("#e88366"), Color("#e88265"),
    Color("#e88165"), Color("#e88064"), Color("#e87f64"), Color("#e77e63"), Color("#e77d63"), Color("#e77c63"),
    Color("#e77b62"), Color("#e77a62"), Color("#e67961"), Color("#e67861"), Color("#e67760"), Color("#e67660"),
    Color("#e67560"), Color("#e5745f"), Color("#e5735f"), Color("#e5725f"), Color("#e5715e"), Color("#e5705e"),
    Color("#e46f5e"), Color("#e46e5e"), Color("#e46d5d"), Color("#e46c5d"), Color("#e36b5d"), Color("#e36a5d"),
    Color("#e3695d"), Color("#e3685c"), Color("#e2675c"), Color("#e2665c"), Color("#e2655c"), Color("#e1645c"),
    Color("#e1635c"), Color("#e1625c"), Color("#e0615c"), Color("#e0605c"), Color("#e05f5c"), Color("#df5f5c"),
    Color("#df5e5c"), Color("#de5d5c"), Color("#de5c5c"), Color("#de5b5c"), Color("#dd5a5c"), Color("#dd595c"),
    Color("#dc585c"), Color("#dc575c"), Color("#db565d"), Color("#db565d"), Color("#da555d"), Color("#da545d"),
    Color("#d9535d"), Color("#d9525e"), Color("#d8525e"), Color("#d7515e"), Color("#d7505e"), Color("#d64f5f"),
    Color("#d64f5f"), Color("#d54e5f"), Color("#d44d60"), Color("#d44c60"), Color("#d34c60"), Color("#d24b60"),
    Color("#d24a61"), Color("#d14a61"), Color("#d04962"), Color("#d04962"), Color("#cf4862"), Color("#ce4763"),
    Color("#cd4763"), Color("#cc4663"), Color("#cc4664"), Color("#cb4564"), Color("#ca4564"), Color("#c94465"),
    Color("#c84465"), Color("#c84365"), Color("#c74366"), Color("#c64366"), Color("#c54266"), Color("#c44267"),
    Color("#c34167"), Color("#c24167"), Color("#c14168"), Color("#c14068"), Color("#c04068"), Color("#bf4069"),
    Color("#be3f69"), Color("#bd3f69"), Color("#bc3f69"), Color("#bb3f6a"), Color("#ba3e6a"), Color("#b93e6a"),
    Color("#b83e6b"), Color("#b73d6b"), Color("#b63d6b"), Color("#b53d6b"), Color("#b43d6b"), Color("#b33c6c"),
    Color("#b23c6c"), Color("#b13c6c"), Color("#b13c6c"), Color("#b03b6d"), Color("#af3b6d"), Color("#ae3b6d"),
    Color("#ad3b6d"), Color("#ac3a6d"), Color("#ab3a6d"), Color("#aa3a6e"), Color("#a93a6e"), Color("#a8396e"),
    Color("#a7396e"), Color("#a6396e"), Color("#a5396e"), Color("#a4386f"), Color("#a3386f"), Color("#a2386f"),
    Color("#a1386f"), Color("#a1376f"), Color("#a0376f"), Color("#9f376f"), Color("#9e3770"), Color("#9d3670"),
    Color("#9c3670"), Color("#9b3670"), Color("#9a3670"), Color("#993570"), Color("#983570"), Color("#973570"),
    Color("#963570"), Color("#953470"), Color("#943470"), Color("#943471"), Color("#933471"), Color("#923371"),
    Color("#913371"), Color("#903371"), Color("#8f3371"), Color("#8e3271"), Color("#8d3271"), Color("#8c3271"),
    Color("#8b3271"), Color("#8a3171"), Color("#893171"), Color("#883171"), Color("#873171"), Color("#873171"),
    Color("#863071"), Color("#853071"), Color("#843071"), Color("#833070"), Color("#822f70"), Color("#812f70"),
    Color("#802f70"), Color("#7f2f70"), Color("#7e2f70"), Color("#7d2e70"), Color("#7c2e70"), Color("#7b2e70"),
    Color("#7a2e70"), Color("#792e6f"), Color("#782e6f"), Color("#772d6f"), Color("#762d6f"), Color("#752d6f"),
    Color("#752d6f"), Color("#742d6e"), Color("#732c6e"), Color("#722c6e"), Color("#712c6e"), Color("#702c6e"),
    Color("#6f2c6d"), Color("#6e2c6d"), Color("#6d2b6d"), Color("#6c2b6d"), Color("#6b2b6c"), Color("#6a2b6c"),
    Color("#692b6c"), Color("#682a6c"), Color("#672a6b"), Color("#662a6b"), Color("#652a6b"), Color("#642a6a"),
    Color("#642a6a"), Color("#63296a"), Color("#62296a"), Color("#612969"), Color("#602969"), Color("#5f2969"),
    Color("#5e2868"), Color("#5d2868"), Color("#5c2868"), Color("#5b2867"), Color("#5a2767"), Color("#592767"),
    Color("#582766"), Color("#582766"), Color("#572766"), Color("#562666"), Color("#552665"), Color("#542665"),
    Color("#532665"), Color("#522564"), Color("#512564"), Color("#502564"), Color("#4f2463"), Color("#4f2463"),
    Color("#4e2463"), Color("#4d2463"), Color("#4c2362"), Color("#4b2362")
  },
  crest = {
    Color("#a5cd90"), Color("#a4cc90"), Color("#a3cc91"), Color("#a2cb91"), Color("#a0cb91"), Color("#9fca91"),
    Color("#9eca91"), Color("#9dc991"), Color("#9cc891"), Color("#9bc891"), Color("#9ac791"), Color("#99c791"),
    Color("#98c691"), Color("#96c691"), Color("#95c591"), Color("#94c591"), Color("#93c491"), Color("#92c491"),
    Color("#91c391"), Color("#90c391"), Color("#8fc291"), Color("#8ec291"), Color("#8dc191"), Color("#8bc191"),
    Color("#8ac091"), Color("#89bf91"), Color("#88bf91"), Color("#87be91"), Color("#86be91"), Color("#85bd91"),
    Color("#84bd91"), Color("#82bc91"), Color("#81bc91"), Color("#80bb91"), Color("#7fbb91"), Color("#7eba91"),
    Color("#7dba91"), Color("#7cb991"), Color("#7bb991"), Color("#79b891"), Color("#78b891"), Color("#77b791"),
    Color("#76b791"), Color("#75b690"), Color("#74b690"), Color("#73b590"), Color("#72b490"), Color("#71b490"),
    Color("#70b390"), Color("#6fb390"), Color("#6eb290"), Color("#6db290"), Color("#6cb190"), Color("#6bb190"),
    Color("#6ab090"), Color("#69b090"), Color("#68af90"), Color("#67ae90"), Color("#66ae90"), Color("#65ad90"),
    Color("#64ad90"), Color("#63ac90"), Color("#62ac90"), Color("#62ab90"), Color("#61aa90"), Color("#60aa90"),
    Color("#5fa990"), Color("#5ea990"), Color("#5da890"), Color("#5ca890"), Color("#5ba790"), Color("#5ba690"),
    Color("#5aa690"), Color("#59a590"), Color("#58a590"), Color("#57a490"), Color("#57a490"), Color("#56a390"),
    Color("#55a290"), Color("#54a290"), Color("#53a190"), Color("#53a190"), Color("#52a090"), Color("#519f90"),
    Color("#509f90"), Color("#509e90"), Color("#4f9e90"), Color("#4e9d90"), Color("#4e9d90"), Color("#4d9c90"),
    Color("#4c9b90"), Color("#4b9b90"), Color("#4b9a8f"), Color("#4a9a8f"), Color("#49998f"), Color("#49988f"),
    Color("#48988f"), Color("#47978f"), Color("#47978f"), Color("#46968f"), Color("#45958f"), Color("#45958f"),
    Color("#44948f"), Color("#43948f"), Color("#43938f"), Color("#42928f"), Color("#41928f"), Color("#41918f"),
    Color("#40918f"), Color("#40908e"), Color("#3f8f8e"), Color("#3e8f8e"), Color("#3e8e8e"), Color("#3d8e8e"),
    Color("#3c8d8e"), Color("#3c8c8e"), Color("#3b8c8e"), Color("#3a8b8e"), Color("#3a8b8e"), Color("#398a8e"),
    Color("#388a8e"), Color("#38898e"), Color("#37888e"), Color("#37888d"), Color("#36878d"), Color("#35878d"),
    Color("#35868d"), Color("#34858d"), Color("#33858d"), Color("#33848d"), Color("#32848d"), Color("#31838d"),
    Color("#31828d"), Color("#30828d"), Color("#2f818d"), Color("#2f818d"), Color("#2e808d"), Color("#2d808c"),
    Color("#2d7f8c"), Color("#2c7e8c"), Color("#2c7e8c"), Color("#2b7d8c"), Color("#2a7d8c"), Color("#2a7c8c"),
    Color("#297b8c"), Color("#287b8c"), Color("#287a8c"), Color("#277a8c"), Color("#27798c"), Color("#26788c"),
    Color("#25788c"), Color("#25778c"), Color("#24778b"), Color("#24768b"), Color("#23758b"), Color("#23758b"),
    Color("#22748b"), Color("#22748b"), Color("#21738b"), Color("#21728b"), Color("#20728b"), Color("#20718b"),
    Color("#20718b"), Color("#1f708b"), Color("#1f6f8a"), Color("#1e6f8a"), Color("#1e6e8a"), Color("#1e6d8a"),
    Color("#1e6d8a"), Color("#1d6c8a"), Color("#1d6c8a"), Color("#1d6b8a"), Color("#1d6a8a"), Color("#1d6a8a"),
    Color("#1c6989"), Color("#1c6889"), Color("#1c6889"), Color("#1c6789"), Color("#1c6689"), Color("#1c6689"),
    Color("#1c6589"), Color("#1c6488"), Color("#1c6488"), Color("#1c6388"), Color("#1d6388"), Color("#1d6288"),
    Color("#1d6188"), Color("#1d6187"), Color("#1d6087"), Color("#1d5f87"), Color("#1d5f87"), Color("#1e5e87"),
    Color("#1e5d86"), Color("#1e5d86"), Color("#1e5c86"), Color("#1e5b86"), Color("#1f5b86"), Color("#1f5a85"),
    Color("#1f5985"), Color("#1f5985"), Color("#205885"), Color("#205784"), Color("#205784"), Color("#205684"),
    Color("#215584"), Color("#215583"), Color("#215483"), Color("#225383"), Color("#225283"), Color("#225282"),
    Color("#225182"), Color("#235082"), Color("#235081"), Color("#234f81"), Color("#244e81"), Color("#244e80"),
    Color("#244d80"), Color("#254c80"), Color("#254c7f"), Color("#254b7f"), Color("#254a7f"), Color("#26497e"),
    Color("#26497e"), Color("#26487e"), Color("#27477d"), Color("#27477d"), Color("#27467c"), Color("#27457c"),
    Color("#28457c"), Color("#28447b"), Color("#28437b"), Color("#28427a"), Color("#29427a"), Color("#29417a"),
    Color("#294079"), Color("#294079"), Color("#2a3f78"), Color("#2a3e78"), Color("#2a3d78"), Color("#2a3d77"),
    Color("#2a3c77"), Color("#2a3b76"), Color("#2b3b76"), Color("#2b3a76"), Color("#2b3975"), Color("#2b3875"),
    Color("#2b3875"), Color("#2b3774"), Color("#2b3674"), Color("#2c3574"), Color("#2c3573"), Color("#2c3473"),
    Color("#2c3373"), Color("#2c3272"), Color("#2c3172"), Color("#2c3172")
  }
}

--- (Override) Register all commands provided by this package.
--
-- Currently provides TODO
--
function package:registerCommands ()

  -- FIXME DEMO COMMANDS !!!!!!!!!!!!!!!!!

  self:registerCommand("gradientbox", function (options, content)
    if not self._hasGradientsSupport then
      SU.warn("The resilient.gradients package requires the libtexpdf outputter to create gradients.")
      SILE.process(content)
      return
    end
    local gradient = {
      name = SU.required(options, "name", "gradientbox"),
      stops = GRADIENTS.viridis,
      angle = options.angle and tonumber(options.angle) or 0,
    }
    SILE.typesetter:pushHbox({
      value = nil,
      width = SILE.types.length(math.random(5, 40) .. "em"),
      height = SILE.types.length("5em"),
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
  self:registerCommand("altgradientboxes", function (_, content)
    if not self._hasGradientsSupport then
      SU.warn("The resilient.gradients package requires the libtexpdf outputter to create gradients.")
      SILE.process(content)
      return
    end
    -- go through all preset gradients orderly
    local nbGradients = 0
    for _ in pairs(GRADIENTS) do nbGradients = nbGradients + 1 end
    for name, stops in pairs(GRADIENTS) do
      local gradient = {
        name = name,
        stops = stops,
        angle = 90,
      }
      SILE.typesetter:pushHbox({
        value = nil,
        width = SILE.types.length("80%lw") / nbGradients,
        height = SILE.types.length("25em"),
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
      SILE.call("hfill")
    end
  end)

end


package.documentation = [[\begin{document}
FIXME

\medskip
Note that gradients are only supported with SILE’s \code{libtexpdf} outputter, and are ignored otherwise.

\end{document}]]

return package
