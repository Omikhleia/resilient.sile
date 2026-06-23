--- A PDF annotations package for re·sil·ient.
--
-- @license MIT
-- @copyright (c) 2026 Omikhleia / Didier Willis
-- @module packages.resilient.annotations

--- The "resilient.annotations" package.
--
-- Extends SILE's `packages.base`.
--
-- @type packages.resilient.annotations

local base = require("packages.base")
local package = pl.class(base)
package._name = "resilient.annotations"

local pdf -- Loaded later only if needed

--- (Constructor) Initialize the package.
-- @tparam table options Package options
function package:_init (options)
  base._init(self, options)
  if SILE.outputter._name ~= "libtexpdf" then
    SU.warn("The resilient.annotations package only does something with the libtexpdf backend.")
    self._hasLibTeXPdfSupport = false
  else
    self._hasLibTeXPdfSupport = true
    pdf = require("justenoughlibtexpdf")
  end
end

-- HACK
-- Adjust coordinates to take into account possible sheet size.
-- Copied from the internals (locals) of the libtexpdf outputter.
local deltaX
local deltaY
local function trueXCoord (x)
   if not deltaX then
      local sheetSize = SILE.documentState.sheetSize or SILE.documentState.paperSize
      deltaX = (sheetSize[1] - SILE.documentState.paperSize[1]) / 2
   end
   return x + deltaX
end
local function trueYCoord (y)
   if not deltaY then
      local sheetSize = SILE.documentState.sheetSize or SILE.documentState.paperSize
      deltaY = (sheetSize[2] - SILE.documentState.paperSize[2]) / 2
   end
   return y + deltaY
end

 -- <<
  --   /FT /Btn       % Mandatory field type = buttons
  --   /T (name)      % Mandatory field name
  --   /Ff 0          % Field flags
  --   /V /Yes        % Current value (/Yes or /Off)
  --   /DV /Yes       % Default value (value when form is reset)
  --   /Kids [ ... ]  % Mandatory array of widget annotations (references)
  -- >>

function package:_createTooltipAnnotation (text, x0, y0, x1, y1)
  SU.debug("resilient.annotations", "Creating tooltip annotation")
  -- Hidden Widget annotation used as tooltip carrier.
  -- <<
  --  /Type /Annot
  --  /Subtype /Widget
  --  /Rect [ x0 y0 x1 y1 ]
  --  /F 768                 % Flags: Print + NoZoom + NoRotate
  --  /FT /Btn               % Field type: button
  --  /Ff 65536              % Field flags: ReadOnly
  --  /H /N                  % Highlight mode: none on mouse interaction
  --  /BS << /W 0 >>         % Border style: width 0 (invisible border)
  --  /TU <text>             % Tooltip text (UTF-16BE hex-encoded)
  --  /T (...)               % Internal field name (unique to avoid name collisions)
  --  /C []                  % Empty color array to avoid visible widget coloring
  -- >>
  self._tooltipCounter = self._tooltipCounter and (self._tooltipCounter + 1) or 1
  local annotSpec = string.format([[<<
      /Type /Annot
      /Subtype /Widget
      /Rect [ %f %f %f %f ]
      /F 768
      /FT /Btn
      /Ff 65536
      /H /N
      /BS << /W 0 >>
      /TU <%s>
      /T (%s)
      /C []
    >>]],
    trueXCoord(x0), trueYCoord(y0),
    trueXCoord(x1), trueYCoord(y1),
    SU.utf8_to_utf16be_hexencoded(text),
    "resilient_tooltip_" .. self._tooltipCounter
  )
  local annotDict = pdf.parse(annotSpec)
  pdf.add_page_annotation(pdf.reference(annotDict))
  pdf.release(annotDict) -- Release the annotation object, no longer needed
end

--- (Override) Register all commands provided by this package.
--
-- Currently provides "tooltip".
--
-- Features are (loosely) based on ideas from the LaTeX `pdfcomment` package.
-- Contributors are welcome to study that package and propose additional features.
--
function package:registerCommands ()
  self:registerCommand("tooltip", function (options, content)
    if not self._hasLibTeXPdfSupport then
      SU.warn("The resilient.annotations package requires the libtexpdf outputter to create PDF annotations.")
      return
    end
    local text = SU.required(options, "text", "The 'text' option is required for the tooltip command.")

    SILE.typesetter:liner("resilient:annotations:tooltip", content,
      function (box, typesetter, line)
        local x0 = typesetter.frame.state.cursorX:tonumber()
        local y0 = (SILE.documentState.paperSize[2] - typesetter.frame.state.cursorY):tonumber()
        local outputWidth = SU.rationWidth(box.width, box.width, line.ratio)
        self:_createTooltipAnnotation(
          text,
          x0,
          y0 - box.depth:tonumber(),
          x0 + outputWidth:tonumber(),
          y0 + box.height:tonumber()
        )
        box:outputContent(typesetter, line)
      end
    )
  end)
end

package.documentation = [[\begin{document}
The experimental \autodoc:package{resilient.annotations} package allows the creation of PDF annotations, such as tooltips, associated with content in the PDF.

\medskip
\noindent
\tooltip[text=Should we really explain what tooltips are?
We can perhaps assume most readers will know.]{\autodoc:command{\tooltip[text=<tooltip text>]{<content>}} creates a tooltip annotation with the specified text, associated with the content. When the user hovers over the content in a PDF viewer that supports it, the tooltip text will be displayed.
The content can span multiple lines.}

\medskip
Note that forms are only supported with SILE’s \code{libtexpdf} outputter, and are ignored otherwise.

\end{document}]]

return package
