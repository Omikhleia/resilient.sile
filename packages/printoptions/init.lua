--
-- Print options for professional printers
--
-- Requires: Inkscape and GraphicsMagick to be available on the host system.
-- Reminders: GraphicsMagick also needs Ghostscript for PDF images
-- (it delegates to it).
--
-- License: GPL-3.0-or-later
--
-- Copyright (C) 2022-2025 Didier Willis
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
package._name = "printoptions"

function package:declareSettings ()
  SILE.settings:declare({
    parameter = "printoptions.resolution",
    type = "integer or nil",
    default = nil,
    help = "If set, defines the target image resolution in DPI (dots per inch)"
  })

  SILE.settings:declare({
    parameter = "printoptions.vector.rasterize",
    type = "boolean",
    default = true,
    help = "When true and resolution is set, SVG vectors are rasterized."
  })

  SILE.settings:declare({
    parameter = "printoptions.image.flatten",
    type = "boolean",
    default = false,
    help = "When true and resolution is set, images are flattened (transparency removed)."
  })

  SILE.settings:declare({
    parameter = "printoptions.image.grayscale",
    type = "boolean",
    default = true,
    help = "When true and resolution is set, images are converted to grayscale."
  })

  SILE.settings:declare({
    parameter = "printoptions.image.tolerance",
    type = "number",
    default = 0.85,
    help = "Warning threshold for under-resolved images (percentage)."
  })
end

local function handlePath (filename)
  local basename = pl.path.basename(filename):match("(.+)%..+$")
  local ext = pl.path.extension(filename)
  if not basename or not ext then
    SU.error("Cannot split path and extension in "..filename)
  end

  local dir = pl.path.join(pl.path.dirname(SILE.masterFilename), "converted")
  if not pl.path.exists(dir) then
    pl.path.mkdir(dir)
  end
  return pl.path.join(dir, basename), ext
end

local function imageResolutionConverter (filename, widthInPx, resolution, pageno)
  local basename, ext = handlePath(filename)
  local flatten = SILE.settings:get("printoptions.image.flatten")
  local grayscale = SILE.settings:get("printoptions.image.grayscale")

  local rescale = true
  local width, _, xres = SILE.outputter:getImageSize(filename, pageno or 1)
  local actualWidthInPx
  if not xres then
    -- This may happen with PDF files used as images, for instance.
    SU.debug("printoptions", "Image doesn't have a known resolution", filename)
    actualWidthInPx = width
  else
    actualWidthInPx = width * xres / 72
  end
  if actualWidthInPx <= widthInPx then
    -- The image is already smaller than the target width.
    rescale = false
    -- Warn if the resolution is too low.
    local actualResolution = math.floor(actualWidthInPx * resolution / widthInPx)
    SU.debug("printoptions", "No resampling needed for", filename,
      actualWidthInPx.."px", "for target", widthInPx.."px")
    local threshold = SILE.settings:get("printoptions.image.tolerance")
    if actualResolution <= threshold * resolution then
      SU.warn("Image " .. filename .. " has a low resolution (" .. actualResolution .. " DPI)")
    end
  end

  if not (rescale or flatten or grayscale) then
    -- No need to convert the image.
    SU.debug("printoptions", "No conversion needed for", filename)
    return filename
  end

  local source = filename
  if pageno then
    -- Use specified page if provided (e.g. for PDF).
    source = filename .. "[" .. (pageno - 1) .. "]" -- Graphicsmagick page numbers start at 0.
    basename = pageno and basename .. "-p" .. pageno
  end

  local targetFilename = basename .. "-".. widthInPx .. "-" .. resolution
  if flatten then
    targetFilename = targetFilename .. "-flat"
  end
  if grayscale then
    targetFilename = targetFilename .. "-gray"
  end
  targetFilename = targetFilename .. ext

  local sourceTime = pl.path.getmtime(filename)
  if sourceTime == nil then
    SU.debug("printoptions", "Source file not found", filename)
    return nil
  end

  local targetTime = pl.path.getmtime(targetFilename)
  if targetTime ~= nil and targetTime > sourceTime then
    SU.debug("printoptions", "Source file already converted", filename, "=", targetFilename)
    return targetFilename
  end

  local command = {
    "gm convert",
      source ,
      "-units PixelsPerInch",
      -- disable antialiasing (best effort)
      "+antialias",
      "-filter point",
  }
  if rescale then
    pl.tablex.insertvalues(command, {
      -- resize
      "-resize "..widthInPx.."x\\>",
      "-density "..resolution,
    })
  end
  if flatten then
    pl.tablex.insertvalues(command, {
      "-background white",
      "-flatten",
    })
  end
  if grayscale then
    pl.tablex.insertvalues(command, {
      "-colorspace GRAY",
    })
  end
  command[#command + 1] = targetFilename
  command = table.concat(command, " ")

  SU.debug("printoptions", "Command:", command)
  local result = os.execute(command)
  if type(result) ~= "boolean" then result = (result == 0) end
  if result then
    SU.debug("printoptions", "Converted", filename, "to", targetFilename)
    return targetFilename
  else
    return nil
  end
end

local function svgRasterizer (filename, widthInPx, _)
  local basename, ext = handlePath(filename)
  if ext ~= ".svg" then SU.error("Expected SVG file for "..filename) end
  local wpx = widthInPx * 2 -- See further below
  local targetFilename = basename .. "-svg-"..wpx..".png"

  local sourceTime = pl.path.getmtime(filename)
  if sourceTime == nil then
    SU.debug("printoptions", "Source file not found", filename)
    return nil
  end

  local targetTime = pl.path.getmtime(targetFilename)
  if targetTime ~= nil and targetTime > sourceTime then
    SU.debug("printoptions", "Source file already converted", filename)
    return targetFilename
  end

  -- Inkscape is better than imagemagick's convert at converting a SVG...
  -- But it handles badly the resolution...
  -- Anyway, we'll just convert to PNG and let the outputter resize the image.
  local toSvg = table.concat({
    "inkscape",
    filename,
    "-w ".. wpx, -- FIXME. I could not find a proper way to disable antialiasing
                 -- So target twice the actual size, and the image conversion to
                 -- resolution will also downsize without antialiasing.
                 -- This is far from perfect, but minimizes the antialiasing a bit...
    "-o",
    targetFilename,
  }, " ")
  local result = os.execute(toSvg)
  if type(result) ~= "boolean" then result = (result == 0) end
  if result then
    SU.debug("printoptions", "Converted ", filename, "to", targetFilename)
    return targetFilename
  else
    return nil
  end
end

local drawSVG = function (filename, svgdata, width, height, density)
  -- FIXME/CAVEAT: We are reimplementing the whole logic from _drawSVG in the
  -- "svg" package, but the latter might be wrong:
  -- See https://github.com/sile-typesetter/sile/pull/1517
  local svg = require("svg")
  local svgfigure, svgwidth, svgheight = svg.svg_to_ps(svgdata, density)
  SU.debug("svg", string.format("PS: %s\n", svgfigure))
  local scalefactor = 1
  if width and height then
    -- local aspect = svgwidth / svgheight
    SU.error("SILE cannot yet change SVG aspect ratios, specify either width or height but not both")
  elseif width then
    scalefactor = width:tonumber() / svgwidth
  elseif height then
    scalefactor = height:tonumber() / svgheight
  end
  width = SILE.types.measurement(svgwidth * scalefactor)
  height = SILE.types.measurement(svgheight * scalefactor)
  scalefactor = scalefactor * density / 72

  local resolution = SILE.settings:get("printoptions.resolution")
  local rasterize = SILE.settings:get("printoptions.vector.rasterize")
  if resolution and resolution > 0 and rasterize then
    local targetWidthInPx = math.ceil(SU.cast("number", width) * resolution / 72)
    local converted = svgRasterizer(filename, targetWidthInPx, resolution)
    if converted then
      SILE.call("img", { src = converted, width = width })
      return -- We are done replacing the SVG by a raster image
    end
    SU.warn("Resolution failure for "..filename..", using original image")
  end

  SILE.typesetter:pushHbox({
    value = nil,
    height = height,
    width = width,
    depth = 0,
    outputYourself = function (self, typesetter)
      SILE.outputter:drawSVG(svgfigure, typesetter.frame.state.cursorX, typesetter.frame.state.cursorY, self.width, self.height, scalefactor)
      typesetter.frame:advanceWritingDirection(self.width)
    end
  })
end

function package:_init (pkgoptions)
  base._init(self, pkgoptions)
  self:loadPackage("image")
  -- We do this to enforce loading the \svg command now.
  -- so our version here can override it.
  self:loadPackage("svg")
  self:registerCommand("svg", function (options, _)
    local src = SU.required(options, "src", "filename")
    local filename = SILE.resolveFile(src) or SU.error("Couldn't find file "..src)
    local width = options.width and SU.cast("measurement", options.width):absolute() or nil
    local height = options.height and SU.cast("measurement", options.height):absolute() or nil
    local density = options.density or 72
    local svgfile = io.open(filename)
    local svgdata = svgfile:read("*all")
    drawSVG(filename, svgdata, width, height, density)
  end)

  local outputter = SILE.outputter.drawImage -- for override
  SILE.outputter.drawImage = function (outputterSelf, filename, x, y, width, height, pageno)
    local resolution = SILE.settings:get("printoptions.resolution")
    if resolution and resolution > 0 then
      SU.debug("printoptions", "Conversion to", resolution, "DPI for", filename)
      local targetWidthInPx = math.ceil(SU.cast("number", width) * resolution / 72)
      local converted = imageResolutionConverter(filename, targetWidthInPx, resolution, pageno)
      if converted then
        outputter(outputterSelf, converted, x, y, width, height)
        return -- We are done replacing the original image by its resampled version.
      end
      SU.warn("Resolution failure for "..filename..", using original image")
    end
    outputter(outputterSelf, filename, x, y, width, height, pageno)
  end
end

package.documentation = [[\begin{document}
The \autodoc:package{printoptions} package provides a few settings that allow tuning image resolution and vector rasterization, as often requested by professional printers and print-on-demand services.

The \autodoc:setting{printoptions.resolution} setting, when set to an integer value, defines the expected image resolution in DPI (dots per inch).
It could be set to 300 or 600 for final offset print or, say, to 150 or lower for a low-resolution PDF for reviewers and proofreaders.
Images are resampled to the target resolution (if they have a higher resolution).

If the \autodoc:setting{printoptions.image.grayscale} setting is true (its default value), resampled images are also converted to grayscale.

Under-resolved images are reported as warnings, if their resolution is below a threshold defined by the \autodoc:setting{printoptions.image.tolerance} (defaulting to 0.85, i.e. 85\% of the target resolution).

The \autodoc:setting{printoptions.vector.rasterize} setting defaults to true.
If a target image resolution is defined and this setting is left enabled, then vector images are rasterized.
It currently applies to SVG files, redefining the \autodoc:command[check=false]{\svg} command.

Converted images are all placed in a \code{converted} folder besides the master file.
Be cautious not having images with the same base filename in different folders, to avoid conflicts!

The package requires Inkscape, GraphicsMagick and Ghostscript to be available on your system.
As with anything that relies on invoking external programs on your host system, please be aware of potential security concerns.
Be very cautious with the source of the elements you include in your documents!

Moreover, if the \autodoc:setting{printoptions.image.flatten} setting is turned to true (its default being false), not only images are resampled, but they are also flattened with a white background.
You probably do not want to enable this setting for production, but it might be handy for checking things before going to print.
(Most professional printers require the whole PDF to be flattened without transparency, which is not addressed here; but the assumption is that you might check what could happen if transparency is improperly managed by your printer and/or you have layered contents incorrectly ordered.)
\end{document}]]

return package
