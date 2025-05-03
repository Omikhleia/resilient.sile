--
-- Documentation tooling for package designers.
--
-- License: GPL-3.0-or-later
--
-- Copyright (C) 2023-2025 Didier Willis
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
-- CAVEAT:
-- This is a modified version of the standard 'autodoc' package,
-- so that it works with the 'resilient' module,
-- with a rather OPINIONATED change. See HACKS comments below.
--
local createCommand, subContent = SU.ast.createCommand, SU.ast.subContent

local base = require("packages.base")

local package = pl.class(base)
package._name = "autodoc-resilient"

local theme = {
  command = "#1d4851", -- oil blue
  parameter = "#3f5218", -- some sort of dark green
  setting = "#42280e", -- some kind of dark brown
  bracketed = "#656565", -- some grey
  package = "#172557", -- saturated space blue
  note = "#525257" -- some asphalt grey hue
}

local colorWrapper = function (ctype, content)
  local color = SILE.scratch.autodoc.theme[ctype]
  if color and SILE.settings:get("autodoc.highlighting") and SILE.Commands["color"] then
    return { createCommand("color", { color = color }, subContent(content)) }
  else
    return content
  end
end

local function optionSorter (o1, o2)
  -- options are in an associative table and Lua doesn't guarantee a fixed order.
  -- To ensure we get a consistent and stable output, we make with some wild guesses here
  -- (Quick'n dirty, could be improved!), and rely on alphabetical order otherwise.
  if o1 == "src" then return true end
  if o2 == "src" then return false end
  if o1 == "name" then return true end
  if o2 == "name" then return false end
  return o1 < o2
end

local function astToDisplay (options, content)
  local result = {}
  if not content then return result end
  local seenCommandWithoutArg = false
  for i = 1, #content do
    local tree = content[i]
    if type(tree) == "string" then
      if seenCommandWithoutArg and tree:sub(1,1) ~= " " and tree:sub(1,1) ~= "{" then
        -- Touchy:
        -- There might have been a space or a {} here in the original code. The AST does
        -- not remember it, we only know we have to separate somehow the string from
        -- the previous command...
        result[#result+1] = " "
        seenCommandWithoutArg = false
      end
      if tree:sub(1, 1) == "<" and tree:sub(-1) == ">" then
        result[#result+1] = createCommand("autodoc:internal:bracketed", {}, tree:sub(2, -2))
      else
        result[#result+1] = tree
      end
    elseif tree.command then
      local cmd = SILE.Commands[tree.command]
      if not cmd and SU.boolean(options.check, true) then
        SU.error("Unexpected command '"..tree.command.."'")
      end
      result[#result+1] = "\\"
      result[#result+1] = createCommand("autodoc:code:style", { type = "command" }, tree.command)
      local sortedOpts = {}
      for k, _ in pairs(tree.options) do table.insert(sortedOpts, k) end
      table.sort(sortedOpts, optionSorter)
      if #sortedOpts > 0 then
        result[#result+1] = "["
        for iOpt, option in ipairs(sortedOpts) do
          result[#result+1] = {
            createCommand("autodoc:code:style", { type = "parameter" }, option),
            "=",
            createCommand("penalty", { penalty = 100 }), -- Quite decent to break here if need be.
            createCommand("autodoc:value", {}, tree.options[option]),
            (iOpt == #sortedOpts) and "]" or ", "
          }
        end
      end
      if (#tree >= 1) then
        result[#result+1] = {
          createCommand("penalty", { penalty = 200 }), -- Less than optimal break.
          "{",
          astToDisplay(options, tree),
          "}"
        }
      else
        seenCommandWithoutArg = true
      end
    elseif tree.id == "texlike_stuff" or tree.id == "content" or (not tree.command and not tree.id) then
      -- Due to the way it is implemented, the SILE-inputter may generate such
      -- nodes in the AST. It's poorly documented, so it's not clear why they
      -- are even kept there (esp. the "texlike_stuff"/"content" nodes),
      -- but anyhow, asfar as autodoc is concerned for presentation purposes,
      -- justrecurse into them.
      result[#result+1] = astToDisplay(options, tree)
    else
      SU.error("Unrecognized AST element, type "..type(tree))
    end
  end
  return result
end

function package:_init (options)
  base._init(self)
  self:loadPackage("inputfilter")
  self:loadPackage("rules")
  if options then pl.tablex.update(theme, options) end
  if not SILE.scratch.autodoc then
    SILE.scratch.autodoc = {
      theme = theme
    }
  end
end

function package:declareSettings ()
  SILE.settings:declare({
    parameter = "autodoc.highlighting",
    default = false,
    type = "boolean",
    help = "Whether audodoc enables syntax highlighting"
  })
end

function package:registerRawHandlers ()

  self:registerRawHandler("autodoc:codeblock", function(options, content)
    SILE.call("autodoc:codeblock", options, { content[1] }) -- Still issues with SU.ast.contentToString() witb raw content
  end)

end

function package:registerCommands ()

  -- Documenting a setting with good line-breaks
  local settingFilter = function (node, content)
    if type(node) == "table" then return node end
    local result = {}
    for token in SU.gtoke(node, "[%.]") do
      if token.string then
        result[#result+1] = token.string
      else
        result[#result+1] = token.separator
        result[#result+1] = self.class.packages.inputfilter:createCommand(
        content.pos, content.col, content.lno,
        "penalty", { penalty = 100 }
        )
      end
    end
    return result
  end

  self:registerCommand("package-documentation", function (_, content)
    local packname = content[1]
    SU.debug("autodoc", packname)
    -- BEGIN HACKS FOR MULTIPLE INSTANTION SIDE EFFECTS
    -- Sorry, I beg to differ...
    -- If the package is already loaded in the class, we have its
    -- documentation at hand without needing to reload things.
    -- If the package is not loaded, I don't think the 'partial'
    -- loading it sound, and the standard autodoc will miss the
    -- styles (and anything else we might add besides settings
    -- and commands)...
    local pkg
    if self.class.packages[packname] then
      -- Already loaded, we have it.
      SU.debug("resilient", "autodoc skips loading alreay know package", packname)
      pkg = self.class.packages[packname]
    else
      pkg = require("packages."..packname)
      -- Let's load for real.
      SU.debug("resilient", "autodoc fully loads package", packname)
      self:loadPackage(packname)
    end
    if type(pkg) ~= "table" or not pkg.documentation then
      SU.error("Undocumented package " .. packname)
    end
    -- END HACKS FOR MULTIPLE INSTANTION SIDE EFFECTS
    SILE.processString(pkg.documentation)
  end)

  self:registerCommand("autodoc:package:style", function (_, content)
    SILE.call("font", { weight = 700 }, colorWrapper("package", content))
  end)

  self:registerCommand("autodoc:code:style", function (options, content)
    -- options.type is used to distinguish the type of code element and style
    -- it accordingly: "ast", "setting", "environment" shall select the font
    -- (by default, using \code) and color, the other (lower-level in an AST)
    -- shall select only the color.
    if options.type == "ast" then
      SILE.call("code", {}, content)
    elseif options.type == "setting" then
      SILE.call("code", {}, colorWrapper(options.type, content))
    elseif options.type == "environment" then
      SILE.call("code", {}, colorWrapper("command", content))
    else
      SILE.process(colorWrapper(options.type, content))
    end
  end)

  self:registerCommand("autodoc:setting", function (options, content)
    if type(content) ~= "table" then SU.error("Expected a table content") end
    if #content ~= 1 then SU.error("Expected a single element") end
    local name = type(content[1] == "string") and content[1]
    if not name then SU.error("Unexpected setting") end
    -- Conditional existence check (can be disable is passing check=false), e.g.
    -- for settings that would be define in another context.
    if SU.boolean(options.check, true) then
      SILE.settings:get(name) -- will issue an error if unknown
    end
    -- Inserts breakpoints after dots
    local nameWithBreaks = self.class.packages.inputfilter:transformContent(content, settingFilter)

    SILE.call("autodoc:code:style", { type = "setting" }, nameWithBreaks)
  end, "Outputs a settings name in code, ensuring good line breaks and possibly checking their existence.")

  self:registerCommand("autodoc:internal:ast", function (options, content)
    if type(content) ~= "table" then SU.error("Expected a table content") end
    SILE.call("autodoc:code:style", { type = "ast" }, astToDisplay(options, content))
  end, "Outputs a nicely typeset AST (low-level command).")

  self:registerCommand("autodoc:internal:bracketed", function (_, content)
    SILE.typesetter:typeset("⟨")
    SILE.call("autodoc:code:style", { type = "bracketed" }, {
      createCommand("em", {}, subContent(content))
    })
    SILE.call("kern", { width = "0.1em" }) -- fake italic correction.
    SILE.typesetter:typeset("⟩")
  end, "Outputs a nicely formatted user-given value within <brackets>.")

  self:registerCommand("autodoc:value", function (_, content)
    local value = type(content) == "table" and content[1] or content
    if type(value) ~= "string" then SU.error("Expected a string") end

    if value:sub(1, 1) == "<" and value:sub(-1) == ">" then
      SILE.call("autodoc:internal:bracketed", {}, { value:sub(2, -2) })
    else
      if value:match("[,=]") or value:match("^ ") or value:match(" $") then
        value = ([["%s"]]):format(value)
      end
      SILE.call("autodoc:code:style", { type = "value" }, { value })
    end
  end, "Outputs a nicely formatted argument within <brackets>.")

  -- Documenting a command, benefiting from AST parsing

  self:registerCommand("autodoc:command", function (options, content)
    if type(content) ~= "table" then SU.error("Expected a table content") end
    if type(content[1]) ~= "table" then SU.error("Expected a command, got "..type(content[1]).." '"..content[1].."'") end

    SILE.call("autodoc:internal:ast", options, content)
  end, "Outputs a formatted command, possibly checking its validity.")

  -- Documenting a parameter

  self:registerCommand("autodoc:parameter", function (_, content)
    if type(content) ~= "table" then SU.error("Expected a table content") end
    if #content ~= 1 then SU.error("Expected a single element") end
    local param = type(content[1] == "string") and content[1]

    local parts = {}
    for v in string.gmatch(param, "[^=]+") do
      parts[#parts+1] = v
    end
    if #parts < 1 or #parts > 2 then SU.error("Unexpected parameter '"..param.."'") end
    SILE.call("autodoc:code:style", { type = "ast" }, {
      createCommand("autodoc:code:style", { type = "parameter" }, parts[1]),
      (#parts == 2) and {
        "=",
        createCommand("penalty", { penalty = 100 }, nil), -- Quite decent to break here if need be.
        createCommand("autodoc:value", {}, parts[2])
      } or nil
    })
  end, "Outputs a nicely presented parameter, possibly with a value.")

  -- Documenting an environment

  self:registerCommand("autodoc:environment", function (options, content)
    if type(content) ~= "table" then SU.error("Expected a table content") end
    if #content ~= 1 then SU.error("Expected a single element") end
    local name = type(content[1] == "string") and content[1]
    if not name then SU.error("Unexpected environment") end
    -- Conditional existence check
    if SU.boolean(options.check, true) then
      if not SILE.Commands[name] then SU.error("Unknown command "..name) end
    end

    SILE.call("autodoc:code:style", { type = "environment" }, { name })
  end, "Outputs a command name in code, checking its validity.")

  -- Documenting a package name

  self:registerCommand("autodoc:package", function (_, content)
    if type(content) ~= "table" then SU.error("Expected a table content") end
    if #content ~= 1 then SU.error("Expected a single element") end
    local name = type(content[1] == "string") and content[1]
    if not name then SU.error("Unexpected package name") end
    -- We cannot really check package name to exist!

    SILE.call("autodoc:package:style", {}, { name })
  end, "Outputs a package name in code, checking its validity.")

  -- Homogenizing the appearance of blocks of code

  self:registerCommand("autodoc:codeblock", function(_, content)
    SILE.call("smallskip")
    SILE.call("style:apply:paragraph", { name = "verbatim"}, content)
    SILE.call("smallskip")
  end, "Outputs its content as a standardized block of code")

  self:registerCommand("autodoc:line", function(_, _)
    SILE.call("fullrule", { thickness = "0.5pt" })
  end, "Ouputs a line used for surrounding code blocks (somewhat internal)")

  self:registerCommand("autodoc:example", function(_, content)
    -- Loosely derived from the \examplefont command from the original SILE manual...
    SILE.call("font", { family = "Cormorant Infant", size = "1.1em" }, content)
  end, "Marks content as an example (possibly typeset in a distinct font, etc.)")

  self:registerCommand("autodoc:note", function(_, content)
    -- Replacing the \note command from the original SILE manual...
    local linedimen = SILE.types.length("0.75em")
    local linethickness = SILE.types.length("0.3pt")
    local ls = SILE.settings:get("document.lskip") or SILE.types.node.glue()
    local p = SILE.settings:get("document.parindent")
    local leftindent = (p.width:absolute() + ls.width:absolute()).length -- fixed part
    local innerindent = SILE.types.measurement("1em"):absolute()
    SILE.settings:temporarily(function ()
      SILE.settings:set("document.lskip", leftindent)
      SILE.settings:set("document.rskip", SILE.types.node.glue())

      SILE.call("noindent")
      SILE.process(
        colorWrapper("note", function ()
          SILE.call("hrule", { width = linethickness, height = linethickness, depth = linedimen })
          SILE.call("hrule", { width = 3 * linedimen, height = linethickness })
          SILE.call("hfill")
          SILE.call("hrule", { width = 3 * linedimen, height = linethickness })
          SILE.call("hrule", { width = linethickness, height = linethickness, depth = linedimen })

          SILE.call("novbreak")
          SILE.settings:temporarily(function ()
            SILE.settings:set("document.lskip", SILE.types.node.glue(leftindent + innerindent))
            SILE.settings:set("document.rskip", SILE.types.node.glue(innerindent))
            SILE.call("font", { size = "0.95em", style = "italic "}, content)
            SILE.call("novbreak")
          end)

          SILE.call("noindent")
          SILE.call("hrule", { width  = linethickness, depth = linethickness, height = linedimen })
          SILE.call("hrule", { width  = 3 * linedimen, depth = linethickness })
          SILE.call("hfill")
          SILE.call("hrule", { width  = 3 * linedimen, depth = linethickness })
          SILE.call("hrule", { width  = linethickness, depth = linethickness, height  = linedimen })
          SILE.typesetter:leaveHmode()
        end)
      )
    end)
    SILE.call("smallskip")
  end, "Outputs its content as a note in a specific boxed and indented block")

end

package.documentation = [[
\begin{document}
This package extracts documentation information from other packages.
It’s used to construct the SILE manual.
Keeping package documentation in the package itself keeps the documentation near the implementation, which (in theory) makes it easy for documentation and implementation to be in sync.

For that purpose, it provides the \autodoc:command{\package-documentation{<package>}} command.

Properly documented packages should export a \code{documentation} string containing their documentation, as a SILE document.

For documenters and package authors, it also provides commands that can be used in their package documentation to present various pieces of information in a consistent way.

Setting names can be fairly long (e.g. \em{namespace.area.some-stuff\kern[width=0.1em]}).
The \autodoc:command{\autodoc:setting} command helps line-breaking them automatically at appropriate points, so that package authors do not have care about them
manually.

With the \autodoc:command{\autodoc:command} command, one can pass a simple command, or even a full commands (with parameters and arguments), without the need for escaping special characters.
This relies on SILE’s AST (abstract syntax tree) parsing, so you benefit from typing simplicity, syntax check, and even more –such as styling
\footnote{If the \autodoc:package{color} package is loaded and the \autodoc:setting{autodoc.highlighting} setting is set to true, you get syntax highlighting.}.
Moreover, for text content in parameter values or command arguments, if they are enclosed between angle brackets, they will be presented with an distinguishable style.
Just type the command as it would appear in code, and it will be nicely typeset.
It comes with a few caveats, though: parameters are not guaranteed to appear in the order you entered them and some purely syntactic sequences are just skipped and not reconstructed.
Also, it is not adapted to math-related commands.
So it comes with many benefits, but also at a cost.

The \autodoc:command{\autodoc:environment} command just takes an environment name, so basically a command, but just displays it without leading backslash.

The \autodoc:command{\autodoc:setting}, \autodoc:command{\autodoc:command} and \autodoc:command{\autodoc:environment} commands all check the validity and existence of their inputs.
Would you want to disable this feature (e.g. to refer to a setting or command defined in another package or module that might not be loaded at this point), you can set the optional parameter \autodoc:parameter{check} to false.
Note, however, that for commands, it is applied recursively to the parsed AST (so it is a all-or-none trade-off).

The \autodoc:command{\autodoc:parameter} commands takes either a parameter name, possibly with a value (which as above, may be bracketed) and typesets it in the same fashion.

The \autodoc:environment{autodoc:codeblock} environment allows typesetting a block of code in a consistent way.
This is not a true verbatim environment, and you still have to escape SILE’s special characters within it
(unless calling commands is what you really intend doing there, obviously).
For convenience, the package also provides a \code{raw} handler going by the same name, where you do not
have to escape the special characters (backslashes, braces, percents).

The \autodoc:command{\autodoc:example} marks its content as an example, possibly typeset in a different choice
of font.

The \autodoc:command{\autodoc:note} outputs its content as a note, in a dedicated framed and indented block.
\end{document}
]]

return package
