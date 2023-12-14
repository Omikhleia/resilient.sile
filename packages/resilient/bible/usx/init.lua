--
-- USX (XML bible format) support for SILE
-- 2023, Didier Willis
-- License: MIT
--
-- EXPERIMENTAL POSSIBLY INCOMPLETE
--
local ast = require("silex.ast")
local createCommand,
      processAsStructure, trimSubContent
        = ast.createCommand,
          ast.processAsStructure, ast.trimSubContent

local base = require("packages.resilient.base")
local package = pl.class(base)
package._name = "resilient.bible.usx"

function package:_init(_)
  base._init(self)
  self:loadPackage("dropcaps")
  self:loadPackage("inputfilter")
  self.class:registerHook("endpage", function ()
    self:outputCollatedNotes()
  end)
end

function package.outputCollatedNotes (_)
  SILE.typesetNaturally(SILE.getFrame("margins"), function ()
    SILE.settings:pushState()
    SILE.settings:toplevelState()
    SILE.settings:set("current.parindent", SILE.nodefactory.glue())
    SILE.settings:set("document.parindent", SILE.nodefactory.glue())
    SILE.settings:set("document.lskip", SILE.nodefactory.glue())
    SILE.settings:set("document.rskip", SILE.nodefactory.hfillglue())
    for _, v in ipairs({
      "current.hangAfter",
      "current.hangIndent",
      "linebreak.hangAfter",
      "linebreak.hangIndent" }) do
      SILE.settings:set(v, SILE.settings.defaults[v])
    end

    SILE.call("hbox")
    SILE.call("vfill")
    SILE.call("font", { size = "9pt" }, function ()
      SILE.call("color", { color = "black" }, function ()
        -- Color hack: When the content frame splits a color item, it propagates
        -- to other frames.
        -- We enforce black, but it is fragile (introducing hboxes for color switching)
        -- so output-collated-sources must be called last here and not leave horizontal
        -- mode...
        SILE.call("output-collated-notes")
      end)
      SILE.typesetter:leaveHmode() -- leave inside the font size change.
    end)
    SILE.call("framebreak")
    SILE.settings:popState()
  end)
end

-- Last (i.e. eventually current) reference tracking:
-- Eventually filled as { book=..., chapter=..., verse=... }
local lastRef = {}

local skippedParaStyles = { -- for now...
  -- identification
  ide = true,
  -- toc
  toc = true,
  toc1 = true,
  toc2 = true,
  toc3 = true,
  toca1 = true,
  toca2 = true,
  toca3 = true,
  -- chapter content
  cd = true,
  -- introductions
  -- The people who invented this format are plain crazy...
  -- Folks, you should have used a proper XML schema, with a tag for introduction matters
  -- and just use regular paragraphs below. This schema is a madman's dream, right?
  imt = true,
  imt1 = true,
  imt2 = true,
  imt3 = true,
  imte = true,
  imte1 = true,
  imte2 = true,
  imte3 = true,
  is = true,
  is1 = true,
  is2 = true,
  is3 = true,
  ip = true,
  ipi = true,
  im = true,
  imi = true,
  ipq = true,
  imq = true,
  ipr = true,
  iq = true,
  iq1 = true,
  iq2 = true,
  iq3 = true,
  ib = true,
  ili = true,
  ili1 = true,
  ili2 = true,
  ili3 = true,
  iot = true,
  io = true,
  io1 = true,
  io2 = true,
  io3 = true,
  iex = true,
  ie = true,
  -- titles and headings
  mt2 = true, -- Erm... Should be used but comes before mt1 in the LSG
  -- The structure is not obvious in this messy format, so
  -- we skip it for now.
  mt3 = true,
  mte = true,
  mte1 = true,
  mte2 = true,
  mte3 = true,
  -- misc. unsupported...
  r = true,
  ms1 = true,
  ms2 = true,
  ms3 = true,
  mr = true,
  -- special exceptions
  usfm = true, -- not part of USX3 but used in the UGNT bible
               -- (containing 3.0... This must be a joke of some sort, right?)
}

local skippedCharStyles = {
  -- We are generating the references ourselves as we collate notes per verses.
  xo = true, -- xo (with xt content)
  fr = true, -- fr (with ft content)
}

---
-- PACKAGE COMMANDS
--
function package:registerCommands()

  local bookrefFilter = function (node, content)
    -- French will add a punctuation space before colons.
    -- We don't want that in book references, so we disable the language there.
    -- E.g. The LSG has references such as "Job 38:4"
    -- This might be poor typography though, see section 3 from the "Bible"
    -- entry in Lacroux http://www.orthotypographie.fr/volume-I/bandeau-bureau.html#Bible
    if type(node) == "table" then return node end
    local result = {}
    for token in SU.gtoke(node, "[%d+:%d+]") do
      if token.string then
        result[#result+1] = token.string
      else
        result[#result+1] = self.class.packages.inputfilter:createCommand(
          content.pos, content.col, content.lno,
          "language", { main = "und" }, token.separator
        )
      end
    end
    return result
  end

  self:registerCommand("running-headers", function (_, content)
    SILE.call("odd-running-header", {}, content)
    SILE.call("even-running-header", {}, content)
  end, "Text to appear on the top of the both pages.")

  self:registerCommand("output-collated-notes", function(_, _)
    local notes = SILE.scratch.info.thispage.collated
    if not notes or #notes == 0 then
      return
    end

    local prec
    SILE.typesetter:leaveHmode()
    for _, note in ipairs(notes) do
      if prec and note.ref == prec then
        SILE.typesetter:typeset(" ")
      else
        SILE.typesetter:leaveHmode()
        SILE.call("style:apply", { name = "usx-verseno-base" }, { note.ref .. " " })
      end
      SILE.process(note.material)
      prec = note.ref
    end
  end, "Ouputs the collated notes for the current page (should be called at end of a page)")

  self:registerCommand("collated-note", function(options, content)
    SILE.call("info", {
      category = "collated",
      value = {
        ref = options.ref,
        material = content
      }
    })
  end, "Registers a collated (by reference) note")

  self:registerCommand("save-book-title", function(_, content)
    lastRef = {
      book = content[1]
    }
  end)

  self:registerCommand("save-chapter-number", function(_, content)
    lastRef = {
      book = lastRef.book,
      chapter = content[1]
    }
  end)

  self:registerCommand("save-verse-number", function(_, content)
    lastRef = {
      book = lastRef.book,
      chapter = lastRef.chapter,
      verse = content[1]
    }
    SILE.call("hbox")
    SILE.call("info", {
      category = "references",
      value = lastRef
    })
  end)

  self:registerCommand("range-reference", function(_, _)
    local refs = SILE.scratch.info.thispage.references
    if refs and #refs > 0 then
      local first = refs[1]
      local last = refs[#refs]
      local ref
      -- BEGIN HACK FIXME
      -- Doh we are not going to guess headers if the sources are not providing them.
      -- are we? FIXME TODO messy XML schema... The case occurred in the NCL bible, on two
      -- books (EXO and JAS): this USX thing is somewhat messy, if it allows such things.
      if not first.book then first.book = "" end
      if not last.book then last.book = "" end
      -- END HACK
      if first.book == last.book then
        if first.chapter == last.chapter then
          ref = first.book .. " " .. first.chapter .. ", " .. first.verse .. "–" .. last.verse
        else
          ref = first.book .. " " .. first.chapter .. ", " .. first.verse .. " – " .. last.chapter ..
                    ", " .. last.verse
        end
      else
        ref = first.book .. " " .. first.chapter .. ", " .. first.verse .. ' – ' ..
                  last.book .. " " .. last.chapter .. ", " .. last.verse
      end
      SILE.call("uppercase", {}, {ref})
    end
  end)

  -- USX TAGS

  self:registerCommand("usx", function(_, content)
    SILE.call("running-headers", {}, {
      createCommand("range-reference")
    })
    processAsStructure(content)
  end)

  self:registerCommand("book", function(options, content)
    SILE.call("save-book-title", {}, { options.code })
    processAsStructure(content)
  end)

  self:registerCommand("chapter", function(options, _)
    SILE.call("par")
    if options.sid then
      -- Start chapter
      local n = SU.required(options, "number", "verse")
      SILE.call("save-chapter-number", {}, { n })
    end
  end)

  self:registerCommand("para", function(options, content)
    if skippedParaStyles[options.style] then return end
    if options.style == "h" then
      SILE.call("save-book-title", {}, content)
      return -- Only for headers
    end
    if options.style == "mt1" then
      SILE.call("sectioning", { style = "usx-para-mt1" }, content)
      return -- We are done for the title
    end

    -- HACK: USX files from Rob have space inconsistencies...
    -- Is this sufficient?
    local hackedContent = {}
    local prec
    for i = 1, #content do
      local current = content[i]
      local hack = type(prec) == "table" and prec.command == "verse"
      if type(current) == "string" and hack then
        hackedContent[#hackedContent+1] = current:gsub("^%s+", "")
      else
        hackedContent[#hackedContent+1] = current
      end
      prec = current
    end
    -- END HACK

    SILE.call("style:apply:paragraph", { discardable = true, name = "usx-para-" .. options.style },
      trimSubContent(hackedContent)
    )
  end)

  self:registerCommand("verse", function(options, _)
    if options.sid then -- Start verse
      SILE.call("set-counter", {
        id = "note",
        value = 0,
        display = "alpha"
      })
      local n = SU.required(options, "number", "verse")
      if tonumber(n) ~= 1 then
        SILE.call("style:apply:number", { name = "usx-verseno", text = n })
      else
        local chap = lastRef.chapter
        SILE.call("dropcap", {
          lines = 2,
          --family = "Libertinus Serif",
          features = "+pnum",
          color = "#74101c",
          join = false
        }, function()
          SILE.typesetter:typeset( chap )
          SILE.call("kern", {
            width = "0.1em"
          })
        end)
      end
      -- Doing it _after_ typesetting the number to avoid
      -- https://github.com/sile-typesetter/sile/issues/1816
      -- (And if n==1, well, we have our back covered by the "chapter")
      SILE.call("save-verse-number", {}, { n })
    end
  end)

  self:registerCommand("char", function(options, content)
    if skippedCharStyles[options.style] then return end
    if options.style == "xt" then
      content = self.class.packages.inputfilter:transformContent(content, bookrefFilter)
    end
    SILE.process(content)
  end)

  self:registerCommand("table", function(_, _)
    -- Ignore...
    -- In LSG this occurs in introductory material
  end)

  self:registerCommand("note", function(_, content)
    local ref
    -- ERM. Can we have a not outside a chapter or verse?
    if lastRef.chapter then
      ref = lastRef.chapter .. ", " .. (lastRef.verse or "@")
    else
      ref = "¤"
    end
    SILE.call("increment-counter", { id = "note" })
    local count = self.class.packages.counters:formatCounter(SILE.scratch.counters.note)
    SILE.call("style:apply:number", { name = "usx-noteno-intext", text = count })
    SILE.call("collated-note", {
      ref = ref
    }, function()
      SILE.call("style:apply:number", { name = "usx-noteno-innote", text = count })
      processAsStructure(content)
    end)
  end)

  self:registerCommand("unmatched", function(_, _)
    -- Not part of USX3, but used in some Paratext USX files
    -- Just ignore...
  end)
end

function package:registerStyles ()
  self:registerStyle("usx-para-mt1", { inherit = "sectioning-base" }, {
    font = { weight = 700, size = "1.4em" },
    color = "#74101c",
    paragraph = {  align = "center",
                   after = { skip = "35pt" },
                   before = { skip = "25pt" },
                },
    sectioning = { counter = { id = "bible", level = 1 },
                    settings = {
                      toclevel = 1,
                      open = "odd"
                    },
                 },
  })
  self:registerStyle("usx-para-s", {}, {
    font = { weight = "700" },
    color = "#74101c",
    paragraph = {
      after = {
        vbreak = false,
        skip = "smallskip"
      },
      before = {
        skip = "medskip",
        indent = false
      }
    }
  })
  self:registerStyle("usx-para-s1", { inherit = "usx-para-s" }, {})
  self:registerStyle("usx-para-s2", { inherit = "usx-para-s" }, {})
  self:registerStyle("usx-para-p", {}, {})
  self:registerStyle("usx-para-q", {}, {})
  self:registerStyle("usx-para-q1", { inherit = "usx-para-q" }, {})
  self:registerStyle("usx-para-q2", { inherit = "usx-para-q" }, {})
  self:registerStyle("usx-para-q3", { inherit = "usx-para-q" }, {})
  self:registerStyle("usx-para-qr", {}, {
    paragraph = {
      align = "right"
    }
  })
  self:registerStyle("usx-verseno-base", {}, {
    color = "#74101c",
  })
  self:registerStyle("usx-verseno", { inherit = "usx-verseno-base" }, {
    properties = {
      position = "super"
    },
    numbering = {
      after = {
        kern = "1spc"
      }
    }
  })
  self:registerStyle("usx-noteno-base", {}, {
    color = "#4682B4",
  })
  self:registerStyle("usx-noteno-intext", { inherit = "usx-noteno-base" }, {
    font = {
      style = "italic"
    },
    properties = {
      position = "super"
    },
    numbering = {
      after = {
        kern = "0.1em"
      }
    }
  })
  self:registerStyle("usx-noteno-innote", { inherit = "usx-noteno-intext" }, {
    numbering = {
      after = {
        kern = "0.5en"
      }
    }
  })
end

package.documentation = [[
\begin{document}

\end{document}]]

return package
