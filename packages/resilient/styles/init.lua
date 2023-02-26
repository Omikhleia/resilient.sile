--
-- A style package for SILE
-- License: MIT
-- 2021-2023, Didier Willis
--
local base = require("packages.base")

local package = pl.class(base)
package._name = "resilient.styles"

local hboxer = require("resilient-compat.hboxing") -- Compatibility hack/shim

local function interwordSpace ()
  return SILE.shaper:measureSpace(SILE.font.loadDefaults({}))
end

local function castKern (kern)
  if type(kern) == "string" then
    local value, rest = kern:match("^(%d*)iwsp[ ]*(.*)$")
    if value then
      if rest ~= "" then SU.error("Could not parse kern '"..kern.."'") end
      return (tonumber(value) or 1) * interwordSpace()
    end
  end
  return SU.cast("length", kern)
end

function package:_init (options)
  base._init(self, options)
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
      return value * 0.5 * interwordSpace()
    end
  })
end

-- local function table_print_value (value, indent, done)
--   indent = indent or 0
--   done = done or {}
--   if type(value) == "table" and not done [value] then
--     done [value] = true

--     local list = {}
--     for key in pairs (value) do
--       list[#list + 1] = key
--     end
--     table.sort(list, function(a, b) return tostring(a) < tostring(b) end)
--     local last = list[#list]

--     local rep = "\n"
--     local comma
--     for _, key in ipairs (list) do
--       -- if key == last then
--       --   comma = ''
--       -- else
--       --   comma = ','
--       -- end
--       local keyRep
--       if type(key) == "number" then
--         keyRep = key
--       else
--         keyRep = tostring(key) -- string.format("%q", tostring(key))
--       end
--       rep = rep .. string.format(
--         "%s%s: %s\n",
--         string.rep(" ", indent + 2),
--         keyRep,
--         table_print_value(value[key], indent + 2, done)
--        -- comma
--       )
--     end

--     --rep = rep .. string.rep(" ", indent) -- indent it
--     rep = rep .. ""

--     done[value] = false
--     return rep
--   elseif type(value) == "string" then
--     return string.format("%q", value)
--   else
--     return tostring(value)
--   end
-- end

function package.writeStyles (_)
  local stydata = pl.pretty.write(SILE.scratch.styles)
  -- table_print_value(SILE.scratch.styles.specs)
  local styfile, err = io.open(SILE.masterFilename .. '.sty', "w")
  if not styfile then return SU.error(err) end
  styfile:write(stydata)
  styfile:close()
end

SILE.scratch.styles = {
  -- Actual style specifications will go there (see defineStyle etc.)
  specs = {},
  -- Known aligns options, with the command implementing them.
  -- Users can register extra options in this table.
  alignments = {
    center = "center",
    left = "raggedright",
    right = "raggedleft",
    -- be friendly with users...
    raggedright = "raggedright",
    raggedleft = "raggedleft",
  },
  -- Known skip options.
  -- Users can add register custom skips there.
  skips = {
    smallskip = SILE.settings:get("plain.smallskipamount"),
    medskip = SILE.settings:get("plain.medskipamount"),
    bigskip = SILE.settings:get("plain.bigskipamount"),
  },
  -- Known position options, with the command implementing them
  -- Users can register extra options in this table.
  positions = {
    super = "textsuperscript",
    sub = "textsubscript",
  }
}

-- programmatically define a style
-- optional origin allows tracking e.g which package declared that style.
function package.defineStyle (_, name, opts, styledef, origin)
  SILE.scratch.styles.specs[name] = { inherit = opts.inherit, style = styledef, origin = origin }
end

-- merge two tables.
-- It turns out that pl.tablex.union does not recurse into the table,
-- so let's do it the proper way.
-- N.B. modifies t1 (and t2 wins on leaves existing in both)
local function recursiveTableMerge(t1, t2)
  for k, v in pairs(t2) do
    if (type(v) == "table") and (type(t1[k]) == "table") then
      recursiveTableMerge(t1[k], t2[k])
    else
      t1[k] = v
    end
  end
end

-- resolve a style (incl. inherited fields)

function package:resolveStyle (name, discardable)
  local stylespec = SILE.scratch.styles.specs[name]
  if not stylespec then
    if not SU.boolean(discardable, false) then SU.error("Style '"..name.."' does not exist") end
    return {}
  end

  if stylespec.inherit then
    local inherited = self:resolveStyle(stylespec.inherit, discardable)
    -- Deep merging the specification options
    local res = pl.tablex.deepcopy(inherited)
    recursiveTableMerge(res, stylespec.style)
    return res
  end
  return stylespec.style
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

-- human-readable specification for debug (text)
local function dumpOptions(options)
  local opts = {}
  for k, v in pairs(options) do
    opts[#opts+1] = k.."="..v
  end
  return table.concat(opts, ", ")
end
function package.dumpStyle (_, name)
  local stylespec = SILE.scratch.styles.specs[name]
  if not stylespec then return "(undefined)" end

  local desc = {}
  for k, v in pairs(stylespec.style) do
    desc[#desc+1] = k .. "[" .. dumpOptions(v).."]"
  end
  local textspec = table.concat(desc, ", ")
  if stylespec.inherit then
    if #textspec > 0 then
      textspec = stylespec.inherit.." > "..textspec
    else
      textspec = "< "..stylespec.inherit
    end
  end
  return textspec
end

-- local function readOnly (t)
--   local proxy = {}
--   local mt = {
--     __index = t,
--     __newindex = function (_, k, v) -- mt, k, v
--       if rawget(t, k) then
--         SU.warn("Attempt to redefine an existing style '"..k..[['
--   This feature will be deprecated when the new styling paradigm is completed.
-- ]])
--       end
--       rawset(t, k, v)
--     end
--   }
--   setmetatable(proxy, mt)
--   return proxy
-- end

function package.freezeStyles (_)
  --SILE.scratch.styles.specs = readOnly(SILE.scratch.styles.specs)
  -- Oops read only tables are not iterable...
  -- FIXME LATER
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

  self:registerCommand("style:define", function (options, content)
    local name = SU.required(options, "name", "style:define")
    if options.inherit and SILE.scratch.styles.specs[options.inherit] == nil then
      SU.error("Unknown inherited named style '" .. options.inherit .. "'.")
    end
    if options.inherit and options.inherit == options.name then
      SU.error("Named style '" .. options.name .. "' cannot inherit itself.")
    end
    SILE.scratch.styles.specs[name] = { inherit = options.inherit, style = {} }
    for i=1, #content do
      if type(content[i]) == "table" and content[i].command then
          SILE.scratch.styles.specs[name].style[content[i].command] = content[i].options
      end
    end
  end, "Defines a named style.")

  -- Very naive cascading...
  local styleForProperties = function (style, content)
    if style.properties and style.properties.position and style.properties.position ~= "normal" then
      local positionCommand = SILE.scratch.styles.positions[style.properties.position]
      if not positionCommand then
        SU.error("Invalid style position '"..style.position.position.."'")
      end
      SILE.call(positionCommand, {}, content)
    else
      SILE.process(content)
    end
  end
  local styleForColor = function (style, content)
    if style.color then
      SILE.call("color", style.color, function ()
        styleForProperties(style, content)
      end)
    else
      styleForProperties(style, content)
    end
  end
  local styleForFont = function (style, content)
    if style.font then
      SILE.call("style:font", style.font, function ()
        styleForColor(style, content)
      end)
    else
      styleForColor(style, content)
    end
  end

  local styleForSkip = function (skip, vbreak)
    local b = SU.boolean(vbreak, true)
    if skip then
      local vglue = SILE.scratch.styles.skips[skip] or SU.cast("vglue", skip)
      if not b then SILE.call("novbreak") end
      SILE.typesetter:pushExplicitVglue(vglue)
    end
    if not b then SILE.call("novbreak") end
  end

  local styleForAlignment = function (style, content, breakafter)
    if style.paragraph and style.paragraph.align then
      if style.paragraph.align and style.paragraph.align ~= "justify" then
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
        if style.font then
          SILE.call("style:font", style.font, function ()
            SILE.call(alignCommand, {}, function ()
              styleForColor(style, content)
              if not breakafter then SILE.call("novbreak") end
            end)
          end)
        else
          SILE.call(alignCommand, {}, function ()
            styleForColor(style, content)
            if not breakafter then SILE.call("novbreak") end
          end)
        end
      else
        styleForFont(style, content)
        if not breakafter then SILE.call("novbreak") end
        -- NOTE: SILE.call("par") would cause a parskip to be inserted.
        -- Not really sure whether we expect this here or not.
        SILE.typesetter:leaveHmode()
      end
    else
      styleForFont(style, content)
    end
  end


  -- APPLY A CHARACTER STYLE

  self:registerCommand("style:apply", function (options, content)
    local name = SU.required(options, "name", "style:apply")
    local styledef = self:resolveStyle(name, options.discardable)

    styleForFont(styledef, content)
  end, "Applies a named style to the content.")

  -- APPLY A PARAGRAPH STYLE

  self:registerCommand("style:apply:paragraph", function (options, content)
    local name = SU.required(options, "name", "style:apply:paragraph")
    local styledef = self:resolveParagraphStyle(name, options.discardable)
    local parSty = styledef.paragraph

    local bb = SU.boolean(parSty.before.vbreak, true)
    if #SILE.typesetter.state.nodes then
      if not bb then SILE.call("novbreak") end
      SILE.typesetter:leaveHmode()
    end

    styleForSkip(parSty.before.skip, parSty.before.vbreak)
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
    styleForSkip(parSty.after.skip, parSty.after.vbreak)
    if parSty.after.indent then
      SILE.call("indent")
    else
      SILE.call("noindent")
    end
  end, "Applies the paragraph style entirely.")

  -- NUMBER STYLE

  self:registerCommand("style:apply:number", function (options, _)
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
      beforekern = numSty.before.kern and castKern(numSty.before.kern)
    end
    if numSty.after then
      aftertext = numSty.after.text or ""
      afterkern = numSty.after.kern and castKern(numSty.after.kern)
    end
    text = beforetext .. text .. aftertext

    -- If the kerning space is positive, it should correspond to the space inserted
    -- after the number.
    -- If negative, the text should be indented by that amount, with the
    -- number left-aligned in the available space.
    if beforekern and beforekern:tonumber() < 0 then
      -- IMPLEMENTATION NOTE / HACK / FRAGILE
      -- SILE's behavior with a hbox occuring as very first element of a line
      -- is plain weird. The width of the box is "adjusted" with respect to
      -- the parindent, it seems.
      -- FIXME So we need to fix it here for the two cases (i.e.) in a text flow,
      -- and not only at the start of a paragraph!!!!
      local hbox = hboxer.makeHbox(function ()
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
  end, "Applies the number style.")

  -- STYLE REDEFINITION

  self:registerCommand("style:redefine", function (options, content)
    SU.required(options, "name", "style:redefined")

    if options.as then
      if options.as == options.name then
        SU.error("Style '" .. options.name .. "' should not be redefined as itself.")
      end

      -- Case: \style:redefine[name=style-name, as=saved-style-name]
      if SILE.scratch.styles.specs[options.as] ~= nil then
        SU.error("Style '" .. options.as .. "' would be overwritten.") -- Let's forbid it for now.
      end
      local sty = SILE.scratch.styles.specs[options.name]
      if sty == nil then
        SU.error("Style '" .. options.name .. "' does not exist!")
      end
      SILE.scratch.styles.specs[options.as] = sty

      -- Sub-case: \style:redefine[name=style-name, as=saved-style-name, inherit=true/false]{content}
      -- TODO We could accept another name in the inherit here? Use case?
      if content and (type(content) ~= "table" or #content ~= 0) then
        SILE.call("style:define", { name = options.name, inherit = SU.boolean(options.inherit, false) and options.as }, content)
      end
    elseif options.from then
      if options.from == options.name then
        SU.error("Style '" .. options.name .. "' should not be restored from itself, ignoring.")
      end

      -- Case \style:redefine[name=style-name, from=saved-style-name]
      if content and (type(content) ~= "table" or #content ~= 0) then
        SU.warn("Extraneous content in '" .. options.name .. "' is ignored.")
      end
      local sty = SILE.scratch.styles.specs[options.from]
      if sty == nil then
        SU.error("Style '" .. options.from .. "' does not exist!")
      end
      SILE.scratch.styles.specs[options.name] = sty
      SILE.scratch.styles.specs[options.from] = nil
    else
      SU.error("Style redefinition needs a 'as' or 'from' parameter.")
    end
  end, "Redefines a style saving the old version with another name, or restores it.")

  -- DEBUG OR DOCUMENTATION

  self:registerCommand("style:show", function (options, _)
    local name = SU.required(options, "name", "style:show")

    SILE.typesetter:typeset(self:dumpStyle(name))
  end, "Ouputs a textual (human-readable) description of a named style.")
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
