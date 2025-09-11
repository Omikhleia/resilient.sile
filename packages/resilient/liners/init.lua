--- Some "liners" for the SILE typesetting system and re·sil·ient.
--
-- This an alternative to some commands from the "rules" package (underline, strikethrough).
-- Rough drawing is supported, using the Grail library (a dependency of the resilient collection).
--
-- FIXME TODO: Pretty repetitive code, could be refactored...
-- But early abstraction is often a bad idea, so let's wait for more use cases.
--
-- @license MIT
-- @copyright (c) 2024-2025 Omikhkeia / Didier Willis
-- @module packages.resilient.liners

local PathRenderer = require("grail.renderer")
local RoughPainter = require("grail.painters.rough")

--- Get the parameters for underlining from the current font.
-- @treturn number underlinePosition Position of the underline from the baseline
-- @treturn number underlineThickness Thickness of the underline
local function getUnderlineParameters ()
  local ot = require("core.opentype-parser")
  local fontoptions = SILE.font.loadDefaults({})
  local face = SILE.font.cache(fontoptions, SILE.shaper.getFace)
  local font = ot.parseFont(face)
  local upem = font.head.unitsPerEm
  local underlinePosition = font.post.underlinePosition / upem * fontoptions.size
  local underlineThickness = font.post.underlineThickness / upem * fontoptions.size
  return underlinePosition, underlineThickness
end

--- Get the parameters for strikethrough from the current font.
-- @treturn number yStrikeoutPosition Position of the strikethrough from the baseline
-- @treturn number yStrikeoutSize Thickness of the strikethrough
local function getStrikethroughParameters ()
  local ot = require("core.opentype-parser")
  local fontoptions = SILE.font.loadDefaults({})
  local face = SILE.font.cache(fontoptions, SILE.shaper.getFace)
  local font = ot.parseFont(face)
  local upem = font.head.unitsPerEm
  local yStrikeoutPosition = font.os2.yStrikeoutPosition / upem * fontoptions.size
  local yStrikeoutSize = font.os2.yStrikeoutSize / upem * fontoptions.size
  return yStrikeoutPosition, yStrikeoutSize
end

local metrics = require("fontmetrics")
local bsratiocache = {}

--- Compute the baseline ratio for the current font.
--
-- Based on font metrics (typographic extents).
--
-- Memoized for performance.
--
-- @treturn number Baseline ratio
local computeBaselineRatio = function ()
  local fontoptions = SILE.font.loadDefaults({})
  local bsratio = bsratiocache[SILE.font._key(fontoptions)]
  if not bsratio then
    local face = SILE.font.cache(fontoptions, SILE.shaper.getFace)
    local m = metrics.get_typographic_extents(face)
    bsratio = m.descender / (m.ascender + m.descender)
    bsratiocache[SILE.font._key(fontoptions)] = bsratio
  end
  return bsratio
end

--- The "resilient.liners" package.
--
-- Extends SILE's `packages.base`.
--
-- @type packages.resilient.liners

local base = require("packages.base")
local package = pl.class(base)
package._name = "resilient.liners"

--- (Constructor) Initialize the package.
-- @tparam table _ Package options (not used here)
function package:_init ()
  base._init(self)
end

--- (Override) Register all commands provided by this package.
function package:registerCommands ()

  self:registerCommand("resilient:liner:underline", function (options, content)
    local underlinePosition, underlineThickness = getUnderlineParameters()
    local isRough = SU.boolean(options.rough, false)

    local color
    if options.thickness and options.thickness ~= "auto" then
      underlineThickness = SU.cast("measurement", options.thickness):tonumber()
    end
    if options.color and options.color ~= "auto" then
      color = SILE.types.color(options.color)
    end

    local paintOptions = {}
    if isRough then
      paintOptions.preserveVertices = true
      paintOptions.disableMultiStroke = true
    end
    paintOptions.strokeWidth = underlineThickness
    paintOptions.stroke = color

    SILE.typesetter:liner("resilient:liner:underline", content,
      function (box, typesetter, line)
        local oldX = typesetter.frame.state.cursorX
        local Y = typesetter.frame.state.cursorY

        -- Build the content.
        -- Cursor will be moved by the actual definitive size.
        box:outputContent(typesetter, line)
        local newX = typesetter.frame.state.cursorX

        -- Output a line.
        -- NOTE: According to the OpenType specs, underlinePosition is "the suggested distance of
        -- the top of the underline from the baseline" so it seems implied that the thickness
        -- should expand downwards
        local painter = PathRenderer(isRough and RoughPainter())
        local w = (newX - oldX):tonumber()
        local path = painter:line(0, 0, w, 0, paintOptions)

        SILE.outputter:drawSVG(path,
          oldX, Y - underlinePosition + underlineThickness,
          newX - oldX, underlineThickness/2, 1)
      end
    )
  end, "Underlines some content")

  self:registerCommand("resilient:liner:strikethrough", function (options, content)
    local yStrikeoutPosition, yStrikeoutSize = getStrikethroughParameters()
    local isRough = SU.boolean(options.rough, false)

    local color
    if options.thickness and options.thickness ~= "auto" then
      yStrikeoutSize = SU.cast("measurement", options.thickness):tonumber()
    end
    if options.color and options.color ~= "auto" then
      color = SILE.types.color(options.color)
    end

    local paintOptions = {}
    if isRough then
      paintOptions.preserveVertices = true
      paintOptions.disableMultiStroke = true
    end
    paintOptions.strokeWidth = yStrikeoutSize
    paintOptions.stroke = color

    SILE.typesetter:liner("resilient:liner:strikethrough", content,
      function (box, typesetter, line)
        local oldX = typesetter.frame.state.cursorX
        local Y = typesetter.frame.state.cursorY

        -- Build the content.
        -- Cursor will be moved by the actual definitive size.
        box:outputContent(typesetter, line)
        local newX = typesetter.frame.state.cursorX

        -- Output a line.
        -- NOTE: The OpenType spec is not explicit regarding how the size
        -- (thickness) affects the position. We opt to distribute evenly
        local painter = PathRenderer(isRough and RoughPainter())
        local w = (newX - oldX):tonumber()
        local path = painter:line(0, 0, w, 0, paintOptions)

        SILE.outputter:drawSVG(path,
          oldX, Y - yStrikeoutPosition - yStrikeoutSize / 2,
          newX - oldX, - yStrikeoutSize / 2, 1)
      end
    )
  end, "Strikes out some content")

  self:registerCommand("resilient:liner:redacted", function (options, content)
    local bs = SILE.types.measurement("0.9bs"):tonumber()
    local bsratio = computeBaselineRatio()
    local isRough = SU.boolean(options.rough, false)

    -- TODO still some discrepancies with the color between rough and non-rough painter
    -- despite ptable 3.0 /!\
    local color = SILE.types.color(options.color or "black")

    local paintOptions = {}
    if isRough then
      paintOptions.preserveVertices = true
      paintOptions.fillStyle = options.fillstyle or 'solid'
    end
    paintOptions.stroke = 'none'
    paintOptions.fill = color
    paintOptions.strokeWidth = SU.cast("measurement", options.thickness or "0.5pt"):tonumber()

    SILE.typesetter:liner("resilient:liner:redacted", content,
      function (box, typesetter, line)
        local outputWidth = SU.rationWidth(box.width, box.width, line.ratio)
        local H = SU.max(box.height:tonumber(), (1 - bsratio) * bs)
        local D = SU.max(box.depth:tonumber(), bsratio * bs)
        local X = typesetter.frame.state.cursorX
        local Y = typesetter.frame.state.cursorY

        local painter = PathRenderer(isRough and RoughPainter())
        local w = outputWidth:tonumber()
        local path = painter:rectangle(0, 0, w, H + D, paintOptions)

        SILE.outputter:drawSVG(path,
          X, Y+D, outputWidth, H+D, 1)

        typesetter.frame:advanceWritingDirection(outputWidth)
      end
    )
  end)

  self:registerCommand("resilient:liner:mark", function (options, content)
    local bs = SILE.types.measurement("0.9bs"):tonumber()
    local bsratio = computeBaselineRatio()
    local isRough = SU.boolean(options.rough, false)

    -- TODO still some discrepancies with the color between rough and non-rough painter
    -- despite ptable 3.0 /!\
    local color = SILE.types.color(options.color or "yellow")

    local paintOptions = {}
    if isRough then
      paintOptions.preserveVertices = true
      paintOptions.fillStyle = options.fillstyle or 'zizag'
    end
    paintOptions.stroke = "none"
    paintOptions.fill = color
    paintOptions.strokeWidth = SU.cast("measurement", options.thickness or "0.5pt"):tonumber()

    SILE.typesetter:liner("resilient:liner:mark", content,
      function (box, typesetter, line)
        local outputWidth = SU.rationWidth(box.width, box.width, line.ratio)
        local H = SU.max(box.height:tonumber(), (1 - bsratio) * bs)
        local D = SU.max(box.depth:tonumber(), bsratio * bs)
        local X = typesetter.frame.state.cursorX
        local Y = typesetter.frame.state.cursorY

        local painter = PathRenderer(isRough and RoughPainter())
        local w = outputWidth:tonumber()
        local path = painter:rectangle(0, 0, w, H + D, paintOptions)

        SILE.outputter:drawSVG(path,
          X, Y+D, outputWidth, H+D, 1)

        box:outputContent(typesetter, line)
      end
    )
  end)

end

package.documentation = [[
\begin{document}
\use[module=packages.resilient.liners]

The \autodoc:package{resilient.liners} package provides commands to:

\begin{itemize}
\item{Underline content, \autodoc:command{\resilient:liner:underline}.}
\item{Strikethrough content, \autodoc:command{\resilient:liner:strikethrough}.}
\item{Redact content, \autodoc:command{\resilient:liner:redacted}.}
\item{Mark (highlight) content, \autodoc:command{\resilient:liner:mark}.}
\end{itemize}

These content can span multiple lines, and the decorations will be drawn accordingly.

This is \resilient:liner:underline{underlined}, \resilient:liner:underline[rough=true]{roughly underlined},
\resilient:liner:strikethrough{struck out}, \resilient:liner:strikethrough[rough=true]{roughly struck out},
\resilient:liner:redacted{redacted} (redacted), \resilient:liner:redacted[rough=true]{roughly redacted} (roughly redacted),
\resilient:liner:mark{marked}, and \resilient:liner:mark[rough=true]{roughly marked}.

These commands were designed for the \autodoc:package{resilient.style} package, where they are used to support the rendering of “decorations” in character styles.
\end{document}
]]

return package
