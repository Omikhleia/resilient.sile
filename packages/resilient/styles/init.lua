--
-- A style package for SILE
-- License: MIT
-- 2021-2023, Didier Willis
--
local base = require("packages.base")

local package = pl.class(base)
package._name = "resilient.styles"

local utils = require("resilient.utils")
local ast = require("silex.ast")
local createCommand, subContent
        = ast.createCommand, ast.subContent

function package:_init (options)
  base._init(self, options)

  self.class:loadPackage("textsubsuper")
  self.class:loadPackage("textcase")

  self.class:registerHook("finish", self.writeStyles)

  -- Numeric space (a.k.a. figure space) unit
  local numsp = SU.utf8charfromcodepoint("U+2007")
  SILE.registerUnit("nspc", {
    relative = true,
    definition = function (value)
      return value * SILE.shaper:measureChar(numsp).width
    end
  })

  -- Thin space unit, as 1/2 fixed inter-word space
  SILE.registerUnit("thsp", {
    relative = true,
    definition = function (value)
      return value * 0.5 * utils.interwordSpace()
    end
  })
  self:readStyles()
end

local YAML_INDENT = 2
local function tableToYaml (value, indent, done)
  indent = indent or 0
  done = done or {}

  if type(value) == "table" and not done[value] then
    done[value] = true -- Be sure to avoid cycles

    -- Sort keys
    local keys = {}
    for key in pairs(value) do
      keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

    -- Recursive dump
    local rep = "\n"
    for _, key in ipairs (keys) do
      local keyRep
      if type(key) == "number" then
        keyRep = key
      else
        keyRep = tostring(key)
      end
      rep = rep .. string.format(
        "%s%s:%s",
        string.rep(" ", indent),
        keyRep,
        tableToYaml(value[key], indent + YAML_INDENT, done)
      )
    end

    -- On first table level (style names), add an extra blank line for mere readabiity
    if indent == YAML_INDENT then
      rep = rep .. "\n"
    end

    done[value] = false
    return rep
  elseif type(value) == "string" then
    return string.format(" %q\n", value)
  else
    return " "..tostring(value).."\n"
  end
end

function package:readStyles ()
  local yaml = require("resilient-tinyyaml")
  local fname = SILE.masterFilename .. '-styles.yml'
  local styfile, _ = io.open(fname)
  if not styfile then
    SILE.scratch.styles.loaded = {}
    return SU.debug("resilient.styles", "No style file yet", fname)
  end

  SU.debug("resilient.styles", "Reading style file", fname)
  local doc = styfile:read("*all")
  local sty = yaml.parse(doc)
  for name, spec in pairs(sty) do
    if type(name) ~= "string" then
      SU.warn("Style file might be corrupted (containing numeric keys)")
      -- Skip those keys...
    else
      local inherit = spec.inherit
      local styledef = spec.style
      if not styledef then
        SU.warn("Style file might be corrupted (missing style specification for '" .. name .."')")
        -- Try do define some style anyway.
        self:defineStyle(name, { inherit = inherit }, {}, spec.origin or "corrupted")
      else
        SU.debug("resilient.styles", "Loading style", name)
        self:defineStyle(name, { inherit = inherit }, styledef, spec.origin)
      end
    end
  end

  -- Shallow copy, since we'll just need the keys
  SILE.scratch.styles.loaded = pl.tablex.copy(SILE.scratch.styles.specs)

  self:freezeStyles()
end

function package.writeStyles () -- NOTE: Not called as a package method (invoked from class hook)
  -- NOTE: We just want the difference on the first set level (keys as style names)
  -- Normally the styles aren't changed after "freezing" them (unless someone taps directly
  -- into the scrach variable, which would be BAD design in the general case.)
  local diffs = pl.tablex.difference(SILE.scratch.styles.specs, SILE.scratch.styles.loaded)
  local count = 0
  for _ in pairs(diffs) do
    count = count + 1
  end
  if count == 0 then
    return SU.debug("resilient.styles", "No need to write style file (no new styles)")
  end

  local stydata = tableToYaml(SILE.scratch.styles.specs)
  local fname = SILE.masterFilename .. '-styles.yml'
  SU.debug("resilient.styles", "Writing style file", fname, ":", count, "new style(s)")
  local styfile, err = io.open(fname, "w")
  if not styfile then return SU.error(err) end
  styfile:write(stydata)
  styfile:close()
end

SILE.scratch.styles = {
  state = {
    locked = false
  },
  -- Actual style specifications will go there (see defineStyle etc.)
  specs = {},
  -- Known aligns options, with the command implementing them.
  -- Users can register extra options in this table.
  alignments = {
    center = "center",
    left = "raggedright",
    right = "raggedleft",
    justify = "justified",
    -- be friendly with users...
    raggedright = "raggedright",
    raggedleft = "raggedleft",
  },
  -- Known casing options
  cases = {
    upper = "uppercase",
    lower = "lowercase",
    title = "titlecase",
  },
  -- Known skip options.
  -- Packages and classes can register custom skips there.
  skips = {
    smallskip = SILE.settings:get("plain.smallskipamount"),
    medskip = SILE.settings:get("plain.medskipamount"),
    bigskip = SILE.settings:get("plain.bigskipamount"),
  },
  -- Known position options, with the command implementing them
  -- Packages and classes can register extra options in this table.
  positions = {
    super = "textsuperscript",
    sub = "textsubscript",
  }
}

-- programmatically define a style
-- optional origin allows tracking e.g which package declared that style.
-- after styles are 'frozen', we can still define new styles but not override
-- existing styles.
function package.defineStyle (_, name, opts, styledef, origin)
  if SILE.scratch.styles.state.locked then
    if SILE.scratch.styles.specs[name] then
      return SU.debug("resilient.styles", "Styles are now frozen: ignoring redefinition for", name)
    end
    SU.debug("resilient.styles", "Defining new style", name)
  end
  SILE.scratch.styles.specs[name] = { inherit = opts.inherit, style = styledef, origin = origin }
end


-- resolve a style (incl. inherited fields)
-- NOTE: an optimization could be to cache the results...

function package:resolveStyle (name, discardable)
  local stylespec = SILE.scratch.styles.specs[name]
  if not stylespec then
    if not SU.boolean(discardable, false) then SU.error("Style '"..name.."' does not exist") end
    return {}
  end

  -- Deep merging the style specification.
  -- We need to deep copy the styles, as in some context (e.g. paragraph
  -- styles, TOC styles, enumerations styles...), we'll want to apply some
  -- default values, but without modifying the in-memory style (so it gets
  -- dumped at the end without those defauls).
  if stylespec.inherit then
    local res = self:resolveStyle(stylespec.inherit, discardable)
    utils.recursiveTableMerge(res, pl.tablex.deepcopy(stylespec.style))
    return res
  end
  return pl.tablex.deepcopy(stylespec.style)
end

function package:resolveParagraphStyle (name, discardable)
  local styledef = self:resolveStyle(name, discardable)
  -- Apply defaults
  styledef.paragraph = styledef.paragraph or {}
  styledef.paragraph.before = styledef.paragraph.before or {}
  styledef.paragraph.before.indent = SU.boolean(styledef.paragraph.before.indent, true)
  styledef.paragraph.before.vbreak = SU.boolean(styledef.paragraph.before.vbreak, true)
  styledef.paragraph.after = styledef.paragraph.after or {}
  styledef.paragraph.after.indent = SU.boolean(styledef.paragraph.after.indent, true)
  styledef.paragraph.after.vbreak = SU.boolean(styledef.paragraph.after.vbreak, true)
  return styledef
end

local function readOnly (t)
  local proxy = {}
  local mt = {
    __index = t,
    __newindex = function (_, _, _) -- mt, k, v
      SU.error("Styles are frozen at this point")
    end
  }
  setmetatable(proxy, mt)
  return proxy
end

function package.freezeStyles (_)
  SILE.scratch.styles.state.locked = true
  SILE.scratch.styles.state = readOnly(SILE.scratch.styles.state)
  SU.debug("resilient.styles", "Freezing styles")
end

function package:registerCommands ()
  self:registerCommand("style:font", function (options, content)
    local size = tonumber(options.size)
    local opts = pl.tablex.copy(options) -- shallow copy
    if size then
      SU.warn("Attempt using a font style with old relative font size '"..options.size..[['
  This feature will be deprecated when the new styling paradigm is completed.
]])
      opts.size = SILE.settings:get("font.size") + size
    end

    SILE.call("font", opts, content)
  end, "Applies a font, with additional support for relative sizes.")

  -- Very naive cascading...
  local function characterStyle (style, content, options)
    options = options or {}
    if style.properties then
      if style.properties.position and style.properties.position ~= "normal" then
        local positionCommand = SILE.scratch.styles.positions[style.properties.position]
        if not positionCommand then
          SU.error("Invalid style position '"..style.properties.position.."'")
        end
        content = createCommand(positionCommand, {}, content)
      end
      if style.properties.case and style.properties.case ~= "normal" then
        local caseCommand = SILE.scratch.styles.cases[style.properties.case]
        if not caseCommand then
          SU.error("Invalid style case '"..style.properties.case.."'")
        end
        content = createCommand(caseCommand, {}, content)
      end
    end
    if style.color then
      content = createCommand("color", { color = style.color }, content)
    end
    if style.font and SU.boolean(options.font, true) then
      content = createCommand("style:font", style.font, content)
    end
    return content
  end

  local function characterStyleNoFont (style, content)
    return characterStyle(style, content, { font = false })
  end

  local function hackSubContent(content, name)
    if type(content) == "table" then
      if content.command or content.id then
        -- We want to skip the calling content key values (id, command, etc.)
        return subContent(content)
      end
      return content
    end
    if name ~= "footnote" then -- HACK: Could not avoid function call in resilient.footnotes...
      SU.warn("Invocation of style '" .. name .. "'' with unexpected content ("
        .. type(content) ..")" .. [[

    For styles to apply correctly, the content should be an AST table.
    Some constructs may fail or generate errors later (text case, position, etc.)
]])
    end
    return content
  end

  local characterStyleFontOnly = function (style, content)
    if style.font then
      content = createCommand("style:font", style.font, content)
    end
    return content
  end

  local styleForAlignment = function (style, content, breakafter)
    if style.paragraph and style.paragraph.align then
      if style.paragraph.align then
        local alignCommand = SILE.scratch.styles.alignments[style.paragraph.align]
        if not alignCommand then
          SU.error("Invalid paragraph style alignment '"..style.paragraph.align.."'")
        end
        if not breakafter then SILE.call("novbreak") end
        SILE.typesetter:leaveHmode()
        -- Here we must apply the font, then the alignement, so that line heights are
        -- correct even on the last paragraph. But the color introduces hboxes so
        -- must be applied last, no to cause havoc with the noindent/indent and
        -- centering etc. environments
        local recontent = createCommand(alignCommand, {}, {
          characterStyleNoFont(style, content),
          not breakafter and createCommand("novbreak") or nil
        })
        if style.font then
          recontent = characterStyleFontOnly(style, recontent)
        end
        SILE.process({ recontent })
      else
        SILE.process({ characterStyle(style, content) })
        if not breakafter then SILE.call("novbreak") end
        -- NOTE: SILE.call("par") would cause a parskip to be inserted.
        -- Not really sure whether we expect this here or not.
        SILE.typesetter:leaveHmode()
      end
    else
      SILE.process({ characterStyle(style, content) })
    end
  end

  -- APPLY A CHARACTER STYLE

  self:registerCommand("style:apply", function (options, content)
    local name = SU.required(options, "name", "style:apply")
    local styledef = self:resolveStyle(name, options.discardable)

    content = hackSubContent(content, name) -- HACK: see above

    content = characterStyle(styledef, content)
    SILE.process({ content })
  end, "Applies a named character style to the content.")

  -- APPLY A PARAGRAPH STYLE

  -- Check for a preceding styling skip in the typesetter output queue.
  local function prevStyleSkipInQueue ()
    for i = #SILE.typesetter.state.outputQueue, 1, -1 do
      local n = SILE.typesetter.state.outputQueue[i]
      if n.is_vbox then return nil end
      if n.is_vglue and n._style_ then
        return n, i
      end
    end
    return nil
  end

  -- Return a cloned styling skip from the given glue.
  -- The reasons for cloning are multiple
  --  - Some glues (e.g. a medskip etc.) are always the same node but here we
  --    want to store the information about the style so we need a distinct
  --    node.
  --  - Also, being the same node implies then when made 'explicit' it applies
  --    to all subsequent use. Maybe that was on purpose, but we want to be
  --    able to control it.
  --  - We overload the output routine to add our own debug on these skips.
  local function cloneStyleSkip (vglue, id)
    local output = vglue.outputYourself
    vglue = pl.tablex.copy(vglue)
    vglue._style_ = id
    vglue.outputYourself = function (s, t, l)
      if SU.debugging("resilient.styles") then
        local X = t.frame.state.cursorX
        local Y = t.frame.state.cursorY
        local H = s.height:tonumber() + s.depth:tonumber() + s.adjustment:tonumber()
        SILE.outputter:pushColor(SILE.color("orange"))
        -- Show a box representing the skip
        SILE.outputter:drawRule(X, Y, 0.4, H)
        SILE.outputter:drawRule(X, Y, 30, 0.4)
        SILE.outputter:drawRule(X + 29.6, Y, 0.4, H)
        SILE.outputter:drawRule(X, Y + H, 30, 0.4)
        -- And show its stretch/shrink adjustment
        SILE.outputter:drawRule(X + 10, Y, 10, s.adjustment:tonumber())
        SILE.outputter:popColor()
      end
      output(s, t, l)
    end
    -- Be sure not inheriting non-discardability and explicit flag from the
    -- original glue.
    vglue.explicit = false
    vglue.discardable = true
    return SILE.nodefactory.vglue(vglue)
  end

  local function styleForBeforeSkip(name, parSty, styledef)
    local prevSkip, index = prevStyleSkipInQueue()
    local skip = parSty.before.skip
    local vglue = skip and SILE.scratch.styles.skips[skip] or SU.cast("vglue", skip)
    if prevSkip then
      -- Collapse consecutive styling skips
      if skip and prevSkip.height:tonumber() < vglue.height:tonumber() then
        SU.debug("resilient.styles", "Changing", prevSkip._style_, "consecutive skip before", name)
        vglue = cloneStyleSkip(vglue, name)
        SILE.typesetter.state.outputQueue[index] = vglue
      else
        SU.debug("resilient.styles", "Ignoring", prevSkip._style_, "consecutive skip before", name)
      end
    else
      local novbreak = not parSty.before.vbreak
      if styledef.sectioning and styledef.sectioning.settings
        and styledef.sectioning.settings and SU.boolean(styledef.sectioning.settings.goodbreak, true) then
        SU.debug("resilient.styles", "Inserting goodbreak before", name)
        SILE.call("goodbreak")
        if novbreak then
          SU.warn("Sectioning style '" .. name .. "' has inconsistent goodbreak and paragraph novbreak")
        end
      end
      if skip then
        SU.debug("resilient.styles", "Inserting skip before", name)
        if novbreak then SILE.call("novbreak") end
        vglue = cloneStyleSkip(vglue, name)
        -- Not sure here whether it should be an explicit glue or not,
        -- but it seems so to me...
        SILE.typesetter:pushVglue(vglue)
      end
      if novbreak then SILE.call("novbreak") end
    end
  end

  local function styleForAfterSkip(name, parSty)
    local prevSkip, index = prevStyleSkipInQueue()
    local skip = parSty.after.skip
    local vglue = skip and SILE.scratch.styles.skips[skip] or SU.cast("vglue", skip)
    if prevSkip then
      -- Collapse consecutive styling skips
      if skip and prevSkip.height:tonumber() < vglue.height:tonumber() then
        SU.debug("resilient.styles", "Changing", prevSkip._style_, "consecutive skip after", name)
        vglue = cloneStyleSkip(vglue, name, true, 120)
        SILE.typesetter.state.outputQueue[index] = vglue
      else
        SU.debug("resilient.styles", "Ignoring", prevSkip._style_, "consecutive skip after", name)
      end
    else
      local novbreak = not parSty.after.vbreak
      if skip then
        SU.debug("resilient.styles", "Inserting skip after", name)
        if novbreak then SILE.call("novbreak") end
        vglue = cloneStyleSkip(vglue, name, true, 30)
        -- Not an explicit glue, so it can be cancelled at the bottom of a page!
        SILE.typesetter:pushVglue(vglue)
      end
      if novbreak then SILE.call("novbreak") end
    end
  end

  self:registerCommand("style:apply:paragraph", function (options, content)
    local name = SU.required(options, "name", "style:apply:paragraph")
    local styledef = self:resolveParagraphStyle(name, options.discardable)
    local parSty = styledef.paragraph

    content = hackSubContent(content, name) -- HACK: see above

    local bb = SU.boolean(parSty.before.vbreak, true)
    if #SILE.typesetter.state.nodes then
      if not bb then
        SILE.call("novbreak")
      else
        SILE.typesetter:leaveHmode()
      end
    end

    styleForBeforeSkip(name, parSty, styledef)

    if parSty.before.indent then
      SILE.call("indent")
    else
      SILE.call("noindent")
    end

    local ba = parSty.after.vbreak
    styleForAlignment(styledef, content, ba)

    if not ba then SILE.call("novbreak") end
    -- NOTE: SILE.call("par") would cause a parskip to be inserted.
    -- Not really sure whether we expect this here or not.
    SILE.typesetter:leaveHmode()

    styleForAfterSkip(name, parSty)

    if parSty.after.indent then
      SILE.call("indent")
    else
      SILE.call("noindent")
    end
  end, "Applies a named paragraph style entirely to the content.")

  -- APPLY A NUMBER STYLE

  self:registerCommand("style:apply:number", function (options, content)
    if SU.hasContent(content) then
      SU.error("Unexpected content")
    end
    local name = SU.required(options, "name", "style:apply:number")
    local text = SU.required(options, "text", "style:apply:number")
    local styledef = self:resolveStyle(name, options.discardable)

    local numSty = styledef.numbering
    if not numSty then
      SILE.call("style:apply", { name = name }, { text })
      return -- Done (not a numbering style)
    end

    local beforetext = ""
    local aftertext = ""
    local beforekern, afterkern
    if numSty.before then
      beforetext = numSty.before.text or ""
      beforekern = numSty.before.kern and utils.castKern(numSty.before.kern)
    end
    if numSty.after then
      aftertext = numSty.after.text or ""
      afterkern = numSty.after.kern and utils.castKern(numSty.after.kern)
    end
    text = beforetext .. text .. aftertext

    -- If the kerning space is positive, it should correspond to the space inserted
    -- after the number.
    -- If negative, the text should be indented by that amount, with the
    -- number left-aligned in the available space.
    if beforekern and beforekern:tonumber() < 0 then
      -- IMPLEMENTATION NOTE
      -- SILE's behavior with a hbox occuring as very first element of a line
      -- was plain weird before v0.14.9. The width of the box was "adjusted" with
      -- respect to the parindent due to improper scoping.
      -- The fix is kept here, but should have no effect after 0.14.9.
      local hbox = SILE.typesetter:makeHbox(function ()
        SILE.call("style:apply", { name = name }, { text })
      end)
      if hbox.width < 0 then
        SU.warn("Negative hbox width should not occur any more, please report an issue")
      end
      local remainingSpace = hbox.width < 0 and -hbox.width or -beforekern:absolute() - hbox.width

      -- We want at least the space of a figure digit between the number
      -- and the text.
      if remainingSpace:tonumber() - SILE.length("1nspc"):absolute() <= 0 then
        -- It's not the case, the number goes beyond the available space.
        -- So add a fixed interword space after it.
        SILE.call("style:apply", { name = name }, { text })
        if afterkern then
          SILE.call("kern", { width = afterkern })
        end
      else
        -- It's the case, add the remaining space after the number, so
        -- everything is aligned.
        SILE.call("style:apply", { name = name }, { text })
        SILE.call("kern", { width = remainingSpace })
      end
    else
      if beforekern then
        SILE.call("kern", { width = beforekern })
      end
      SILE.call("style:apply", { name = name }, { text })
      if afterkern then
        SILE.call("kern", { width = afterkern })
      end
    end
  end, "Applies a named number style to the text argument (no content).")

  -- HARD DEPRECATIONS
  -- Considering 1.x was omikhleia-sile-packages and anything in between was
  -- a work-in-progress, we do NOT intend to maintain compatibility now
  -- that we have a much better system.

  self:registerCommand("style:define", function (_, _)
    SU.error("\\style:define is not available in resilient 2.0")
  end)

  self:registerCommand("style:redefine", function (_, _)
    SU.error("\\style:redefine is not available in resilient 2.0")
  end)

  self:registerCommand("style:show", function (_, _)
    SU.error("\\style:show is not available in resilient 2.0")
  end)
end

package.documentation = [[\begin{document}
The \autodoc:package{resilient.styles} package aims at easily defining
and invoking “styling specifications”.
It is intended to be used by other packages or classes, rather than directly—though
users might of course use the commands provided herein to apply some styling
definitions according to their needs.

\smallskip
\em{Applying a character style.}
\novbreak

To apply a character style to some content, one just has to do:

\smallskip
\quad\autodoc:command{\style:apply[name=<name>]{<content>}}

\smallskip
The command raises an error if the named style (or an inherited style) does
not exist. You can specify \autodoc:parameter{discardable=true} if you wish
it to be ignored, without error.

\smallskip
\em{Applying a number style.}
\novbreak

The command takes a string as parameter, and applies the corresponding
number style.

\smallskip
\quad\autodoc:command{\style:apply:number[name=<name>, text=<string>]}

\smallskip
\em{Applying a paragraph style.}
\novbreak

Likewise, the following command applies the whole paragraph style to its content, that is:
the skips and options applying before the content, the character style and the alignment
on the content itself, and finally the skips and options applying after it.

\smallskip
\quad\autodoc:command{\style:apply:paragraph[name=<name>]{<content>}}

\smallskip
Why a specific command, you may ask? Sometimes, one may want to just apply only the
(character) formatting specifications of a style.

\smallskip
\em{Applying the other styles.}
\novbreak

A style is a versatile concept and a powerful paradigm, but for some advanced usages it
cannot be fully generalized in a single package. The sectioning, table of contents or
enumeration styles all require support from other packages. This package just provides
them a general framework to play with. Actually we refrained for checking many things
in the style specifications, so one could possibly extend them with new concepts and
benefit from the proposed core features and simple style inheritance model.
\end{document}]]

return package
