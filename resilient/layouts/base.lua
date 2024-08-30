--
-- Base layout class (a.k.a. default/none)
-- 2022-2023, Didier Willis
-- License: MIT
--
local layout = pl.class()

function layout:_init (_)
  self.inner = "width(page)/6"
  self.outer = "width(page)/6"
  self.head = "height(page)/6"
  self.foot = "height(page)/6"
  self.offset = "0"
end

function layout:setPaperHack (W, H)
  -- unused here but see Canonical layout
  self.W = W
  self.H = H
end

function layout:setOffset (offset)
  self.offset = offset
end

function layout:frameset ()
  local odd = {
    textblock = self:textblock(true),
    content = self:content(true),
    footnotes = self:footnotes(true),
    footer = self:footer(true),
    header = self:header(true),
    margins = self:margins(true),
    bindinggutter = self:gutter(true),
  }
  local even = {
    textblock = self:textblock(false),
    content = self:content(false),
    footnotes = self:footnotes(false),
    footer = self:footer(false),
    header = self:header(false),
    margins = self:margins(false),
    bindinggutter = self:gutter(false),
  }
  odd.folio = pl.tablex.copy(odd.footer)
  even.folio = pl.tablex.copy(even.footer)
  -- N.B. At some point we may want folio in headers, but
  -- we need to a way to "link" nofoliothispage with noheaderthispage
  -- in that case!
  return odd, even
end

function layout:textblock (isOdd)
  local left = isOdd and (self.inner .. " + " .. self.offset) or (self.outer .. " - " .. self.offset)
  local right = isOdd and (self.outer  .. " - " .. self.offset) or (self.inner  .. " + " .. self.offset)
  return {
    left = "left(page) + " .. left,
    right = "right(page) - " .. right,
    top = "top(page) + " .. self.head,
    bottom = "bottom(page) - " .. self.foot
  }
end

function layout.content (_, _)
  return {
    left = "left(textblock)",
    right = "right(textblock)",
    top = "top(textblock)",
    bottom = "top(footnotes)"
  }
end

function layout.footnotes (_, _)
  return {
    left = "left(textblock)",
    right = "right(textblock)",
    height = "0",
    bottom = "bottom(textblock)"
   }
end

-- None of the resources I consulted (Lacroux, Bringhurst, Tschichold...)
-- explain where bottom footer and headers should go, beyond generalities
-- (e.g. "close to the text block").
-- Looking at several books I own, whatever their quality (or lack of
-- thereof), none seem to show any explicit rule in that matter.
-- Hence, I decided to be a typographer on my own:
--  - Let's reserve up to 16pt for these.
--  - Let's play with a golden ratio in that approximate mix.
-- And guess what, it looks "decent" for most standard layouts and page
-- dimensions I checked. According to my tastes, at least.

function layout:footer (_)
  return {
    left = "left(textblock)",
    right = "right(textblock)",
    top = "bottom(page) - (" .. self.foot .. ") / 1.618 + 8pt",
    bottom = "top(footer) + 16pt"
  }
end

function layout:header (_)
  return {
    left = "left(textblock)",
    right = "right(textblock)",
    top = "top(page) + (" .. self.head  .. ") / 1.618 - 8pt",
    bottom = "top(header) + 16pt"
  }
end

function layout.margins (_, odd)
  return {
    left = odd and "right(textblock) + 2.5%pw" or "left(page) + 0.5in",
    right= odd and "right(page) - 0.5in" or "left(textblock) - 2.5%pw",
    top = "top(textblock)",
    bottom = "bottom(textblock)",
  }
end

function layout:gutter (isOdd)
  return {
    left = isOdd and ("left(page) + " .. self.offset) or "left(page)",
    right = isOdd and "left(page)" or ("left(page) + " .. self.offset),
    top = "top(page)",
    bottom = "bottom(page)"
  }
end

-- layout graph drawing adapter

local graphics = require("packages.framebox.graphics.renderer")
local PathRenderer = graphics.PathRenderer
local RoughPainter = graphics.RoughPainter

local function buildFrameRect (painter, frame, wratio, hratio, options)
  options = options or {}
  local path = painter:rectangle(
    frame:left():tonumber() * wratio,
    frame:top():tonumber() * hratio,
    frame:width():tonumber() * wratio,
    frame:height():tonumber() * hratio, {
      fill = options.fillcolor and SILE.types.color(options.fillcolor) or "none",
      stroke = options.strokecolor and SILE.types.color(options.strokecolor),
      preserveVertices = SU.boolean(options.preserve, true),
      disableMultiStroke = SU.boolean(options.singlestroke, true),
      strokeWidth = SU.cast("measurement", options.stroke or "0.3pt"):tonumber()
  })
  return path
end

local framesetAdapter = require("resilient.adapters.frameset")
function layout:draw (W, H, options)
  local ratio = SU.cast("number", options.ratio or 6.5)
  local rough = SU.boolean(options.rough, false)

  local oddFrameset, _ = self:frameset()
  -- Add fake page frame
  oddFrameset.page = {
    left = 0,
    top = 0,
    right = W,
    bottom = H,
  }
  local adapter = framesetAdapter(oddFrameset)
  local frames = adapter:solve()

  SILE.typesetter:pushHbox({
    width = W / ratio,
    height = H / ratio,
    depth = SILE.types.length(),
    outputYourself = function(node, typesetter, line)
      local saveX = typesetter.frame.state.cursorX
      local saveY = typesetter.frame.state.cursorY
      -- Scale to line to take into account stretch/shrinkability
      local outputWidth = node:scaledWidth(line)
      -- Force advancing to get the new cursor position
      typesetter.frame:advanceWritingDirection(outputWidth)
      local newX = typesetter.frame.state.cursorX
      -- Compute the target width, height, depth for the box
      local w = (newX - saveX):tonumber()
      local h = node.height:tonumber()
      -- Compute the page scaling ratio
      local wratio = w / frames.page:width():tonumber()
      local hratio = h / frames.page:height():tonumber()

      -- Compute and draw the PDF graphics path
      local painter = PathRenderer(rough and RoughPainter())
      local path
      path = buildFrameRect (painter, frames.bindinggutter, wratio, hratio, {
        stroke = "0.1pt",
        strokecolor = "225",
        fillcolor = "220"
      })
      SILE.outputter:drawSVG(path, saveX, saveY, w, h, 1)
      path = buildFrameRect (painter, frames.page, wratio, hratio, {
        stroke = "0.5pt",
        strokecolor = "black"
      })
      SILE.outputter:drawSVG(path, saveX, saveY, w, h, 1)
      path = buildFrameRect(painter, frames.textblock, wratio, hratio, {
        strokecolor = "black",
        fillcolor = "200"
      })
      SILE.outputter:drawSVG(path, saveX, saveY, w, h, 1)
      path = buildFrameRect(painter, frames.header, wratio, hratio, {
        strokecolor = "175"
      })
      SILE.outputter:drawSVG(path, saveX, saveY, w, h, 1)
      path = buildFrameRect(painter, frames.footer, wratio, hratio, {
        strokecolor = "175"
      })
      SILE.outputter:drawSVG(path, saveX, saveY, w, h, 1)
      path = buildFrameRect(painter, frames.margins, wratio, hratio, {
        strokecolor = "220"
      })
      SILE.outputter:drawSVG(path, saveX, saveY, w, h, 1)
    end
  })
end

return layout
