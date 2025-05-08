--
-- Definition environment for SILE,
-- Very minimal implementation for Djot/Markdown needs, with styling support.
-- Following the resilient styling paradigm.
--
-- License: MIT
-- Copyright (C) 2023-2025 Omikhleia / Didier Willis
--
local trimLeft = function (str)
  return str:gsub("^%s*", "")
end

local trimRight = function (str)
  return str:gsub("%s*$", "")
end

local trim = function (str)
  return trimRight(trimLeft(str))
end

local base = require("packages.resilient.base")
local package = pl.class(base)
package._name = "resilient.defn"

function package:_init (options)
  base._init(self, options)
end

function package:declareSettings ()

  SILE.settings:declare({
    parameter = "defn.variant",
    type = "string or nil",
    default = nil,
    help = "Definition variant (styling)"
  })

  SILE.settings:declare({
    parameter = "defn.indent",
    type = "measurement",
    default = SILE.types.measurement("2em"),
    help = "Definition description indentation (styling)"
  })

end

function package:registerCommands ()

  self:registerCommand("defn:internal:term", function (options, content)
    local variant = options.variant or SILE.settings:get("defn.variant")
    local varstyle = variant and "defn-term-" .. variant
    local style = varstyle and self.styles:hasStyle(varstyle) and varstyle or "defn-term"

    SILE.call("style:apply:paragraph", { name = style }, content)
  end, "Definition term (internal)")

  self:registerCommand("defn:internal:desc", function (options, content)
    local variant = options.variant or SILE.settings:get("defn.variant")
    local varstyle = variant and "defn-desc-" .. variant
    local style = varstyle and self.styles:hasStyle(varstyle) and varstyle or "defn-desc"

    SILE.settings:temporarily(function ()
      local indent = SILE.settings:get("defn.indent"):absolute()
      local lskip = SILE.settings:get("document.lskip") or SILE.types.node.glue()
      SILE.settings:set("document.lskip", SILE.types.node.glue(lskip.width:absolute() + indent))
      SILE.call("style:apply:paragraph", { name = style }, content)
    end)
  end, "Definition block (internal)")

  self:registerCommand("defn", function (options, content)
    local term = SU.ast.removeFromTree(content, "term")
    local desc = SU.ast.removeFromTree(content, "desc")
    if not term then
      SU.error("Missing term in definition")
    end

    for _, v in ipairs(content) do
      -- Just check that there is no unexpected content left
      if type(v) == "string" then
        -- All text nodes are ignored in structure tags, but just warn
        -- if there do not just consist in spaces.
        local text = trim(v)
        if text ~= "" then SU.warn("Ignored standalone text ("..text..")") end
      else
        SU.error("Definition structure error")
      end
    end

    SILE.call("defn:internal:term", options, term)
    if desc then
      SILE.call("defn:internal:desc", options, desc)
    end
  end, "Definition environment (term and description).")

end

function package:registerStyles ()
  self:registerStyle("defn-base", {}, {})

  self:registerStyle("defn-term", { inherit = "defn-base" }, {
    font = { weight = 700 },
    paragraph = {
      before = {
        skip = "smallskip"
      },
      after = {
        vbreak = false
      }
    }
  })
  self:registerStyle("defn-desc", { inherit = "defn-base" }, {
    paragraph = {
      before = {
        vbreak = false
      },
      after = {
        skip = "smallskip"
      }
    }
  })
end

package.documentation = [[\begin{document}
The \autodoc:package{resilient.defn} package is a style-enabled implementation of definition items, containing a term and a description.
The current implementation is fairly minimal, focused on the needs of Djot and Markdown.

The \autodoc:environment{defn} environment can contain a \autodoc:command[check=false]{\term} and a \autodoc:command[check=false]{\desc} element, and nothing else.
By default, it looks like this:

\begin{defn}
  \term{SILE}
  \desc{A typesetting system.}
\end{defn}

\begin{defn}
  \term{re·sil·ient}
  \desc{A collection of classes and packages for SILE.}
\end{defn}

The term is styled with the \code{defn-term} paragraph style, and the description is styled with the \code{defn-desc} paragraph style.

The indentation of the description can be controlled with the \autodoc:setting{defn.indent} setting, which defaults to \code{2em}.

The package also exposes a \autodoc:setting{defn.variant} setting, to globally switch to an alternate set of styles, assumed to be named \code{defn-term-⟨\em{variant}⟩} and \code{defn-desc-⟨\em{variant}⟩}.
To switch styles on a specific definition, the \autodoc:environment{defn} environment also accepts a \autodoc:parameter{variant} option.

\end{document}]]

return package
