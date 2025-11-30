--- Forms package for re·sil·ient.
--
-- This package allows including basic form elements (interactive fields)
-- in PDF documents generated with the `libtexpdf` outputter.
--
-- @license MIT
-- @copyright (c) 2025 Omikhkeia / Didier Willis
-- @module packages.resilient.forms

local computeBaselineRatio = require("resilient.utils").computeBaselineRatio

--- Compute the combined field flags for a field.
--
-- @tparam table options Options (readonly, required, noexport)
-- @tparam number btype Base type flags (type-specific bits)
-- @treturn number Combined field flags
local function getFieldFlags (options, btype)
  -- PDF 1.7 Table 221
  -- Field flags common to all field types.
  local readonly = SU.boolean(options.required, false) and 1 or 0 -- Bit 1
  local required = SU.boolean(options.readonly, false) and 2 or 0 -- Bit 2
  local noexport = SU.boolean(options.noexport, false) and 4 or 0 -- Bit 3
  -- Other bits are type-specific
  local flags = btype + required + readonly + noexport
  return flags
end

--- Assert that a field name is valid.
--
-- The PDF specification restricts the characters that can be used in field names.
-- To keep things simple and avoid later issues, we enforce a stricter subset:
-- ASCII letters, digits, underscore, dash, colon, and period.
--
-- @tparam string name Field name
-- @treturn string Stripped field name if valid
-- @raise error if the name is invalid
local function assertNameValidity(name)
  -- Let's play fair and ignore trailing/leading spaces
  name = pl.stringx.strip(name)
  -- PDF 1.7 7.3.5 Names Object
  -- but we enforce a stricter subset for simplicity:
  -- Only characters, digits, and underscore, dash, colon, and period.
  if not name:match("^[A-Za-z0-9_%-%.:]+$") then
    SU.error("Invalid field name: " .. tostring(name) .. "\n" ..[[
Field names may only contain letters, digits, underscore and hyphen-dash.
  ]])
  end
  return name
end

--- The "resilient.forms" package.
--
-- Extends `packages.base`.
--
-- @type packages.resilient.forms

local base = require("packages.base")
local package = pl.class(base)
package._name = "resilient.forms"

local pdf -- Loaded later only if needed

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

-- Forward declaration
local getAppearances

--- (Constructor) Initialize the package.
--
-- @tparam table options Package options (none currently defined)
function package:_init (options)
  base._init(self, options)

  -- Hash map of forms:
  --   name -> {
  --     fieldDict = PdfDict,
  --     kids = PdfArray,
  --     type = "checkbox" | "radio" | "text" | "choice"
  --     flags = integer
  --   }
  self._parents = pl.Map()
  self._objectsToRelease = {} -- List of PDF objects to release at end

  if SILE.outputter._name ~= "libtexpdf" then
    SU.warn("The resilient.forms package only does something with the libtexpdf backend.")
    self._hasFormSupport = false
  else
    self._hasFormSupport = true
    pdf = require("justenoughlibtexpdf")
  end
  local this = self
  SILE.outputter:registerHook("prefinish", function ()
    -- Use a closure to access 'this', check support and release PDF objects.
    if this._hasFormSupport then
      this:_releasePdfObjects()
    end
  end)

  getAppearances = pl.utils.memoize(function (key)
    -- Appearances are automatically scaled to fit the widget rectangle,
    -- So we can create them at a fixed size.
    -- E.g. using an arbitrary bounding box [0 0 140 140].
    SU.debug("resilient.forms", "Creating appearances for shape", key)
    if key == "square" then
      -- Square for Off state.
      local offObj = self:_createAppearanceStream(
        "10 10 120 120 re 9 w S",
        140,
        140
      )
      -- Square with filled smaller square for On state.
      local onObj = self:_createAppearanceStream(
        "10 10 120 120 re 9 w S 30 30 80 80 re f",
        140,
        140
      )
      return { on = onObj, off = offObj }
    elseif key == "circle" then
      local offObj = self:_createAppearanceStream(
      -- Circle for Off state.
      -- Using 4 cubic Béziers to approximate a circle:
      --   k = 4 * (sqrt(2) -1)/3 ~= 0.5522847498
      -- Pre-computed values for radius 60 centered at (70, 70):
      --   103.13708 = 70 + 60 * k
      --    36.86291 = 70 - 60 * k
      -- (Rounded to 5 decimal dogits, Annex C.1 of the PDF 1.7 spec.)
[[9 w
130 70 m
130 103.13708 103.13708 130 70 130 c
36.86291 130 10 103.13708 10 70 c
10 36.86291 36.86291 10 70 10 c
103.13708 10 130 36.86291 130 70 c S]],
        140,
        140
      )

      local onObj = self:_createAppearanceStream(
      -- Approximated circle with 4 cubic Béziers, filled smaller circle for On state.
      -- Same as above, and smaller circle of radius 40 centered at (70, 70):
      --    92.09139 = 70 + 40 * k
      --    47.90861 = 70 - 40 * k
[[9 w
130 70 m
130 103.13708 103.13708 130 70 130 c
36.86291 130 10 103.13708 10 70 c
10 36.86291 36.86291 10 70 10 c
103.13708 10 130 36.86291 130 70 c S
110 70 m
110 92.09139 92.09139 110 70 110 c
47.90861 110 30 92.09139 30 70 c
30 47.90861 47.90861 30 70 30 c
92.09139 30 110 47.90861 110 70 c f]],
        140,
        140
      )
      return { on = onObj, off = offObj }
    end
  SU.error("Unknown checkbox appearance type: " .. tostring(key))
  end)
end

--- (Private) Release PDF objects that were kept until the end.
--
-- Some objects (appearances, parent field dictionaries) need to be
-- released after the PDF is finished:
-- They are only referenced indirectly in other objects as we build
-- them one by one.
--
function package:_releasePdfObjects ()
  SU.debug("resilient.forms", "Releasing", #self._objectsToRelease, "PDF objects (appearances, etc.)")
  for _, obj in ipairs(self._objectsToRelease) do
    pdf.release(obj)
  end

  SU.debug("resilient.forms", "Releasing", self._parents:len(), "PDF parent field dictionaries")
  for _, entry in self._parents:iter() do
    pdf.release(entry.fieldDict)
  end
end

--- (Private) Create an appearance stream XObject.
--
-- @tparam string operator Drawing operators
-- @tparam number width Width of the bounding box
-- @tparam number height Height of the bounding box
-- @treturn PdfDict Appearance stream XObject
function package:_createAppearanceStream (operator, width, height)
  -- <<
  --   /Type /XObject    % Mandatory type XObject
  --   /Subtype /Form    % Mandatory subtype Form
  --   /BBox [0 0 W H]   % Bounding box
  --   /Resources << >>  % Resources dictionary (empty here, but needed for synchronization to work)
  --   /Length N         % Length of the stream
  -- >>
  -- stream
  --   ... operator ...  % Drawing operators
  -- endstream
  local xObjectSpec = string.format([[<<
    /Type /XObject
    /Subtype /Form
    /BBox [0 0 %d %d]
    /Resources << >>
    /Length %d
  >>]],
    width,
    height,
    string.len(operator)
  ) .. "\nstream\n" .. operator .. "\nendstream"
  local xObject = pdf.parse(xObjectSpec)
  table.insert(self._objectsToRelease, xObject)
  return xObject
end

--- (Private) Retrieve or create the /AcroForm/Fields array in the PDF Catalog.
--
-- @treturn PdfArray The /Fields array in the /AcroForm dictionary
function package:_getAcroFormFieldDict ()
  -- PDF 1.7 12.7.2
  -- "The contents and properties of a document’s interactive form shall be defined by an
  -- interactive form dictionary that shall be referenced from the AcroForm entry in the
  -- document catalogue..."

  -- /AcroForm <<
  --   /Fields [ ... ]    % Mandatory array of form field dictionaries (references)
  --   ...                % Other entries (optional)
  -- >>
  if self._acroFormFields then
    return self._acroFormFields
  end
  local catalog = pdf.get_dictionary("Catalog")
  local acroform = pdf.lookup_dictionary(catalog, "AcroForm")
  if not acroform then
    SU.debug("resilient.forms", "Creating /AcroForm in PDF Catalog")
    acroform = pdf.parse("<< /Fields [] >>")
    pdf.add_dict(catalog, pdf.parse("/AcroForm"), acroform)
  end
  local fields = pdf.lookup_dictionary(acroform, "Fields")
  if not fields then
    SU.debug("resilient.forms", "Creating /Fields array in /AcroForm")
    fields = pdf.parse("[]")
    pdf.add_dict(acroform, pdf.parse("/Fields"), fields)
  end
  self._acroFormFields = fields
  return fields
end

--- (Private) Insert a field dictionary in the /AcroForm /Fields array.
--
-- @tparam PdfDict fieldDict Field dictionary to insert
function package:_insertInAcroformFields(fieldDict)
  local fields = self:_getAcroFormFieldDict()
  pdf.push_array(fields, pdf.reference(fieldDict))
end

--- (Private) Register a widget on its parent field and insert it in the current page.
--
-- @tparam PdfDict annotDict Widget annotation dictionary
-- @tparam table parent Parent field entry (fieldDict, kids, type, flags)
function package:_registerOnParentAndInsetInPage (annotDict, parent)
  SU.debug("resilient.forms", "Registering widget annotation on parent field and inserting in current page")

  -- Add the /Parent entry
  pdf.add_dict(annotDict, pdf.parse("/Parent"), pdf.reference(parent.fieldDict))

  -- Add to /Kids of parent
  pdf.push_array(parent.kids, pdf.reference(annotDict))

  -- Add the annotation to the page's /Annots array
  local page = pdf.get_dictionary("@THISPAGE")
  local annots = pdf.lookup_dictionary(page, "Annots")
  if not annots then
    SU.debug("resilient.forms", "Creating /Annots array on current page")
    annots = pdf.parse("[]")
    pdf.add_dict(page, pdf.parse("/Annots"), annots)
  end
  pdf.push_array(annots, pdf.reference(annotDict))
  pdf.release(annotDict) -- Release the annotation object, no longer needed
end

--- (Private) Retrieve or create the (parent) field dictionary for a given field name.
--
-- @tparam function baseFieldSpecFn Function that returns the base field dictionary specification as a string.
-- @tparam string name Field name
-- @tparam string fieldType Field type
-- @tparam number flags Field flags
-- @treturn table Field entry (PdfDict dictionary, PdfArray kids, string type, number flags)
function package:_getFieldDictionary (baseFieldSpecFn, name, fieldType, flags)
   --- PDF 1.7 12.7.3.1 Field Dictionaries / General
   -- "Each field in a document’s interactive form shall be defined by a field dictionary,
   -- which shall be an indirect object..."
  if self._parents[name] == nil then
    -- This is the parent field dictionary, so it has no /Parent, but it has /Kids:.
    -- It handles the global state of the field.
    -- In terms of PDF 1.7 12.7.1 it is a "non-terminal field".
    SU.debug("resilient.forms", "Creating new field dictionary for", name, "of type", fieldType)

    -- 1. Create the base field dictionary
    local fieldSpec = baseFieldSpecFn()
    local fieldDict = pdf.parse(fieldSpec)

    -- 2. Adds the /Kids array
    local kids = pdf.parse("[]")
    pdf.add_dict(fieldDict, pdf.parse("/Kids"), kids)
    -- 3. Store it, keeping:
    --    The field dictionay (it will be referenced by widgets)
    --    The /Kids array (to which widgets will be added)
    --    The field type (for checking on reuse) TODO
    --    The field flags (for checking on reuse) TODO
    self._parents[name] = { fieldDict = fieldDict, kids = kids, type = fieldType, flags = flags }

    -- 4. Add to /AcroForm /Fields array
    local acroformFields = self:_getAcroFormFieldDict()
    pdf.push_array(acroformFields, pdf.reference(fieldDict))
  else
    if fieldType ~= "radio" then
      -- No reuse of fields yet for other types than radio buttons.
      -- Poorly supported in many PDF viewers.
    SU.error("Field with name " .. name .. " already defined.\n" .. [[
Multiple widgets with the same name not yet supported.
Several viewers (incl. Evince, Okular) seem to have issues with that.]])
    end
    -- For radio buttons, we allow multiple widgets to share the same parent field,
    -- but we check that the type and flags match.
    if self._parents[name].type ~= fieldType then
      SU.error("Field with name " .. name .. " already defined with a different type ("
         .. self._parents[name].type .. " vs. " .. fieldType .. ").")
    end
    if self._parents[name].flags ~= flags then
      SU.error("Field with name " .. name .. " already defined with different properties.")
    end
  end
  return self._parents[name]
end

--- (Private) Retrieve or create the parent field dictionary for a checkbox field.
--
-- @tparam string name Field name
-- @tparam table options Field options
-- @treturn table Field entry (PdfDict dictionary, PdfArray kids, string type, number flags)
function package:_getParentCheckboxField (name, options)
  local value = SU.boolean(options.checked, false) and "/Yes" or "/Off"
  local flags = getFieldFlags(options, 0) -- 0 = checkbox

  -- <<
  --   /FT /Btn       % Mandatory field type = buttons
  --   /T (name)      % Mandatory field name
  --   /Ff 0          % Field flags
  --   /V /Yes        % Current value (/Yes or /Off)
  --   /DV /Yes       % Default value (value when form is reset)
  --   /Kids [ ... ]  % Mandatory array of widget annotations (references)
  -- >>
  return self:_getFieldDictionary(function ()
    return string.format([[<<
        /FT /Btn
        /T (%s)
        /Ff %f
        /V %s
        /DV %s
      >>]],
      name,
      flags,
      value,
      value
    )
  end, name, "checkbox", flags)
end

--- (Private) Retrieve or create the parent field dictionary for a radio button field.
--
-- @tparam string name Field name
-- @tparam table options Field options
-- @treturn table Field entry (PdfDict dictionary, PdfArray kids, string type, number flags)
function package:_getParentRadioField (name, options)
  -- PDF 1.7 Table 226, bit 16 = Radio button (32768)
  local flags = getFieldFlags(options, 32768)
  -- RadiosInUnison (bit 26) not supported, not very usual anyway.

  -- <<
  --   /FT /Btn       % Mandatory field type = button
  --   /T (name)      % Mandatory field name
  --   /Ff 32768      % Field flags
  --   /V /Off        % Current value (/Option1, /Option2, etc., or /Off)
  --   /DV /Off       % Default value (value when form is reset)
  --   /Kids [ ... ]  % Mandatory array of widget annotations (references)
  -- >>
  --
  -- NOTE: When creating the field, we always set /V and /DV to /Off.
  -- Each widget will set its own /AS to /Off initially too, and the user
  -- can select one of them, which will update the /V entry in the parent.
  -- Handling a pre-selected radio button would require more work, since
  -- all our commands are independent.
  return self:_getFieldDictionary(function ()
    return string.format([[<<
        /FT /Btn
        /T (%s)
        /Ff %d
        /V /Off
        /DV /Off
      >>]],
      name,
      flags
    )
    end, name, "radio", flags)
end

--- (Private) Retrieve or create the parent field dictionary for a text field.
--
-- @tparam string name Field name
-- @tparam table options Field options
-- @treturn table Field entry (PdfDict dictionary, PdfArray kids, string type, number flags)
function package:_getParentTextField (name, options)
  local text = SU.utf8_to_utf16be_hexencoded(options.text or "")
  -- PDF 1.7 Table 228
  -- Field flags specific to text fields
  local password = SU.boolean(options.password, false) and 8192 or 0 -- Bit 14
  -- How to handle multiline fields properly? Esp. know the space to reserve?
  -- local multiline = SU.boolean(options.multiline, false) and 4096 or 0 -- Bit 13
  -- (And others not yet implemented)

  local btype = password -- + multiline
  local flags = getFieldFlags(options, btype)

  -- <<
  --   /FT /Tx        % Mandatory field type = text
  --   /T (name)      % Mandatory field name
  --   /Ff 0          % Field flags
  --   /V <value>     % Current value (UTF-16BE hex encoded)
  --   /DV <value>    % Default value (value when form is reset)
  --   /Kids [ ... ]  % Mandatory array of widget annotations (references)
  -- >>
  return self:_getFieldDictionary(function ()
    return string.format([[<<
        /FT /Tx
        /T (%s)
        /Ff %d
        /V <%s>
        /DV <%s>
      >>]],
      name,
      flags,
      text,
      text
    )
    end, name, "text")
end

--- (Private) Retrieve or create the parent field dictionary for a choice field.
--
-- @tparam string name Field name
-- @tparam table options Field options
-- @treturn table Field entry (PdfDict dictionary, PdfArray kids, string type, number flags)
function package:_getParentChoiceField (name, options)
  -- FIXME if not combo, how to reserve the space?
  local combo = true and 131072 or 0 -- Bit 18
  -- How to handle multiselect properly? Esp. know the space to reserve?
  -- local multiselect = SU.boolean(options.multiselect, false) and 262144 or 0 -- Bit 19
  -- (And others not yet implemented)

  local btype = combo -- + multiselect
  local flags = getFieldFlags(options, btype)

  -- options.choices is a list of space separated choices
  local opts = pl.stringx.split(options.choices, ",")
  local optsSpec = table.concat(
    pl.tablex.map(function (v)
      return string.format("(%s)", assertNameValidity(v))
    end, opts)
  )

  -- <<
  --   /FT /Ch                  % Mandatory field type = choice
  --   /T (name)                % Mandatory field name
  --   /Ff 0                    % flags: bit 18 = combo, bit 19 = multi-select, etc. Table 228 (many others)
  --   /V (...)                 % Current value
  --   /DV (...)                % Default value (value when form is reset)
  --   /Opt [(...) (...), ...]  % Array of available option values (e.g., [(Choice1) (Choice2) ...])
  --   /Kids [ ... ]            % Mandatory array of widget annotations (references)
  -- >>
  return self:_getFieldDictionary(function ()
    return string.format([[<<
        /FT /Ch
        /T (%s)
        /Ff %d
        /V (%s)
        /DV (%s)
        /Opt [ %s ]
      >>]],
      name,
      flags,
      opts[1] or "",
      opts[1] or "",
      optsSpec
    )
    end, name, "choice")
end

--- (Private) Add the appearance dictionary to a checkbox or radio button widget annotation.
--
-- @tparam PdfDict annotDict Widget annotation dictionary
-- @tparam string shape Shape type ("square", "circle", ...)
-- @tparam string onValue Name of the "On" appearance (e.g., "/Yes" or "/Option1")
-- @tparam string offValue Name of the "Off" appearance (e.g., "/Off")
function package:_addAppearanceDict (annotDict, shape, onValue, offValue)
  -- PDF 1.7 12.7.4.2.3 Check Boxes
  -- "Each state can have a separate appearance, which shall be defined by an appearance stream in the
  -- appearance dictionary of the field’s widget annotation."
  --
  -- The appearance stream itself is defined in PDF 1.7 12.5.5
  SU.debug("resilient.forms", "Adding appearance dictionary to widget annotation")

  -- Add the appearance dictionary
  local ap = pdf.parse("<< >>")
  pdf.add_dict(annotDict, pdf.parse("/AP"), ap)

  -- Add the normal appearance sub-dictionary
  local n = pdf.parse("<< >>")
  pdf.add_dict(ap, pdf.parse("/N"), n)

  -- Add the On and Off appearance streams
  local appearances = getAppearances(shape, onValue, offValue)
  pdf.add_dict(n, pdf.parse(onValue), pdf.reference(appearances.on))
  pdf.add_dict(n, pdf.parse(offValue), pdf.reference(appearances.off))
end

-- PDF 1.7 12.5.6.19 Widget Annotations
-- It also acts as the "terminal field" (no /Kids) that handles the visual representation and interaction,
-- that is the Widget annotation itself and the non-terminal field dictionary can be merged for simplicity,
-- and we do that here.

--- (Private) Create a checkbox widget annotation.
--
-- The annotation is created, registered on its parent field, and inserted
-- in the current page.
--
-- Caller should use coordinates that define a square area at proper position.
--
-- @tparam string name Field name
-- @tparam table options Field options
-- @tparam number x0 Start X coordinate
-- @tparam number y0 Start Y coordinate
-- @tparam number x1 End X coordinate
-- @tparam number y1 End Y coordinate
function package:_createCheckboxWidgetAnnotation (name, options, x0, y0, x1, y1)
  SU.debug("resilient.forms", "Creating checkbox widget annotation for field", name)
  local value = SU.boolean(options.checked, false) and "/Yes" or "/Off"
  -- <<
  --   /Type /Annot          % Annotation
  --   /Subtype /Widget      % Widget annotation
  --   /Parent REF           % Reference to the parent field dictionary
  --   /Rect [ x0 y0 x1 y1 ] % Rectangle specifying location on the page
  --   /AS /Off              % Appearance state (initial state) - SHOULD match /V in parent
  --   /AP <<                % Appearance dictionary for the widget
  --     /N <<               % Normal appearance
  --       /Off REF          % Appearance stream for Off state, as XObject reference
  --       /Yes REF          % Appearance stream for Yes state, as XObject reference
  --     >>
  --   >>
  -- >>
  local annotSpec = string.format([[<<
      /Type /Annot
      /Subtype /Widget
      /AS %s
      /Rect [ %f %f %f %f ]
    >>]],
    value,
    trueXCoord(x0), trueYCoord(y0),
    trueXCoord(x1), trueYCoord(y1)
  )
  local annotDict = pdf.parse(annotSpec)
  self:_addAppearanceDict(annotDict, "square", "/Yes", "/Off")

  local parent = self:_getParentCheckboxField(name, options)
  self:_registerOnParentAndInsetInPage(annotDict, parent)
end

--- (Private) Create a radio button widget annotation.
--
-- The annotation is created, registered on its parent field, and inserted
-- in the current page.
--
-- Caller should use coordinates that define a square area at proper position.
--
-- @tparam string name Field name
-- @tparam table options Field options
-- @tparam number x0 Start X coordinate
-- @tparam number y0 Start Y coordinate
-- @tparam number x1 End X coordinate
-- @tparam number y1 End Y coordinate
function package:_createRadioWidgetAnnotation (name, options, x0, y0, x1, y1)
  SU.debug("resilient.forms", "Creating radio button widget annotation for field", name)
  local value = assertNameValidity(SU.required(options, "value", "Radio button option must have a value"))
  -- <<
  --   /Type /Annot          % Annotation
  --   /Subtype /Widget      % Widget annotation
  --   /Parent REF           % Reference to the parent field dictionary
  --   /Rect [ x0 y0 x1 y1 ] % Rectangle specifying location on the page
  --   /AS /Off              % Appearance state (initial state) - SHOULD match /V in parent
  --   /AP <<                % Appearance dictionary for the widget
  --     /N <<               % Normal appearance
  --       /Option1 REF      % Appearance stream for the radio button value, as XObject reference
  --       /Off REF          % Appearance stream for Off state, as XObject reference
  --     >>
  --   >>
  -- >>
  local annotSpec = string.format([[<<
      /Type /Annot
      /Subtype /Widget
      /AS /Off
      /Rect [ %f %f %f %f ]
    >>]],
    trueXCoord(x0 ), trueYCoord(y0),
    trueXCoord(x1), trueYCoord(y1)
  )
  local annotDict = pdf.parse(annotSpec)
  self:_addAppearanceDict(annotDict, "circle", "/" .. value, "/Off")

  local parent = self:_getParentRadioField(name, options)
  self:_registerOnParentAndInsetInPage(annotDict, parent)
end

--- (Private) Create a text widget annotation.
--
-- The annotation is created, registered on its parent field, and inserted
-- in the current page.
--
-- Caller should use coordinates that define a rectangular area at proper position.
--
-- @tparam string name Field name
-- @tparam table options Field options
-- @tparam number x0 Start X coordinate
-- @tparam number y0 Start Y coordinate
-- @tparam number x1 End X coordinate
-- @tparam number y1 End Y coordinate
-- @tparam number fontSize Font size
function package:_createTextWidgetAnnotation (name, options, x0, y0, x1, y1, fontSize)
  SU.debug("resilient.forms", "Creating text widget annotation for field", name)
  -- <<
  --   /Type /Annot          % Annotation
  --   /Subtype /Widget      % Widget annotation
  --   /Parent REF           % Reference to the parent field dictionary
  --   /Rect [ x0 y0 x1 y1 ] % Rectangle specifying location on the page
  --   /DA (/F1 SZ Tf)       % Default appearance font, size SZ (and optional color etc.) SEE BELOW
  --   /DR <<                % Resource dictionary for the appearance SEE BELOW
  --     /Font <<
  --       /F1 REF           % Font object reference
  --     >>
  --   >>
  --   /Border [1 1 1]       % Border style NOT DONE HERE
  --   /MK <<                % Widget appearance characteristics NOT DONE HERE
  --     ...
  --   >>
  --   /AP <<
  --     /N REF              % Normal appearance stream reference NOT DONE HERE
  --   >>
  -- >>
  --
  -- On /DA see PDF 1.7 12.7.3.3 Variable Text.
  -- On /DR DR see Table 218 and 7.8.3 Resource Dictionaries.
  -- In brief:
  -- A font, usually referenced as /Fn in the page's /Resources /Font dictionary,
  -- should be used for the field's appearance.
  -- This is not as obvious to implement here:
  --  - The "current" font hasn't been stored in the page's /Resources yet at this time.
  --  - The font may be subsetted, so we don't know which glyphs will be available.
  -- We use a "standard" font that should always be available in PDF viewers.
  -- BUT it's not compliant with PDF/A (or PDF/UA) which requires embedded fonts only
  -- notably in all "visible text" content.
  local annotSpec = string.format([[<<
      /Type /Annot
      /Subtype /Widget
      /Rect [ %f %f %f %f ]
      /DA (/Helvetica %f Tf)
    >>]],
    trueXCoord(x0), trueYCoord(y0),
    trueXCoord(x1), trueYCoord(y1),
    fontSize
  )
  local annotDict = pdf.parse(annotSpec)

  local parent = self:_getParentTextField(name, options)
  self:_registerOnParentAndInsetInPage(annotDict, parent)
end

--- (Private) Create a choice widget annotation.
--
-- The annotation is created, registered on its parent field, and inserted
-- in the current page.
--
-- Caller should use coordinates that define a rectangular area at proper position.
--
-- @tparam string name Field name
-- @tparam table options Field options
-- @tparam number x0 Start X coordinate
-- @tparam number y0 Start Y coordinate
-- @tparam number x1 End X coordinate
-- @tparam number y1 End Y coordinate
-- @tparam number fontSize Font size
function package:_createChoiceWidgetAnnotation (name, options, x0, y0, x1, y1, fontSize)
  SU.debug("resilient.forms", "Creating choice widget annotation for field", name)
  -- <<
  --   /Type /Annot          % Annotation
  --   /Subtype /Widget      % Widget annotation
  --   /Parent REF           % Reference to the parent field dictionary
  --   /Rect [ x0 y0 x1 y1 ] % Rectangle specifying location on the page
  --   /DA (/F1 SZ Tf)       % Default appearance font (and color if needed) SEE TEXT WIDGET
  --   /DR <<                % Resource dictionary for the appearance SEE TEXT WIDGET
  --     /Font <<
  --       /F1 REF           % Font object reference
  --     >>
  --   >>
  -- >>
  --
  -- Same comments as for text widget regarding font selection.
  local annotSpec = string.format([[<<
      /Type /Annot
      /Subtype /Widget
      /Rect [ %f %f %f %f ]
      /DA (/Helvetica %f Tf)
    >>]],
    trueXCoord(x0), trueYCoord(y0),
    trueXCoord(x1), trueYCoord(y1),
    fontSize
  )
  local annotDict = pdf.parse(annotSpec)

  local parent = self:_getParentChoiceField(name, options)
  self:_registerOnParentAndInsetInPage(annotDict, parent)
end

--- (Override) Register all commands provided by this package.
--
-- Currently provides "checkbox", "radiobutton", "textfield", and "choicemenu" commands.
--
function package:registerCommands ()

  self:registerCommand("checkbox", function (options, _)
    if not self._hasFormSupport then
      SU.warn("The resilient.forms package requires the libtexpdf outputter to create PDF forms.")
      return
    end
    local name = assertNameValidity(SU.required(options, "name", "checkbox"))
    SILE.typesetter:pushHbox({
      value = nil,
      width = SILE.types.length(SILE.types.length("0.8em"):tonumber()),
      height = SILE.types.length(SILE.types.length("0.75em"):tonumber()),
      depth = SILE.types.length(SILE.types.length("0.05em"):tonumber()),
      outputYourself = function (this, typesetter)
        local x0 = typesetter.frame.state.cursorX:tonumber()
        local y0 = (SILE.documentState.paperSize[2] - typesetter.frame.state.cursorY):tonumber()
        self:_createCheckboxWidgetAnnotation(
          name,
          options,
          x0,
          y0 - this.depth:tonumber(),
          x0 + this.width:tonumber(),
          y0 + this.height:tonumber()
        )
        typesetter.frame:advanceWritingDirection(this.width)
      end,
    })
  end)

  self:registerCommand("radiobutton", function (options, _)
    if not self._hasFormSupport then
      SU.warn("The resilient.forms package requires the libtexpdf outputter to create PDF forms.")
      return
    end
    local name = assertNameValidity(SU.required(options, "name", "radiobutton"))
    SILE.typesetter:pushHbox({
      value = nil,
      width = SILE.types.length(SILE.types.length("0.8em"):tonumber()),
      height = SILE.types.length(SILE.types.length("0.75em"):tonumber()),
      depth = SILE.types.length(SILE.types.length("0.05em"):tonumber()),
      outputYourself = function (this, typesetter)
        local x0 = typesetter.frame.state.cursorX:tonumber()
        local y0 = (SILE.documentState.paperSize[2] - typesetter.frame.state.cursorY):tonumber()
        self:_createRadioWidgetAnnotation(
          name,
          options,
          x0,
          y0 - this.depth:tonumber(),
          x0 + this.width:tonumber(),
          y0 + this.height:tonumber()
        )
        typesetter.frame:advanceWritingDirection(this.width)
      end,
    })
  end)

  self:registerCommand("textfield", function (options, _)
    if not self._hasFormSupport then
      SU.warn("The resilient.forms package requires the libtexpdf outputter to create PDF forms.")
      return
    end
    local name = assertNameValidity(SU.required(options, "name", "textfield"))

    -- Quite empirical, attempt to have a reasonable height/depth
    local leading = SILE.types.length("1bs"):tonumber()
    local bsratio = computeBaselineRatio()
    -- Quite empirical, a tad smaller than the current font size
    local fontSize = SILE.settings:get("font.size") * 0.95

    SILE.typesetter:pushHbox({
      value = nil,
      -- Width minimally 4em (arbitrary choice), expandable to the line width
      width = SILE.types.length(SILE.types.node.hfillglue("4em")):absolute(),
      height = SILE.types.length((1 - bsratio) * leading),
      depth = SILE.types.length(bsratio * leading),
      outputYourself = function (this, typesetter, line)
        local outputWidth = SU.rationWidth(this.width, this.width, line.ratio):tonumber()
        local x0 = typesetter.frame.state.cursorX:tonumber()
        local y0 = (SILE.documentState.paperSize[2] - typesetter.frame.state.cursorY):tonumber()
        self:_createTextWidgetAnnotation(
          name,
          options,
          x0,
          y0 - this.depth:tonumber(),
          x0 + outputWidth,
          y0 + this.height:tonumber(),
          fontSize
        )
        typesetter.frame:advanceWritingDirection(this.width)
      end,
    })
  end)

  self:registerCommand("choicemenu", function (options, _)
    if not self._hasFormSupport then
      SU.warn("The resilient.forms package requires the libtexpdf outputter to create PDF forms.")
      return
    end
    local name = assertNameValidity(SU.required(options, "name", "choicemenu"))

    -- Quite empirical, attempt to have a reasonable height/depth
    local leading = SILE.types.length("1bs"):tonumber()
    local bsratio = computeBaselineRatio()
    -- Quite empirical, a tad smaller than the current font size
    local fontSize = SILE.settings:get("font.size") * 0.95

    SILE.typesetter:pushHbox({
      value = nil,
      -- Width minimally 4em (arbitrary choice), expandable to the line width
      width = SILE.types.length(SILE.types.node.hfillglue("4em")):absolute(),
      height = SILE.types.length((1 - bsratio) * leading),
      depth = SILE.types.length(bsratio * leading),
      outputYourself = function (this, typesetter, line)
        local outputWidth = SU.rationWidth(this.width, this.width, line.ratio):tonumber()
        local x0 = typesetter.frame.state.cursorX:tonumber()
        local y0 = (SILE.documentState.paperSize[2] - typesetter.frame.state.cursorY):tonumber()
        self:_createChoiceWidgetAnnotation(
          name,
          options,
          x0,
          y0 - this.depth:tonumber(),
          x0 + outputWidth,
          y0 + this.height:tonumber(),
          fontSize
        )
        typesetter.frame:advanceWritingDirection(this.width)
      end,
    })
  end)

  -- SOME RAW NOTES FOR FUTURE REFERENCE
  --
  -- LaTeX hyperref also has:
  -- \PushButton[parameters]{label}
  -- \Submit[parameters]{label}
  -- \Reset[parameters]{label}
  --
  -- \PushButton is a /FT /Btn with no radio/checkbox flags.
  -- It's a general button, which could trigger JavaScript or actions.
  -- We are not implementing it for now, JavaScript support in viewers is spotty at best.
  --
  -- \Submit is a buton with action to submit the form.
  -- I.e. /A << /S /SubmitForm /F (http://example.com/submit) >>
  -- We are not implementing it for now, Submit forms support in viewers is spotty at best.
  --
  -- \Reset is a button with action to reset the form.
  -- I.e. /A << /S /ResetForm >>
  -- Could be implemented relatively easily, but not doing it for now.
  -- We"d need a cool appearance stream for the button too.
  --
  -- Additional actions (/AA) describe when happens on certain events, like mouse enter, exit, focus, etc.
  -- Not implemented for now, as not very common and viewer support is also spotty.
  --
  -- On viewer support...
  -- Tested with: evince 46.3.1, okular 25.04.3, firefox (pdf.js) 145.x, Chromium 141.x
  --  - Evince honors appearance states properly for checkboxes and radio buttons.
  --  - Okular doest in too when viewing, but replaces all interactive form fields with
  --    its own widgets (on top of the appearance streams) when entering "form editing mode".
  --  - Evince crashes a lot when re-compiling an opened PDF with forms.
  --  - Both do not properly support multiple widgets sharing the same field name.
  --  - Both do not properly update the parent field value if the widget is changed (text field edited).
  --  - Firefox replaces all interactive form fields with its own widgets, ignoring the appearance streams.
  --  - Chromium seems shows the appearance streams properly.
  -- PDF is a complicated format and form support is spotty in many viewers.
end

package.documentation = [[\begin{document}
The experimental \autodoc:package{resilient.forms} package allows the creation of PDF forms with interactive fields, such as checkboxes, radio buttons, text fields, and choice menus.

\noindent\autodoc:command{\checkbox[name=<name>, checked=<false|true>]}

\noindent\autodoc:command{\radiobutton[name=<name>, value=<option>]}

\noindent\autodoc:command{\textfield[name=<name>, text=<default text>, password=<false|true>]}

\noindent\autodoc:command{\choicemenu[name=<name>, choices=<options>]}

\medskip
Common additional options for all commands are \autodoc:parameter{readonly=<false|true>}, \autodoc:parameter{required=<false|true>}, and \autodoc:parameter{noexport=<false|true>}.

\medskip
\checkbox[name=agree, checked=true] I like the \em{re·sil·ient} forms package.

\smallskip
\radiobutton[name=user, value=User] I am a simple user.

\radiobutton[name=user, value=Developer] I am a developer.

Name: \underline{\textfield[name=username, text=Omikhleia]}

I am from:
\choicemenu[name=country, choices="France, Germany, Italy, Spain, Other", combo=true, multiselect=false]

\medskip
PDF/A or PDF/UA compliance requires all fonts used in form fields to be embedded in the PDF.
This package uses a standard font for text-based form fields, which is not embedded, and is therefore not compliant.

\medskip
Note that forms are only supported with SILE’s \code{libtexpdf} outputter, and are ignored otherwise.

\end{document}]]

return package
