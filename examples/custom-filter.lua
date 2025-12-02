--- An example Lua filter for Djot.
--
-- This filter does two things in sequence:
--
--  - On both spans and strings, it re-maps some classes to custom styles.
--  - On strings only, it transforms numbers with the class "siecle" into roman numerals with a superscript "e", as per French typographic conventions.
--
-- @license MIT
-- @copyright (c) 2025 Omikhleia / Didier Willis

-- luacheck: globals djot

local CLASS2STYLE = {
  software = "Software",
  hardware = "Hardware",
}

local function classToStyle (e)
  if e.attr and e.attr['class'] then
    local styles = {}
    local classes = pl.Set(pl.stringx.split(e.attr['class']))
    for class, style in pairs(CLASS2STYLE) do
      if classes[class] then
        styles[#styles+1] = style
        classes[class] = nil
      end
    end
    if #styles > 0 then
      if #styles > 1 then
        SU.warn("Multiple styles implied by classes, using the first one '" .. styles[1] .. "'")
      end
      if e.attr['custom-style'] then
        SU.warn("Ignoring custom-style '" .. e.attr['custom-style'] .. "' because class implies style '" .. styles[1] .. "'")
      end
      e.attr['custom-style'] = styles[1]
      e.attr.class = table.concat(pl.Set.values(classes), " ") -- Unused classes are kept
    end
  end
end

local function numberToRoman (num)
  local val = { 1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1 }
  local syms = { "m", "cm", "d", "cd", "c", "xc", "l", "xl", "x", "ix", "v", "iv", "i" }
  local roman = ""
  for i = 1, #val do
    while num >= val[i] do
      num = num - val[i]
      roman = roman .. syms[i]
    end
  end
  return roman
end

return {
  -- A first filter that maps classes to custom styles on spans and strings.
  -- Ex. [Pandoc]{.software} --> equivalent to [Pandoc]{custom-style="Software"}
  {
    span = function(e)
      classToStyle(e)
    end,
    str = function(e)
      classToStyle(e)
    end,
  },
  -- A second filter that transforms numbers with the class "siecle" into small caps roman
  -- numerals with a superscript "e", as per French typographic conventions.
  -- Ex. 21{.siecle} --> equivalent to xxi{.smallcaps}^e^
  -- It somewhat specific to French, and we should rather delegate to a SILE command,
  -- but it's a good example of AST manipulation.
  {
    str = function(e)
      if e.attr and e.attr['class'] and tonumber(e.text) then
        local classes = pl.Set(pl.stringx.split(e.attr['class']))
        if not classes["siecle"] then
          return -- Nothing to do
        end
        -- Unused classes are kept
        classes["siecle"] = nil
        e.attr['class'] = table.concat(pl.Set.values(classes), " ")
        local num = tonumber(e.text)

        -- Create the roman numeral
        local century = djot.ast.new_node("str")
        century.text = numberToRoman(num)
        century.attr = djot.ast.new_attributes({ class = "smallcaps" })
        -- Create the superscript "e"
        local exp = djot.ast.new_node("str")
        exp.text = num == 1 and "er" or "e"
        -- Create the superscript node
        local super = djot.ast.new_node("superscript")
        super.children = { exp }
        -- Transform the original str node into a span
        e.tag = "span"
        e.text = nil
        e.children = { century, super }
      end
    end,
  }
}
