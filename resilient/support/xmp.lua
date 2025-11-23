--- Basic XMP metadata generation support for re·sil·ient.
--
-- @license MIT
-- @copyright (c) 2025 Omikhleia / Didier Willis
-- @module resilient.support.xmp

local UUID = require("resilient.uuid")

local function xmlEscape (s)
  s = tostring(s)
  s = s:gsub("&", "&amp;")
  s = s:gsub("<", "&lt;")
  s = s:gsub(">", "&gt;")
  s = s:gsub("'", "&apos;")
  s = s:gsub('"', "&quot;")
  return s
end

local function xmlTagHelper(tag, attributes, value)
  if not value then
    return "" -- Assumption: omit empty tags.
  end
  if type(value) == "table" then
    if value.year then
      -- Assume it's a date that was parsed with os.date(().
      -- (This is what the tinyyaml module we use for parsing does.)
      value = os.date("%Y%m%d", os.time(value)) -- Format "102" in Factur-X
    else
      SU.error("Factur-X XML generation: unsupported table value for tag " .. tag)
    end
  end
  local attributesStrs = {}
  for k, v in pairs(attributes) do
    attributesStrs[#attributesStrs+1] = k .. '="' .. v .. '"'
  end
  local sattributes = ""
  if #attributesStrs > 0 then
    sattributes = " " .. table.concat(attributesStrs, " ")
  end
  return "<" .. tag .. sattributes .. ">" .. xmlEscape(value) .. "</" .. tag .. ">"
end

-- Hash map of attachments from the resilient.attachments package.
--   name -> {
--     relation = string,
--     mime = string,
--     ...
--   }

--- Generate the XML snippet for associated files (embedded attachments).
--
-- @tparam table attachments Hash map of attachments
-- @treturn string XML snippet for associated files
local function xmpAssociatedFiles (attachments)
  if not attachments or next(attachments) == nil then
    return ""
  end
  local liTags = {}
  for name, entry in attachments:iter() do
    liTags[#liTags+1] = string.format([[
          <rdf:li rdf:parseType="Resource">
            %s
            %s
            %s
          </rdf:li>]],
      xmlTagHelper("pdfaExt:AFRelationship", {}, entry.relation),
      xmlTagHelper("pdfaExt:FileName", {}, name),
      xmlTagHelper("pdfaExt:MimeType", {}, entry.mime)
    )
  end
  return string.format([[
    <!-- Embedded files (associated files) -->
    <rdf:Description rdf:about="">
      <pdfaExt:associatedFiles>
        <rdf:Bag>
%s
        </rdf:Bag>
      </pdfaExt:associatedFiles>
    </rdf:Description>]],
    table.concat(liTags, "\n")
  )
end

--- Generate the XMP Media Management XML snippet.
--
-- @tparam string documentUUID Document UUID
-- @tparam string instanceUUID Instance UUID
-- @treturn string XMP Media Management XML snippet
local function xmpMediaManagement (documentUUID, instanceUUID)
  return string.format([[
    <!-- XMP Media Management -->
    <rdf:Description rdf:about="">
      %s
      %s
    </rdf:Description>]],
    xmlTagHelper("xmpMM:DocumentID", {}, documentUUID),
    xmlTagHelper("xmpMM:InstanceID", {}, instanceUUID)
  )
end

--- Wrap content in an XMP packet.
--
-- @tparam string content XML content
-- @treturn string Complete XMP packet
local function xmpPacket (content)
  local BOM = "\xEF\xBB\xBF" -- U+FEFF BOM
  -- As far as I understand, the id can be arbitrary,
  -- but many tools use "W5M0MpCehiHzreSzNTczkc9d" as Adobe does.
  return table.concat({
    '<?xpacket begin="', BOM, '" id="W5M0MpCehiHzreSzNTczkc9d"?>\n',
    content,
    '<?xpacket end="w"?>\n',
  })
end

local XMPTemplateSimple = [[
<x:xmpmeta xmlns:x="adobe:ns:meta/">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
           xmlns:xmpMM="http://ns.adobe.com/xap/1.0/mm/"
           xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/"
           xmlns:pdfaExt="http://www.aiim.org/pdfa/ns/extension/">
    <!-- PDF/A identification -->
    <rdf:Description rdf:about="">
%s
    </rdf:Description>
%s
%s
  </rdf:RDF>
</x:xmpmeta>
]]

-- I extracted this from a Factur-X file I found online.
-- It seems to be the minimal set of tags required.
-- I haven't checked the specification.
local XMPTemplateFacturX = [[
<x:xmpmeta xmlns:x="adobe:ns:meta/">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
           xmlns:fx="urn:ferd:pdfa:CrossIndustryDocument:invoice:1p0#"
           xmlns:xmpMM="http://ns.adobe.com/xap/1.0/mm/"
           xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/"
           xmlns:pdfaExt="http://www.aiim.org/pdfa/ns/extension/">
    <!-- PDF/A identification -->
    <rdf:Description rdf:about="">
%s
    </rdf:Description>
    <!-- Factur-X core metadata -->
    <rdf:Description rdf:about="">
%s
    </rdf:Description>
%s
%s
  </rdf:RDF>
</x:xmpmeta>
]]

--- Generate the PDF/A identification XML snippet.
--
-- PDF/A-1 only supports conformance level B.
-- Conformaance A and U were introduced in PDF/A-2.
--
-- Parts:
--
--  - PDF/A-1 Based on PDF 1.4, no transparency, no embedded files, strict, basic archival.
--  - PDF/A-2 Based on PDF 1.7, transparency, layers, JPEG2000, better compression.
--  - PDF/A-3 = PDF/A-2 but allows embedding arbitrary file formats.
--
--  Conformance levels:
--
--  - A (Accessible) = tagged PDF for accessibility. Implies B.
--  - U (Unicode) = Unicode text mapping. Implies B.
--  - B (Basic) = visual fidelity only.
--
-- @tparam string part PDF/A part (e.g., "3")
-- @tparam string conformance PDF/A conformance level (e.g., "B")
-- @treturn string PDF/A identification XML snippet
local function xmpPDFAIdentification (part, conformance)
  return string.format([[
      <pdfaid:part>%s</pdfaid:part>
      <pdfaid:conformance>%s</pdfaid:conformance>]],
    part,
    conformance
  )
end

--- Generate the XMP metadata packet.
--
-- @tparam string|nil documentKey Document Key (deterministic)
-- @tparam string part PDF/A part (e.g., "3")
-- @tparam string conformance PDF/A conformance level (e.g., "B")
-- @tparam pl.OrderedMap attachments Hash map of attachments
-- @tparam boolean isFacturX Whether the document is a Factur-X invoice
-- @treturn string XMP metadata packet
local function xmpMetadata (documentKey, part, conformance, attachments, isFacturX)
  local xmpPDFAidSnippt = xmpPDFAIdentification(part, conformance)
  local documentUUID
  if not documentKey then
    SU.warn("XMP Metadata DocumentID is not deterministic as no document key was provided.")
    documentUUID = UUID.v5(UUID.v4())
  else
    documentUUID = UUID.v5(documentKey)
  end
  local instanceUUID = UUID.v4()

  local xmpMediaManagementSnippet = xmpMediaManagement(documentUUID, instanceUUID)
  local xmpAssociatedFilesSnippet = xmpAssociatedFiles(attachments)
  local xmpContent
  if isFacturX then
    local xmpFacturXSnippet = string.format([[
      <fx:DocumentType>INVOICE</fx:DocumentType>
      <fx:DocumentFileName>factur-x.xml</fx:DocumentFileName>
      <fx:Version>1.0</fx:Version>
      <fx:ConformanceLevel>BASIC</fx:ConformanceLevel>]])
    xmpContent = string.format(
      XMPTemplateFacturX,
      xmpPDFAidSnippt,
      xmpFacturXSnippet,
      xmpMediaManagementSnippet,
      xmpAssociatedFilesSnippet
    )
  else
    xmpContent = string.format(
      XMPTemplateSimple,
      xmpPDFAidSnippt,
      xmpMediaManagementSnippet,
      xmpAssociatedFilesSnippet
    )
  end
  return xmpPacket(xmpContent)
end

--- @export
return {
  xmpMetadata = xmpMetadata,
}

-- Known mandatory XMP metadata elements for PDF/A-3B compliance, missing from our current implementation:
--       <!-- Dublin Core metadata -->
--       <dc:title>
--         <rdf:Alt>
--           <rdf:li xml:lang="x-default">Sample PDF/A-3 Document</rdf:li>
--           <!-- Same as /Title in Info dictionary -->
--         </rdf:Alt>
--       </dc:title>
--       <dc:creator>
--         <rdf:Seq>
--           <rdf:li>Author Name</rdf:li>
--           <!-- Same as /Author in Info dictionary -->
--         </rdf:Seq>
--       </dc:creator>
--       <dc:description>
--         <rdf:Alt>
--           <rdf:li xml:lang="x-default">A short description of the PDF/A-3 document.</rdf:li>
--           <!-- Optional but same as /Subject in Info dictionary -->
--         </rdf:Alt>
--       </dc:description>
--       <dc:date>
--         <rdf:Seq>
--           <rdf:li>2025-11-21T12:00:00Z</rdf:li>
--           <!-- Same as /CreationDate in Info dictionary -->
--         </rdf:Seq>
--       </dc:date>
--
--       <!-- XMP tool metadata -->
--       <xmp:CreatorTool>...</xmp:CreatorTool><!-- In our case, same as /Producer in Info dictionary -->
--       <xmp:CreateDate>2025-11-21T12:00:00Z</xmp:CreateDate><!-- Same as /CreationDate in Info dictionary -->
--       <xmp:ModifyDate>2025-11-21T12:00:00Z</xmp:ModifyDate><!-- Same as /ModDate in Info dictionary, and on new files, ModDate = CreationDate -->
--       <xmp:MetadataDate>2025-11-21T12:00:00Z</xmp:MetadataDate><!-- Same as /ModDate in Info dictionary -->
--
--       <!-- PDF producer info -->
--       <pdf:Producer>...</pdf:Producer><!-- Same as /Producer in Info dictionary -->
