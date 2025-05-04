--
-- Some minimal subset of common "Plain TeX"-like commands.
-- Extracted from SILE's plain class and moved into a package.
--
local base = require("packages.base")
local package = pl.class(base)
package._name = "resilient.plain"

local skips = {
  small = "3pt plus 1pt minus 1pt",
  med = "6pt plus 2pt minus 2pt",
  big = "12pt plus 4pt minus 4pt",
}

function package:_init (options)
  base._init(self, options)
end

function package:declareSettings ()
  for k, v in pairs(skips) do
    SILE.settings:declare({
      parameter = "plain." .. k .. "skipamount",
      type = "vglue",
      default = SILE.types.node.vglue(v),
      help = "The amount of a \\" .. k .. "skip",
    })
  end
end

function package:registerCommands ()
  self:registerCommand("noindent", function (_, content)
    if #SILE.typesetter.state.nodes ~= 0 then
      SU.warn([[
        \noindent was called after paragraph content has already been processed

        This will not result in avoiding the current paragraph being indented. This
        function must be called before any content belonging to the paragraph is
        processed. If the intent was to suppress indentation of a following paragraph,
        first explicitly close the current paragraph. From an input document this is
        typically done with an empty line between paragraphs, but calling the \par
        command explicitly or from Lua code running SILE.call("par") will end
        the current paragraph.
      ]])
    end
    SILE.settings:set("current.parindent", SILE.types.node.glue())
    SILE.process(content)
  end, "Do not add an indent to the start of this paragraph")

  self:registerCommand("neverindent", function (_, content)
    SILE.settings:set("current.parindent", SILE.types.node.glue())
    SILE.settings:set("document.parindent", SILE.types.node.glue())
    SILE.process(content)
  end, "Turn off all indentation")

  self:registerCommand("indent", function (_, content)
    SILE.settings:set("current.parindent", SILE.settings:get("document.parindent"))
    SILE.process(content)
  end, "Do add an indent to the start of this paragraph, even if previously told otherwise")

  for k, _ in pairs(skips) do
    self:registerCommand(k .. "skip", function (_, _)
      SILE.typesetter:leaveHmode()
      SILE.typesetter:pushExplicitVglue(SILE.settings:get("plain." .. k .. "skipamount"))
    end, "Skip vertically by a " .. k .. " amount")
  end

  self:registerCommand("hfill", function (_, _)
    SILE.typesetter:pushExplicitGlue(SILE.types.node.hfillglue())
  end, "Add a huge horizontal glue")

  self:registerCommand("vfill", function (_, _)
    SILE.typesetter:leaveHmode()
    SILE.typesetter:pushExplicitVglue(SILE.types.node.vfillglue())
  end, "Add huge vertical glue")

  self:registerCommand("hss", function (_, _)
    SILE.typesetter:pushGlue(SILE.types.node.hssglue())
    table.insert(SILE.typesetter.state.nodes, SILE.types.node.zerohbox())
  end, "Add glue which stretches and shrinks horizontally (good for centering)")

  self:registerCommand("vss", function (_, _)
    SILE.typesetter:pushExplicitVglue(SILE.types.node.vssglue())
  end, "Add glue which stretches and shrinks vertically")

  local _thinspacewidth = SILE.types.measurement(0.16667, "em")

  self:registerCommand("thinspace", function (_, _)
    SILE.call("glue", { width = _thinspacewidth })
  end)

  self:registerCommand("negthinspace", function (_, _)
    SILE.call("glue", { width = -_thinspacewidth })
  end)

  self:registerCommand("enspace", function (_, _)
    SILE.call("glue", { width = SILE.types.measurement(1, "en") })
  end)

  self:registerCommand("enskip", function (_, _)
    SILE.call("enspace")
  end)

  local _quadwidth = SILE.types.measurement(1, "em")

  self:registerCommand("quad", function (_, _)
    SILE.call("glue", { width = _quadwidth })
  end)

  self:registerCommand("qquad", function (_, _)
    SILE.call("glue", { width = _quadwidth * 2 })
  end)

  self:registerCommand("slash", function (_, _)
    SILE.typesetter:typeset("/")
    SILE.call("penalty", { penalty = 50 })
  end)

  self:registerCommand("break", function (_, _)
    SILE.call("penalty", { penalty = -10000 })
  end, "Requests a frame break (if in vertical mode) or a line break (if in horizontal mode)")

  self:registerCommand("cr", function (_, _)
    SILE.call("hfill")
    SILE.call("break")
  end, "Fills a line with a stretchable glue and then requests a line break")

  -- Despite their name, in older versions, \framebreak and \pagebreak worked badly in horizontal
  -- mode. The former was a linebreak, and the latter did nothing. That was surely not intended.
  -- There are many ways, though to assume what's wrong or what the user's intent ought to be.
  -- We now warn, and terminate the paragraph, but to all extents this might be a wrong approach to
  -- reconsider at some point.

  self:registerCommand("framebreak", function (_, _)
    if not SILE.typesetter:vmode() then
      SU.warn([[
        \\framebreak was not intended to work in horizontal mode

        Behavior may change in future versions.
      ]])
    end
    SILE.call("penalty", { penalty = -10000, vertical = true })
  end, "Requests a frame break (switching to vertical mode if needed)")

  self:registerCommand("pagebreak", function (_, _)
    if not SILE.typesetter:vmode() then
      SU.warn([[
        \\pagebreak was not intended to work in horizontal mode

        Behavior may change in future versions.
      ]])
    end
    SILE.call("penalty", { penalty = -20000, vertical = true })
  end, "Requests a non-negotiable page break (switching to vertical mode if needed)")

  self:registerCommand("nobreak", function (_, _)
    SILE.call("penalty", { penalty = 10000 })
  end, "Inhibits a frame break (if in vertical mode) or a line break (if in horizontal mode)")

  self:registerCommand("novbreak", function (_, _)
    SILE.call("penalty", { penalty = 10000, vertical = true })
  end, "Inhibits a frame break (switching to vertical mode if needed)")

  self:registerCommand("allowbreak", function (_, _)
    SILE.call("penalty", { penalty = 0 })
  end, "Allows a page break (if in vertical mode) or a line break (if in horizontal mode) at a point would not be considered as suitable for breaking")

  -- NOTE: TeX's "\goodbreak" does a \par first, so always switches to vertical mode.
  -- SILE differs here, allowing it both within a paragraph (line breaking) and between
  -- paragraphs (page breaking).
  self:registerCommand("goodbreak", function (_, _)
    SILE.call("penalty", { penalty = -500 })
  end, "Indicates a good potential point to break a frame (if in vertical mode) or a line (if in horizontal mode")

  self:registerCommand("eject", function (_, _)
    SILE.call("vfill")
    SILE.call("break")
  end, "Fills the page with stretchable vglue and then request a page break")

  self:registerCommand("supereject", function (_, _)
    SILE.call("vfill")
    SILE.call("penalty", { penalty = -20000 })
  end, "Fills the page with stretchable vglue and then requests a non-negotiable page break")

  self:registerCommand("em", function (_, content)
    local style = SILE.settings:get("font.style")
    local toggle = (style and style:lower() == "italic") and "Regular" or "Italic"
    SILE.call("font", { style = toggle }, content)
  end, "Emphasizes its contents by switching the font style to italic (or back to regular if already italic)")

  self:registerCommand("strong", function (_, content)
    SILE.call("font", { weight = 700 }, content)
  end, "Sets the font weight to bold (700)")

  self:registerCommand("nohyphenation", function (_, content)
    SILE.call("font", { language = "und" }, content)
  end)

  self:registerCommand("center", function (_, content)
    if #SILE.typesetter.state.nodes ~= 0 then
      SU.warn([[
        \\center environment started after other nodes in a paragraph

        Content may not be centered as expected.
      ]])
    end
    SILE.settings:temporarily(function ()
      local lskip = SILE.settings:get("document.lskip") or SILE.types.node.glue()
      local rskip = SILE.settings:get("document.rskip") or SILE.types.node.glue()
      SILE.settings:set("document.parindent", SILE.types.node.glue())
      SILE.settings:set("current.parindent", SILE.types.node.glue())
      SILE.settings:set("document.lskip", SILE.types.node.hfillglue(lskip.width.length))
      SILE.settings:set("document.rskip", SILE.types.node.hfillglue(rskip.width.length))
      SILE.settings:set("typesetter.parfillskip", SILE.types.node.glue())
      SILE.settings:set("document.spaceskip", SILE.types.length("1spc", 0, 0))
      SILE.process(content)
      SILE.call("par")
    end)
  end, "Typeset its contents in a centered block (keeping margins).")

  self:registerCommand("raggedright", function (_, content)
    SILE.settings:temporarily(function ()
      local lskip = SILE.settings:get("document.lskip") or SILE.types.node.glue()
      local rskip = SILE.settings:get("document.rskip") or SILE.types.node.glue()
      SILE.settings:set("document.lskip", SILE.types.node.glue(lskip.width.length))
      SILE.settings:set("document.rskip", SILE.types.node.hfillglue(rskip.width.length))
      SILE.settings:set("typesetter.parfillskip", SILE.types.node.glue())
      SILE.settings:set("document.spaceskip", SILE.types.length("1spc", 0, 0))
      SILE.process(content)
      SILE.call("par")
    end)
  end, "Typeset its contents in a left aligned block (keeping margins).")

  self:registerCommand("raggedleft", function (_, content)
    SILE.settings:temporarily(function ()
      local lskip = SILE.settings:get("document.lskip") or SILE.types.node.glue()
      local rskip = SILE.settings:get("document.rskip") or SILE.types.node.glue()
      SILE.settings:set("document.lskip", SILE.types.node.hfillglue(lskip.width.length))
      SILE.settings:set("document.rskip", SILE.types.node.glue(rskip.width.length))
      SILE.settings:set("typesetter.parfillskip", SILE.types.node.glue())
      SILE.settings:set("document.spaceskip", SILE.types.length("1spc", 0, 0))
      SILE.process(content)
      SILE.call("par")
    end)
  end, "Typeset its contents in a right aligned block (keeping margins).")

  self:registerCommand("justified", function (_, content)
    SILE.settings:temporarily(function ()
      local lskip = SILE.settings:get("document.lskip") or SILE.types.node.glue()
      local rskip = SILE.settings:get("document.rskip") or SILE.types.node.glue()
      -- Keep the fixed part of the margins for nesting but remove the stretchability.
      SILE.settings:set("document.lskip", SILE.types.node.glue(lskip.width.length))
      SILE.settings:set("document.rskip", SILE.types.node.glue(rskip.width.length))
      -- Reset parfillskip to its default value, in case the surrounding context
      -- is ragged and cancelled it.
      SILE.settings:set("typesetter.parfillskip", nil, false, true)
      SILE.settings:set("document.spaceskip", nil)
      SILE.process(content)
      SILE.call("par")
    end)
  end, "Typeset its contents in a justified block (keeping margins).")

  self:registerCommand("ragged", function (options, content)
    -- Fairly dubious command for compatibility
    local l = SU.boolean(options.left, false)
    local r = SU.boolean(options.right, false)
    if l and r then
      SILE.call("center", {}, content)
    elseif r then
      SILE.call("raggedleft", {}, content)
    elseif l then
      SILE.call("raggedright", {}, content)
    else
      SILE.call("justified", {}, content)
    end
  end)

  self:registerCommand("sloppy", function (_, _)
    SILE.settings:set("linebreak.tolerance", 9999)
  end)

  self:registerCommand("awful", function (_, _)
    SILE.settings:set("linebreak.tolerance", 10000)
  end)

  self:registerCommand("hbox", function (_, content)
    local hbox, hlist = SILE.typesetter:makeHbox(content)
    SILE.typesetter:pushHbox(hbox)
    if #hlist > 0 then
      SU.warn([[
        \\hbox has migrating content

        Ignored for now, but likely to break in future versions.
      ]])
      -- Ugly shim:
      -- One day we ought to do SILE.typesetter:pushHlist(hlist) here, so as to push
      -- back the migrating contents from within the hbox'ed content.
      -- However, old Lua code assumed the hbox to be returned, and sometimes removed it
      -- from the typesetter queue (for measuring, etc.), assuming it was the last
      -- element in the queue...
    end
    return hbox
  end, "Compiles all the enclosed horizontal-mode material into a single hbox")

  self:registerCommand("vbox", function (options, content)
    local vbox
    SILE.settings:temporarily(function ()
      if options.width then
        SILE.settings:set("typesetter.breakwidth", SILE.types.length(options.width))
      end
      SILE.typesetter:pushState()
      SILE.process(content)
      SILE.typesetter:leaveHmode(1)
      vbox = SILE.pagebuilder:collateVboxes(SILE.typesetter.state.outputQueue)
      SILE.typesetter:popState()
    end)
    return vbox
  end, "Compiles all the enclosed material into a single vbox")
end

return package
