--- Book matter support (front and back covers, half-title, title pages, endpapers, etc.) for re·sil·ient.
--
-- This package is for internal use only.
-- It is used (mostly) by the "master document".
-- API is subject to change.
--
-- @license MIT
-- @copyright (c) 2023-2025 Omikhkeia / Didier Willis
-- @module packages.resilient.bookmatters

local layoutParser = require("resilient.layoutparser")
local loadkit = require("loadkit")
local templateLoader = loadkit.make_loader("djt")

--- Resolve a template and prepare an include command specification.
--
-- @tparam string template Template name (without extension)
-- @tparam table metaopts Initial options (metadata) to pass to the include command
-- @treturn table Include command options
-- @raise Error if the template cannot be found
local function getTemplateInclude (template, metaopts)
  local tpl = SILE.resolveFile("templates/" .. template .. ".djt")
              or templateLoader("templates." .. template)
  if not tpl then
    SU.error("Cannot find template '" .. template .. "'")
  end
  local spec = pl.tablex.union(metaopts, { src = tpl, format = "djot"})
  return spec
end

--- Compute a weighted color distance in 3D space.
--
-- @tparam SILE.types.color color Input color (RGB only for now)
local function weightedColorDistanceIn3D (color)
  -- Source: https://www.nbdtech.com/Blog/archive/2008/04/27/Calculating-the-Perceived-Brightness-of-a-Color.aspx
  return math.sqrt(
    (color.r * 255)^2 * 0.241
    + (color.g * 255)^2 * 0.691
    + (color.b * 255)^2 * 0.068
  )
end

--- Compute the best contrast color (black or white) for a given background color.
--
-- @tparam SILE.types.color color Input color (RGB only for now)
-- @treturn string "black" or "white"
local function contrastColor(color)
  if not color.r then
    -- Not going to bother with other color schemes for now...
    SU.error([[Background color for back cover must be in RGB.
Feel free to propose a PR to the maintainer if you want it otherwise]])
  end
  return weightedColorDistanceIn3D(color) < 130 and "white" or "black"
end

--- The "bookmatters" package.
--
-- Extends `packages.resilient.base`.
--
-- @type packages.resilient.bookmatters

local base = require("packages.resilient.base")
local package = pl.class(base)
package._name = "resilient.bookmatters"

local extraRequestedPackages = {
  "masters",
  "twoside",
  "resilient.sectioning",
  "resilient.headers"
}

--- (Constructor) Initialize the package.
--
-- @tparam table options Package options
function package:_init (options)
  base._init(self, options)

  self:loadPackage("barcodes.ean13")
  self:loadPackage("qrcode")
  self:loadPackage("background")
  self:loadPackage("parbox")
  self:loadPackage("framebox")
  -- There are other package assumptions for some commands,
  -- that we are not going to handle here (masters, resilient.headers, etc.)
  -- They ought to be already loaded by the document class, as "resilient.book",
  -- with proper hooks etc.
  -- Ensuring everything works with other classes (fully resilient-aware or
  -- not) is beyond the scope of this package.
  local missing = false
  for _, p in ipairs(extraRequestedPackages) do
    if not self.class.packages[p] then
      missing = true
    end
  end
  if missing then
    SU.error([[Book matters require packages not loaded by the current document class.
Either you are not using a resilient class, or your class lacks the appropriate
support.
Please consider using a resilient-compatible class!]])
  end

  local layout = layoutParser:match("geometry 0.5in 0.5in")
  local oddFrameset, evenFrameset = layout:frameset()
  self.class:defineMaster({
    id = "bookmatters-front-cover",
    firstContentFrame = "content",
    frames = oddFrameset
  })
  self.class:defineMaster({
    id = "bookmatters-back-cover",
    firstContentFrame = "content",
    frames = evenFrameset
  })
end

--- (Override) Register package commands.
function package:registerCommands ()

  -- Book matter support commands

  self:registerCommand("bookmatters:front-cover", function (options, _)
    local image = options.image
    local backgroundColor = options.background
    local metadata = options.metadata or {} -- Unusual: table of metadata options
    local template = options.template
    local textColor = contrastColor(SILE.types.color(backgroundColor or "white"))

    SILE.call("switch-master-one-page", { id = "bookmatters-front-cover" })
    SILE.call("hbox") -- To ensure some content
    if image then
      local src = SILE.resolveFile(image) or SU.error("Cannot find image file: " .. image)
      SILE.call("background", {
        src = src,
        allpages = false
      })
    elseif backgroundColor then
      SILE.call("background", {
        color = backgroundColor,
        allpages = false
      })
    end
    SILE.call("noheaders")
    SILE.call("nofolios")
    if template then
      SILE.call("color", { color = textColor }, function ()
        SILE.call("include", getTemplateInclude(template, metadata))
      end)
    end
    SILE.call("framebreak")
    SILE.call("set-counter", { id = "folio", value = -1 })
  end, "Create the front cover")

  self:registerCommand("bookmatters:back-cover", function (options, content)
    local image = options.image
    local metadata = options.metadata or {} -- Unusual: table of metadata options
    local backgroundColor = options.background
    local backgroundContentColor = options.bgcontent or backgroundColor
    local textColor = contrastColor(SILE.types.color(backgroundContentColor or "white"))

    SILE.call("open-on-even-page")
    SILE.call("switch-master-one-page", { id = "bookmatters-back-cover" })
    SILE.call("hbox") -- To ensure some content
    if image then
      local src = SILE.resolveFile(image) or SU.error("Cannot find image file: " .. image)
      SILE.call("background", {
        src = src,
        allpages = false
      })
      backgroundContentColor = backgroundContentColor or "white"
    elseif backgroundColor then
      SILE.call("background", {
        color = backgroundColor,
        allpages = false
      })
    end
    SILE.call("noheaders")
    SILE.call("nofolios")

    -- Lots of empirical measurements here...
    -- I'm in a hurry, but maybe some readers can propose better...
    local offset = SILE.types.measurement("15mm"):tonumber()
    local pad1 = SILE.types.measurement("0.25cm"):tonumber()
    local pad2 = 3 * pad1
    local W = SILE.types.measurement("100%fw"):tonumber() - 2 * offset - 2 * pad2
      local pbox, hlist = self.class.packages.parbox:makeParbox({
        width = W, strut="none" }, function ()
          SILE.call("style:apply", { name = "bookmatter-backcover" }, content)
       end)
    if #hlist > 0 then
      SU.error("Migrating content (footnotes, etc.) not supported in back cover")
    end
    local hBox = pbox.height:tonumber() + pbox.depth:tonumber()
    local hIsbnReserved = SILE.types.measurement("40mm"):tonumber() + offset
    local H = SILE.types.measurement("100%fh"):tonumber() - hIsbnReserved - hBox - 2 * pad2
    if H < 0 then
      SU.error("Back cover content is too large, you need to reduce it")
    end
    if hBox > 0 then
      SILE.call("skip", { height = H })
      SILE.call("noindent")
      SILE.call("kern", { width = offset })
      SILE.call("framebox", { fillcolor = backgroundContentColor, padding = pad2, borderwidth = 0 }, function ()
        SILE.call("color", { color = textColor }, function ()
          SILE.typesetter:pushHbox(pbox)
        end)
      end)
      SILE.typesetter:leaveHmode()
    else
      SILE.call("skip", { height = H + 2 * pad2 })
    end

    if metadata["meta:isbn"] then
      SILE.call("skip", { height = offset })
      SILE.call("kern", { width = SILE.types.node.hfillglue() })
      SILE.call("framebox", { fillcolor = "white", padding = pad1, borderwidth = 0 }, {
        SU.ast.createCommand("ean13", { code = metadata["meta:isbn"] }),
      })
      SILE.call("kern", { width = offset })
    end
  end, "Create the back cover")

  self:registerCommand("bookmatters:template", function (options, _)
    local recto = SU.required(options, "recto", "bookmatters:template")
    local verso = SU.required(options, "verso", "bookmatters:template")
    local metadata = options.metadata or {} -- Unusual: table of metadata options

    SILE.call("open-on-odd-page")
    SILE.call("include", getTemplateInclude(recto, metadata))
    SILE.call("noheaderthispage")
    SILE.call("nofoliothispage")
    SILE.call("framebreak")
    SILE.call("include", getTemplateInclude(verso, metadata))
    SILE.call("noheaders")
    SILE.call("nofolios")
    SILE.call("framebreak")
  end, "Create templated recto-verso pages")

  -- Book matter helpful default pseudo-styles
  -- (for easier Djot custom styling)

  self:registerCommand("noparindent", function (_, content)
    SILE.settings:temporarily(function ()
      SILE.settings:set("document.parindent", SILE.types.node.glue())
      SILE.settings:set("current.parindent", SILE.types.node.glue())
      SILE.process(content)
      SILE.call("par")
    end)
  end, "Typeset its contents without paragraph indentation.")

  SILE.scratch.styles.alignments["noparindent"] = "noparindent"

  self:registerCommand("bookmatter-ean13", function (_, content)
    local code = content[1]
    -- Markdown/Djot parser may interpret a dash between digits as smart typography for en-dash.
    -- Let's remove those.
    code = code:gsub("[–-]","")
    SILE.call("medskip")
    SILE.call("ean13", { code = code })
    SILE.call("medskip")
  end, "EAN-13 convenience for Djot custom styling")

  self:registerCommand("bookmatter-qrcode", function (_, content)
    local url = content[1]
    if not url:match("^https?://") then
      SU.warn("bookmatter-qrcode content is not a URL: " .. url .. " (skipped)")
    else
      SILE.call("href", { src = url }, function ()
        SILE.call("qrcode", { code = url })
      end)
    end
  end, "QR code convenience for Djot custom styling")

end

--- (Override) Register package styles.
function package:registerStyles ()
  -- Some default styles for (usually) the front cover
  -- (When template-generated)
  self:registerStyle("bookmatter-coverpage", {}, {
  })
  self:registerStyle("bookmatter-cover-title", { inherit = "bookmatter-coverpage" }, {
    font = {
      size = "20pt"
    },
    paragraph = {
      after = {
        skip = "5%fh"
      },
      before = {
        skip = "30%fh"
      }
    },
  })
  self:registerStyle("bookmatter-cover-subtitle", { inherit = "bookmatter-coverpage" }, {
    font = {
      size = "16pt"
    },
    paragraph = {
      after = {
        skip = "5%fh"
      }
    }
  })
  self:registerStyle("bookmatter-cover-author", { inherit = "bookmatter-coverpage" }, {
    font = {
      size = "16pt"
    },
    properties = {
      case = "upper"
    },
  })
  self:registerStyle("bookmatter-cover-publisher", { inherit = "bookmatter-coverpage" }, {
  })

  -- Some default styles for (usually) half-title page recto
  self:registerStyle("bookmatter-halftitle", {}, {
    font = {
      size = "14pt"
    },
    paragraph = {
      after = {
        skip = "5%fh"
      },
      align = "center",
      before = {
        skip = "25%fh"
      }
    },
    properties = {
      case = "upper"
    }
  })

  -- Some default styles for (usually) title page recto
  self:registerStyle("bookmatter-titlepage", {}, {
  })
  self:registerStyle("bookmatter-title", { inherit = "bookmatter-titlepage" }, {
    font = {
      size = "20pt"
    },
    paragraph = {
      after = {
        skip = "5%fh"
      },
      before = {
        skip = "30%fh"
      }
    },
  })
  self:registerStyle("bookmatter-subtitle", { inherit = "bookmatter-titlepage" }, {
    font = {
      size = "16pt"
    },
    paragraph = {
      after = {
        skip = "5%fh"
      }
    }
  })
  self:registerStyle("bookmatter-author", { inherit = "bookmatter-titlepage" }, {
    font = {
      size = "16pt"
    },
    properties = {
      case = "upper"
    },
  })
  self:registerStyle("bookmatter-publisher", { inherit = "bookmatter-titlepage" }, {
  })

  -- Styles for (usually) title page recto
  self:registerStyle("bookmatter-copyright", {}, {
    paragraph = {
      align = "noparindent"
    }
  })
  self:registerStyle("bookmatter-legal", {}, {
    font = {
      size = "0.8em"
    },
    paragraph = {
      before = {
        skip = "smallskip"
      }
    }
  })

  -- Styles for the backcover text content
  self:registerStyle("bookmatter-backcover", {}, {
    font = {
      size = "0.95em"
    },
  })
end

package.documentation = [[\begin{document}
The \autodoc:package{resilient.bookmatters} is currently for internal use only.

\end{document}]]

return package
