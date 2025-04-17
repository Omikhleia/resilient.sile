--
-- A minimalist SILE class for a "resumé" (CV)
-- Following the resilient styling paradigm.
--
-- 2021-2023, Didier Willis
-- License: MIT
--
-- This is indeed very minimalist :)
--
local base = require("classes.resilient.base")
local class = pl.class(base)
class._name = "resilient.resume"

local ast = SILE.utilities.ast
local createCommand, createStructuredCommand, subContent,
      extractFromTree, findInTree
        = ast.createCommand, ast.createStructuredCommand, ast.subContent,
          ast.extractFromTree, ast.findInTree

SILE.scratch.resilient = SILE.scratch.resilient or {}
SILE.scratch.resilient.resume = SILE.scratch.resilient.resume or {}

-- PAGE MASTERS AND FRAMES

-- 1. We want two page masters:
--    one for the first page, slightly higher as it doesn't need a header
--    one for subsequent pages, which will have a header repeating the user name.
-- 2. The spacing at top and bottom should be close to that on sides, so
--    vertical dimensions are based on the same pw specification.
-- 3. The footer and folio are place side-by-side to gain a bit of space.
--
class.defaultFrameset = {
  content = {
    left = "left(page) + 10%pw",
    right = "left(page) + 90%pw",
    top = "top(page) + 10%pw",
    bottom = "bottom(page)-22%pw"
  },
  folio = {
    left = "right(footer)",
    right = "right(content)",
    top = "bottom(content)+3%ph",
    bottom = "bottom(page)-10%pw"
  },
  header = { -- We don't need it, but let's define it somewhere harmless
             -- just in case.
    left = "left(content)",
    right = "right(content)",
    top = "top(content)-5%ph",
    bottom = "top(content)-2%ph"
  },
  footer = {
    left = "left(content)",
    right = "right(content)-10%pw",
    top = "bottom(content)+3%ph",
    bottom = "bottom(page)-10%pw"
  },
}

class.nextFrameset = {
  content = {
    left = "left(page) + 10%pw",
    right = "left(page) + 90%pw",
    top = "bottom(header)",
    bottom = "bottom(page)-22%pw"
  },
  folio = {
    left = "right(footer)",
    right = "right(content)",
    top = "bottom(content)+3%ph",
    bottom = "bottom(page)-10%pw"
  },
  header = {
    left = "left(content)",
    right = "right(content)",
    top = "top(page) + 10%pw",
    bottom = "10%pw + 3%ph"
  },
  footer = {
    left = "left(content)",
    right = "right(content)-10%pw",
    top = "bottom(content)+3%ph",
    bottom = "bottom(page) - 10%pw"
  },
}

function class:_init (options)
  base._init(self, options)

  self:loadPackage("color")
  self:loadPackage("rules") -- for section rules
  self:loadPackage("image") -- for the user picture
  self:loadPackage("ptable") -- for tables
  self:loadPackage("resilient.lists") -- for bullet lists
  -- Hack the default itemize styles to apply our resume-color
  -- IMPLEMENTATION NOTES
  --  - Tricky to remember: not possible in registerStyles() as the latter is
  --    invoked before the packages are loaded (so its only usage is for styles
  --    provided by the class itself)
  --  - We directly tap into the internal style specification, to add the
  --    inheritance without losing user-defined styling. That's better
  --    than redefining the style, so as to ensure the inheritance is
  --    added whatever the saved styled file says.
  SILE.scratch.styles.specs["lists-itemize-base"].inherit = "resume-color"

  self:loadPackage("masters")
  self:defineMaster({
      id = "first",
      firstContentFrame = self.firstContentFrame,
      frames = self.defaultFrameset
    })
  self:defineMaster({
      id = "next",
      firstContentFrame = self.firstContentFrame,
      frames = self.nextFrameset
    })
  if not SILE.scratch.headers then SILE.scratch.headers = {} end
  self:loadPackage("labelrefs") -- cross-reference, used to get the n/N page numbering
  self:loadPackage("resilient.headers") -- header facility

  -- override foliostyle
  -- TRICKY, TO REMEMBER: Such overrides cannot be done in registerCommands()
  self:registerCommand("foliostyle", function (_, content)
    SILE.call("hbox", {}, {}) -- for vfill to be effective
    SILE.call("vfill")
    SILE.call("raggedleft", {}, {
     content,
      "/",
      createCommand("pageref", { marker = "resilient.resume:end" })
    })
    SILE.call("eject") -- for vfill to be effective
  end)

  -- override default document.parindent, we do not want it.
  SILE.settings:set("document.parindent", SILE.types.node.glue())
end

function class:newPage ()
  -- In 0.12.5
  --   if SILE.scratch.counters.folio.value > 1 then
  --     self.switchMaster("next")
  --   end
  --   return plain.newPage(self)
  -- In 0.13/0.14, this became a shit of unclear weirdness
  -- See https://github.com/sile-typesetter/sile/issues/1544
  -- Ditching the folio numbering check as the folio is not even incremented yet (?!)
  -- Then the mess below _seems_ to work:
  base.newPage(self) -- It calls and returns self:initialFrame(), but heh...
  self:switchMaster("next")
  return self:initialFrame() -- And now this (?!)
end

function class:endPage ()
  if SILE.scratch.counters.folio.value > 1 then
    self.packages["resilient.headers"]:outputHeader(SILE.scratch.headers.content)
  end
  SILE.typesetNaturally(SILE.getFrame("footer"), function ()
    SILE.settings:pushState()
    SILE.settings:toplevelState()
    SILE.settings:set("document.parindent", SILE.types.node.glue())
    SILE.settings:set("current.parindent", SILE.types.node.glue())
    SILE.settings:set("document.lskip", SILE.types.node.glue())
    SILE.settings:set("document.rskip", SILE.types.node.glue())

    SILE.call("hbox", {}, {}) -- for vfill to be applied
    SILE.call("vfill")
    SILE.process(SILE.scratch.resilient.resume.address)
    SILE.call("eject") -- for vfill to be effective
    SILE.settings:popState()
  end)
  return base.endPage(self)
end

-- STYLES
function class:registerStyles ()
  base.registerStyles(self)

  self:registerStyle("resume-firstname", {}, {
    font = { style = "light" },
    color = "#a6a6a6"
  })
  self:registerStyle("resume-lastname", {}, {
    color = "#737373"
  })

  self:registerStyle("resume-fullname", {}, {
    font = { size = "30pt" },
    paragraph = { align = "right" }
  })

  self:registerStyle("resume-color", {}, {
    color = "#4080bf"
  }) -- a nice tint of blue

  self:registerStyle("resume-dingbats", { inherit = "resume-color" }, {
    font = { family = "Symbola", size = "0.9em" }
  })

  self:registerStyle("resume-jobrole", {}, {
    font = { weight = 600 }
  })

  self:registerStyle("resume-headline", {}, {
    font = { weight = 300, style = "italic", size = "0.9em" },
    color = "#373737",
    paragraph = { align = "center" }
  })

  self:registerStyle("resume-section", { inherit = "resume-color" }, {
    font = { size = "1.2em" }
  })

  self:registerStyle("resume-topic", {}, {
    font = { style="light", size = "0.9em" },
    paragraph = { align = "right" }
  })

  self:registerStyle("resume-description", {}, {})

  self:registerStyle("resume-contact", {}, {
    font = { style = "thin", size = "0.95em" },
    paragraph = { align = "center" }
  })

  self:registerStyle("resume-jobtitle", {}, {
    font = { size = "20pt" },
    color = "#373737",
    paragraph = { align = "center", before = { skip = "0.5cm" } }
  })

  self:registerStyle("resume-header", {}, {
    font = { size = "20pt" },
    paragraph = { align = "right" }
  })
end

-- RESUME PROCESSING

local function doEntry (rows, _, content)
  local topic = extractFromTree(content, "topic")
  local description = extractFromTree(content, "description")
  local titleRow = createStructuredCommand("row", {}, {
    createStructuredCommand("cell", { valign = "top", padding = "4pt 4pt 0 4pt" }, {
      -- We are typesetting in a different style but want proper alignment
      -- With the other style, so strut tweaking:
      createStructuredCommand("style:apply:paragraph", { name = "resume-topic" }, {
        createStructuredCommand("style:apply", { name = "resume-description" }, {
          createCommand("strut"),
        }),
        -- Then go ahead.
        subContent(topic)
      })
    }),
    createStructuredCommand("cell", { valign = "top", span = 2, padding = "4pt 4pt 0.33cm 0" }, {
      createStructuredCommand("style:apply", { name = "resume-description" }, description)
    })
  })
  for i = 0, #content do
    if type(content[i]) == "table" and content[i].command == "entry" then
      doEntry(rows, content[i].options, content[i])
    end
  end
  table.insert(rows, titleRow)
end

local doSection = function (rows, _, content)
  local title = extractFromTree(content, "title")
  local titleRow = createStructuredCommand("row", {}, {
    createStructuredCommand("cell", { valign = "bottom", padding = "4pt 4pt 0 4pt" }, {
      createStructuredCommand("style:apply", { name = "resume-section" }, {
        createCommand("hrule", { width = "100%fw", height= "1ex" })
      })
    }),
    createStructuredCommand("cell", { span = 2, padding = "4pt 4pt 0.33cm 0" }, {
      createStructuredCommand("style:apply", { name = "resume-section" }, title)
    })
  })
  table.insert(rows, titleRow)
  for i = 0, #content do
    if type(content[i]) == "table" and content[i].command == "entry" then
      doEntry(rows, content[i].options, content[i])
    end
  end
end

function class:registerCommands ()
  base.registerCommands(self)

  self:registerCommand("cv-header", function (_, content)
    SILE.scratch.headers.content = content
  end, "Text to appear at the top of the page")

  self:registerCommand("cv-footer", function (_, content)
    local closure = SILE.settings:wrap()
    SILE.scratch.resilient.resume.address = function () closure(content) end
  end, "Text to appear at the bottom of the page")

  self:registerCommand("resume", function (_  , content)
    local firstname = extractFromTree(content, "firstname") or SU.error("firstname is mandatory")
    local lastname = extractFromTree(content, "lastname") or SU.error("lastname is mandatory")
    local picture = extractFromTree(content, "picture") or SU.error("picture is mandatory")
    local contact = extractFromTree(content, "contact") or SU.error("contact is mandatory")
    local jobtitle = extractFromTree(content, "jobtitle") or SU.error("jobtitle is mandatory")
    local headline = extractFromTree(content, "headline") -- can be omitted

    SILE.call("cv-footer", {}, { contact })
    SILE.call("cv-header", {}, {
      createStructuredCommand("style:apply:paragraph", { name = "resume-header" }, {
        createStructuredCommand("style:apply", { name = "resume-firstname" }, { subContent(firstname) }),
        " ",
        createStructuredCommand("style:apply", { name = "resume-lastname" }, { subContent(lastname) })
      })
    })

    local rows = {}

    local fullnameAndPictureRow = createStructuredCommand("row", {}, {
      createStructuredCommand("cell", { border = "0 1pt 0 0", padding = "4pt 4pt 0 4pt", valign = "bottom" }, { function ()
          local w = SILE.types.measurement("100%fw"):absolute() - 7.2 -- padding and border
          SILE.call("parbox", { width = w, border = "0.6pt", padding = "3pt" }, function ()
            SILE.call("img", { width = "100%fw", src = picture.options.src })
          end)
        end
      }),
      createStructuredCommand("cell", { span = 2, border = "0 1pt 0 0", padding = "4pt 2pt 4pt 0",  valign = "bottom" }, {
        createStructuredCommand("style:apply:paragraph", { name = "resume-fullname" }, {
          createStructuredCommand("style:apply", { name = "resume-firstname" }, { subContent(firstname) }),
          " ",
          createStructuredCommand("style:apply", { name = "resume-lastname" }, { subContent(lastname) })
         })
      })
    })
    table.insert(rows, fullnameAndPictureRow)

    local jobtitleRow = createStructuredCommand("row", {}, {
      createStructuredCommand("cell", { span = 3 }, {
        createStructuredCommand("style:apply:paragraph", { name = "resume-jobtitle" }, jobtitle)
      })
    })
    table.insert(rows, jobtitleRow)

    -- NOTE: if headline is absent, no problem. We still insert a row, just for
    -- vertical spacing.
    local headlineRow = createStructuredCommand("row", {}, {
      createStructuredCommand("cell", { span = 3 }, { function ()
          SILE.call("center", {}, function ()
            SILE.call("parbox", { width = "80%fw" }, function()
              SILE.call("style:apply:paragraph", { name = "resume-headline" }, headline)
            end)
          end)
        end
      })
    })
    table.insert(rows, headlineRow)

    for i = 0, #content do
      if type(content[i]) == "table" and content[i].command == "section" then
        doSection(rows, content[i].options, content[i])
      end
      -- We should error/warn upon other commands or non-space text content.
    end

    -- NOTE: All the above was made with 4 columns in mind, I ended up using only
    -- three, with appropriate spanning. I had a more complex layout in mind. To refactor or extend...
    SILE.call("ptable", { cols = "17%fw 43%fw 40%fw", cellborder = 0, cellpadding = "4pt 4pt 4pt 4pt" },
      rows
    )

    -- An overkill? To get the number of pages, we insert a cross-reference label
    -- at the end of the resume table. Might not even be right if the user
    -- adds free text after it. Oh well, it will do for now.
    SILE.call("label", { marker = "resilient.resume:end" })
    SILE.call("hbox", {}, {}) -- For some reason if the label is the last thing on the page,
                              -- the info node is not there.
  end)

  local charFromUnicode = function (str)
    local hex = (str:match("[Uu]%+(%x+)") or str:match("0[xX](%x+)"))
    if hex then
      return luautf8.char(tonumber("0x"..hex))
    end
    return "*"
  end

  self:registerCommand("ranking", function (options, _)
    local value = SU.cast("integer", options.value or 0)
    local scale = SU.cast("integer", options.scale or 5)
    local rank = {}
    for i = 1, scale do
      rank[#rank + 1] = i <= value and charFromUnicode("U+25CF") or charFromUnicode("U+25CB")
      rank[#rank + 1] = createCommand("kern", { width = "0.1em" })
    end
    SILE.call("style:apply", { name = "resume-dingbats" }, rank)
  end)

  self:registerCommand("cv-bullet", function (_, _)
    SILE.call("kern", { width = "0.75em" })
    SILE.call("style:apply", { name = "resume-dingbats" }, { charFromUnicode("U+2022") })
    SILE.call("kern", { width = "0.75em" })
  end)

  self:registerCommand("cv-dingbat", function (options, _)
    local symb = SU.required(options, "symbol", "cv-dingbat")
    SILE.call("style:apply", { name = "resume-dingbats" }, { charFromUnicode(symb) })
  end)

  self:registerCommand("contact", function (_, content)
    local street = findInTree(content, "street") or SU.error("street is mandatory")
    local city = findInTree(content, "city") or SU.error("city is mandatory")
    local phone = findInTree(content, "phone") or SU.error("phone is mandatory")
    local email = findInTree(content, "email") or SU.error("email is mandatory")

    SILE.call("style:apply:paragraph", { name = "resume-contact" }, {
      createStructuredCommand("cv-icon-text", { symbol="U+1F4CD" }, { subContent(street) }),
      createCommand("cv-bullet"),
      subContent(city),
      createCommand("par"),
      phone,
      createCommand("cv-bullet"),
      email
    })
  end)

  self:registerCommand("cv-icon-text", function (options, content)
    SILE.call("cv-dingbat", options)
    SILE.call("kern", { width = "1.5spc" })
    SILE.process(content)
  end)

  self:registerCommand("email", function (options, content)
    local symbol = options.symbol or "U+1F4E7"
    SILE.call("cv-icon-text", { symbol = symbol }, content)
  end)
  self:registerCommand("phone", function (options, content)
    local symbol = options.symbol or "U+2706"
    SILE.call("cv-icon-text", { symbol = symbol }, content)
  end)

  self:registerCommand("jobrole", function (_, content)
    SILE.call("style:apply", { name = "resume-jobrole" }, content)
  end)
end

return class
