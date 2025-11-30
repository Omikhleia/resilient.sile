--- Attachment package for re·sil·ient.
--
-- This package allows attaching arbitrary files to the generated PDF, when using
-- the `libtexpdf` outputter.
--
-- @license MIT
-- @copyright (c) 2025 Omikhkeia / Didier Willis
-- @module packages.resilient.attachments

--- The "resilient.attachments" package.
--
-- Extends `packages.base`.
--
-- @type packages.resilient.attachments

local base = require("packages.base")
local package = pl.class(base)
package._name = "resilient.attachments"

local pdf -- Loaded later only if needed
local mimetypes = require("mimetypes")
local xmpMetadata = require("resilient.support.xmp").xmpMetadata

--- (Constructor) Initialize the package.
--
-- @tparam table options Package options (none currently defined)
function package:_init (options)
  base._init(self, options)

  -- N.B. I hate these scratch spaces, but we need a global container.
  -- Hash map of attachments:
  --   name -> {
  --     description = string,
  --     filename = string,
  --     relation = string,
  --     mime = string,
  --     content = string|nil,
  --   }
  SILE.scratch.attachments = SILE.scratch.attachments or pl.OrderedMap()
  self._attachments = SILE.scratch.attachments

  self._xmpDocumentKey = nil -- Used for XMP DocumentID generation
  self._isFacturX = false

  self._hasAttachmentSupport = true
  if SILE.outputter._name ~= "libtexpdf" then
    SU.warn("The resilient.attachments package only does something with the libtexpdf backend.")
    self._hasAttachmentSupport = false
  end
  local this = self
  SILE.outputter:registerHook("prefinish", function ()
    -- Use a closure to access 'this', check support and output attachments on the proper instance.
    if this._hasAttachmentSupport then
      this:_outputAttachments()
    end
  end)
end

local function isAsciiString (s)
  for i = 1, #s do
    if s:byte(i) > 127 then
      return false
    end
  end
  return true
end

--- (Private) Build the PDF objects for all registered attachments.
--
-- It iterates over all registered attachments and builds the necessary PDF objects
-- using libtexpdf functions:
--
--  - An embedded file stream for each attachment,
--  - A file specification dictionary for each attachment.
--
-- @treturn pl.OrderedMap Ordered map of attachment names (UTF-16BE hex-encoded) with object references.
function package:_buildAttachments ()
  local attachments = pl.OrderedMap()

  local n = 0
  for name, entry in self._attachments:iter() do
    local u16name = SU.utf8_to_utf16be_hexencoded(name)
    local u16desc = SU.utf8_to_utf16be_hexencoded(entry.description)
    local data
    if entry.content then
      data = entry.content
    else
      local file = io.open(entry.filename, "rb")
      if not file then
        SU.error("Could not open attachment file: " .. entry.filename)
      end
      data = file:read("*all")
      file:close()
    end

    n = n + 1 -- Attachment counter for fallback names if needed

    -- Build the PDF objects for this attachment...

    -- Create the embedded file stream
    -- <<
    --    /Type /EmbeddedFile
    --    /Subtype /application#2Foctet-stream  % As /MIME with #2F for internal slashes
    --    /Length LENGTH                        % Length of the data in bytes
    -- >>
    -- stream
    -- DATA                                     % Actual data
    -- endstream
    --
    -- NOTE: libtexpdf is able to handle compression of streams automatically and adds /Filter entries
    -- as needed, and also updates /Length accordingly.
    -- So we just create a simple uncompressed stream here, and the library will do the rest for us.
    local streamStr = table.concat({
      "<<",
        "/Type /EmbeddedFile",
        "/Subtype /" .. entry.mime:gsub("/", "#2F"),
        "/Length",
        string.len(data),
      ">>\nstream\n" .. data .. "\nendstream"
    }, " ")

    local stream = pdf.parse(streamStr)
    local streamRef1 = pdf.reference(stream) -- for /F entry in /EF dictionary
    local streamRef2 = pdf.reference(stream) -- for /UF entry in /EF dictionary
    pdf.release(stream)

    -- Create the file specification dictionary
    -- <<
    --   /Type /Filespec
    --   /F (...)                % File name (ASCII mandatory)
    --   /UF <...>               % Unicode file name (UTF-16BE hex-encoded), optional but we will always set it
    --   /Desc <...>             % Description (optional)
    --   /EF <<
    --         /F REF            % Object reference for the embedded file stream with ASCII name
    --         /UF REF           % Ooptional reference for the embedded file stream with Unicode name,
    --                           % Recommended to be present and identical to /F entry
    --       >>
    --   /AFRelationship /Data   % Relationship type (Data, Source, Supplement, Alternative, Unspecified)
    -- >>
    local ascname = isAsciiString(name)
      and name
      or ("attachment" .. n .. ".txt") -- Fallback to some placeholder name if not ASCII

    local fileStr = table.concat({
      "<<",
        "/Type /Filespec",
        "/F (" .. ascname .. ")",
        "/UF <" .. u16name .. ">",
        "/Desc <" .. u16desc .. ">",
        "/AFRelationship /" .. entry.relation,
      ">>"
    }, " ")
    local fileSpec = pdf.parse(fileStr)
    local efDict = pdf.parse("<< >>")
    pdf.add_dict(efDict, pdf.parse("/F"), streamRef1)
    pdf.add_dict(efDict, pdf.parse("/UF"), streamRef2)
    pdf.add_dict(fileSpec, pdf.parse("/EF"), efDict)

    local fileSpecRef1 = pdf.reference(fileSpec) -- for /AF array in Catalog
    local fileSpecRef2 = pdf.reference(fileSpec) -- for /Names array in /EmbeddedFiles in Catalog
    pdf.release(fileSpec)

    SU.debug("resilient.attachments", "Built attachment PDF objects for", name,
      entry.relation,
      entry.mime
    )

    attachments:update({
      [u16name] = {
        fileSpecRef1 = fileSpecRef1,
        fileSpecRef2 = fileSpecRef2
      }
    })

    -- Heuristic to detect Factur-X EN16931 XML attachment:
    --  - Name must be "factur-x.xml" (implied by some documents, if not mandated),
    --  - MIME "application/xml" and relation "Alternative"
    --  - Content must match CrossIndustryInvoice (CII) XML and EN16931 specification.
    local MAX_SNIFF_LENGTH = 1500
    if name == "factur-x.xml" then
      if entry.mime == "application/xml"
        and entry.relation == "Alternative"
        -- There are quite a lot of namespaces in a Factur-X XML invoice so anything shorter
        -- is unlikely to be one.
        and string.len(data) > MAX_SNIFF_LENGTH
      then
        local sniff = data:sub(1, MAX_SNIFF_LENGTH) -- To avoid trying to match too much
        if sniff:match("urn:cen%.eu:en16931:") ~= nil -- In GuidelineSpecifiedDocumentContextParameter
          and sniff:match("<%w*:?CrossIndustryInvoice") ~= nil -- Root element possibly namespaced
        then
          self._isFacturX = true
          SU.debug("resilient.attachments", "Detected Factur-X attachment", name)
        else
          SU.warn("Attachment 'factur-x.xml' does not appear to be a valid Factur-X XML invoice.")
        end
      else
        SU.warn("Attachment 'factur-x.xml' does not match expected MIME type or relation for Factur-X.")
      end
    end
  end
  return attachments
end

--- (Private) Output attachments to the PDF.
--
-- Called at the end of the document generation process.
--
-- It builds the necessary PDF structures to register all attachments:
--
--  - An /AF array in the Catalog dictionary (Associated Files, PDF/A).
--  - A /Names/EmbeddedFiles name tree in the Catalog dictionary (regular attachments).
--
-- The /Names/EmbeddedFiles name tree lists all embedded files for general use.
-- The /AF array lists all attachments considered as integral part of the document, and could
-- theoretically be a subset of the former.
-- PDF/A-3 however mandates that all attachments must be listed in the `/AF` array,
-- so we do not bother making a subset here.
--
function package:_outputAttachments ()
  SILE.outputter:_ensureInit()
  pdf = require("justenoughlibtexpdf")

  local attachments = self:_buildAttachments()
  local n = #attachments:keys()
  if n == 0 then
    SU.debug("resilient.attachments", "No attachments to output")
    return -- Nothing to do
  end
  SU.debug("resilient.attachments", "Outputting", n, "attachments to PDF")

  -- Build an /AF array (PDF/A-3 associated files, mandatory for invoices in Factur-X).
  -- /AF [
  --   REF            % Reference a to the file specification object
  -- ]
  local afArray = pdf.parse("[]")

  -- Build the dictionary of /Names for the /EmbeddedFiles entry (itself in a /Names dictionary in the Catalog).
  -- Yes, this is convoluted.
  -- PDF tools are based on it for listing and extracting attachments.
  -- E.g. this is what pdfdetach from the poppler utilities uses.
  -- <<
  --   /Names [
  --     <...> REF        % File name (UTF-16BE hex-encoded) and reference to file spec
  -- >>
  --
  -- IMPORTANT: Note that large trees should use /Kids and /Limits to split the name space,
  -- but we don't do that here. The limit is quite high anyway normally, and we will assume for now
  -- that we don't have that many attachments...
  local namesArray = pdf.parse("[]")

  for u16name, refs in attachments:iter() do
    pdf.push_array(afArray, refs.fileSpecRef1)
    pdf.push_array(namesArray, pdf.parse("<" .. u16name .. ">"))
    pdf.push_array(namesArray, refs.fileSpecRef2)
  end

  local namesDict = pdf.parse("<< >>")
  pdf.add_dict(namesDict, pdf.parse("/Names"), namesArray)
  local namesArrayRef = pdf.reference(namesDict)
  pdf.release(namesDict)

  -- The dictionary of /Names may already exist in the Catalog as it is also used
  -- for /JavaScript actions, /Dests named destinations, etc.
  -- Well, we are invoked before liibtexpdf finalizes the PDF, so usually those
  -- entries are not there yet, but let's be safe.
  -- /Names <<
  --    /EmbeddedFiles REF  % Reference to the names dictionary created above
  --    ...
  -- >>
  local catalog = pdf.get_dictionary("Catalog")
  local namesInCatalog = pdf.lookup_dictionary(catalog, "/Names")
  if not namesInCatalog then
    SU.debug("resilient.attachments", "Creating /Names in PDF Catalog")
    namesInCatalog = pdf.parse("<< >>")
    pdf.add_dict(catalog, pdf.parse("/Names"), namesInCatalog)
  else
    SU.debug("resilient.attachments", "Using existing /Names in PDF Catalog")
  end

  -- We don't expect other modules to also add attachments independently,
  -- so we won't check for an existing /EmbeddedFiles and /AF entries in
  -- the relevant dictionaries.
  SU.debug("resilient.attachments", "Creating /Names/EmbeddedFiles and /AF in PDF Catalog")
  pdf.add_dict(namesInCatalog, pdf.parse("/EmbeddedFiles"), namesArrayRef)
  pdf.add_dict(catalog, pdf.parse("/AF"), afArray)

  -- PDF/A full compliance mandates the presence of XMP metadata.
  -- PDF/A-3 furthermore requires that all attachments are listed there.
  local metadata = pdf.lookup_dictionary(catalog, "/Metadata")
  if metadata then
    -- SILE's libtexpdf does not add Metadata by default, so we don't expect this to happen.
    -- That is, unless other packages also added some XMP metadata...
    SU.error("PDF Metadata already exists in Catalog, but resilient.attachments cannot currently merge XMP metadata.")
    return
  end

  -- HACK: Claim PDF/A-3B compliance in the XMP metadata.
  -- Real PDF/A compliance requires more elements than currently handled.
  -- But A-3 is what we need for attaching arbitrary files, and B is the
  -- minimum level of compliance.
  local xmpContent = xmpMetadata(self._xmpDocumentKey, "3", "B", self._attachments, self._isFacturX)
  local xmpStreamStr = table.concat({
    "<<",
      "/Type /Metadata",
      "/Subtype /XML",
      "/Length",
      string.len(xmpContent),
    ">>\nstream\n" .. xmpContent .. "\nendstream"
  }, " ")
  local xmpStream = pdf.parse(xmpStreamStr)
  local xmpStreamRef = pdf.reference(xmpStream)
  pdf.release(xmpStream)
  -- NOTE: As of SILE 0.15.13, SILE's derived libtexpdf library compresses streams by default,
  -- above a certain size.
  -- PDF/A requires Metadata streams to be uncompressed (i.e. no /Filter entry).
  -- There's a fix in dvipfmx (dated 2016-06-25) to enforce that...
  SU.debug("resilient.attachments", "Creating /Metadata in PDF Catalog")
  pdf.add_dict(catalog, pdf.parse("/Metadata"), xmpStreamRef)
end

--- Register an attachment file.
--
-- In the PDF, the base name of the file will be used as the attachment name.
--
-- @tparam string filename File to attach
-- @tparam string|nil relation Relationship of the attachment ("Data", "Source", "Supplement", "Alternative", "Unspecified")
-- @tparam string|nil description Description of the attachment
-- @tparam string|nil mime MIME type of the attachment (guessed when not provided)
-- @tparam string|nil content When set, will be used as the attachment content instead of reading a file on disk.
function package:addAttachment (filename, relation, description, mime, content)
  if not self._hasAttachmentSupport then
    return
  end

  local name = pl.path.basename(filename) -- We don't want full paths as attachment names
  if self._attachments[name] then
    SU.error("Attachment base name already registered: " .. name)
  end

  if not content then
    -- We will read the content from disk, check it exists
    filename = SILE.resolveFile(filename) or SU.error("Attachment file not found: " .. filename)
  end
  description = description or "Unspecified" -- Optional, but we want something for compliance with some profiles.
  mime = mime or mimetypes.guess(name)
  if not mime then
    SU.warn("Unknown MIME type for attachment '" .. name .. "' (using application/octet-stream)")
    mime = "application/octet-stream"
  end
  relation = relation or "Data"

  self._attachments:update({
    [name] = {
      relation = relation,
      description = description,
      filename = filename,
      mime = mime,
      content = content,
    }
  })
end

local knownRelationSet = pl.Set({
  "Data", "Source", "Supplement", "Alternative", "Unspecified"
})

--- (Private) Add an attachment from a raw handler or command.
--
-- Common code for both the "attachment" raw handler and command
-- (parameter checking etc.).
--
-- @tparam table options Options Command or raw handler options
-- @tparam table|nil content Raw handler content, or nil for command
function package:_addAttachmentFromCommand (options, content)
  local filename = SU.required(options, "src", "attachment")
  local mime = options.mime
  if mime and not mime:match("^[%s%w%-%+%./]+$") then
    SU.error("Invalid characters in MIME type for attachment: " .. mime)
  end
  local relation = options.relation
  if relation and not knownRelationSet[relation] then
    SU.error("Unrecognized attachment relation: " .. relation)
  end
  self:addAttachment(filename, relation, options.description, mime, content and content[1])
end

--- (Override) Register all raw handlers provided by this package.
--
-- Currently provides an "attachment" raw handler.
--
function package:registerRawHandlers ()
  self:registerRawHandler("attachment", function (options, content)
    self:_addAttachmentFromCommand(options, content)
  end)
end

--- (Override) Register all commands provided by this package.
--
-- Currently provides an "attachment" command, and an "xmp-set-document" command.
--
function package:registerCommands ()

  self:registerCommand("attachment", function (options, _)
    self:_addAttachmentFromCommand(options)
  end)

  self:registerCommand("xmp-set-document", function (options, _)
    local key = SU.required(options, "key", "xmp-document-key")
    self._xmpDocumentKey = key
  end)

end

package.documentation = [[\begin{document}
The \autodoc:package{resilient.attachments} package allows attaching arbitrary files to the generated PDF.

It provides the \autodoc:command{\attachment} command and a raw handler of the same name.

Both take a mandatory \autodoc:parameter{src=<file name>} parameter to specify the file to attach.
In the case of the raw handler, the content of the raw block is used as the attachment content, and the file name is only used for the attachment name in the PDF.

An optional \autodoc:parameter{description=<text>} parameter may also be provided to specify a free-form description of the attachment.

An optional \autodoc:parameter{relation=<type>} parameter may also be provided to specify the relationship type of the attachment, as one of \code{Data} (assumed by default), \code{Source}, \code{Supplement}, \code{Alternative}, or \code{Unspecified}.
The most common case are \code{Data} for generic attachments, and \code{Alternative} for hybrid PDF/XML invoices such as Factur-X.
The \code{Source} type may be used to attach the original source document inside the PDF.
The other types are less commonly used.

An optional \autodoc:parameter{mime=<MIME type>} parameter may also be provided to specify the MIME type of the attachment.
If not provided, the MIME type is guessed from the file name extension.

The name of the attachment in the PDF will be the base name of the provided file name (without any path), and it must be unique.

Several tools can be used to list and extract attachments from a PDF file.
For instance, with the Poppler utilities:

\begin{itemize}
\item{List attachments with \code{pdfdetach -list myfile.pdf}}
\item{Extract all attachments with \code{pdfdetach -saveall myfile.pdf}}
\end{itemize}

\medskip
PDF/A-3 compliance requires that all attachments are listed in the XMP metadata of the PDF.
The XMP metadata include a DocumentID which should theoretically be unique to the logical document, and stable across generations of the same document.

The \autodoc:command{\xmp-set-document[key=<key>]} command may be used to pass a specific key to be used for generating the DocumentID.

\medskip
Note that attachments are only supported with SILE’s \code{libtexpdf} outputter, and are ignored otherwise.

\end{document}]]

return package
