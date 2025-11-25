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

-- --- Generate the XML snippet for associated files (embedded attachments).
-- --
-- -- CAVEAT: Do not use: Non-standard in PDF/A-3, and rejected by several validators.
-- -- I can't remember where I read that, but it's wrong visibly, or not mature.
-- -- We'll see what PDF/A-4 may bring, or not. It's funny that the XMP packet does
-- -- not seem to have a standardized way to declare associated files.
-- --
-- -- @tparam table attachments Hash map of attachments
-- -- @treturn string XML snippet for associated files
-- local function xmpAssociatedFiles (attachments)
--   if not attachments or next(attachments) == nil then
--     return ""
--   end
--   local liTags = {}
--   for name, entry in attachments:iter() do
--     liTags[#liTags+1] = string.format([[
--           <rdf:li rdf:parseType="Resource">
--             %s
--             %s
--             %s
--           </rdf:li>]],
--       xmlTagHelper("pdfaExtension:AFRelationship", {}, entry.relation),
--       xmlTagHelper("pdfaExtension:FileName", {}, name),
--       xmlTagHelper("pdfaExtension:MimeType", {}, entry.mime)
--     )
--   end
--   return string.format([[
--     <!-- Embedded files (associated files) -->
--     <rdf:Description xmlns:pdfaExtension="http://www.aiim.org/pdfa/ns/extension/" rdf:about="">
--       <pdfaExtension:associatedFiles>
--         <rdf:Bag>
-- %s
--         </rdf:Bag>
--       </pdfaExtension:associatedFiles>
--     </rdf:Description>]],
--     table.concat(liTags, "\n")
--   )
-- end

--- Generate the XMP Media Management XML snippet.
--
-- @tparam string documentUUID Document UUID
-- @tparam string instanceUUID Instance UUID
-- @treturn string XMP Media Management XML snippet
local function xmpMediaManagement (documentUUID, instanceUUID)
  return string.format([[
    <!-- XMP Media Management -->
    <rdf:Description xmlns:xmpMM="http://ns.adobe.com/xap/1.0/mm/" rdf:about="">
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
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <!-- PDF/A identification -->
    <rdf:Description xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/" rdf:about="">
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
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <!-- PDF/A identification -->
    <rdf:Description xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/" rdf:about="">
%s
    </rdf:Description>
    <!-- Required PDF/A extension schema declaration -->
    <rdf:Description xmlns:pdfaExtension="http://www.aiim.org/pdfa/ns/extension/"
                     xmlns:pdfaProperty="http://www.aiim.org/pdfa/ns/property#"
                     xmlns:pdfaSchema="http://www.aiim.org/pdfa/ns/schema#"
                     rdf:about="">
      <!-- Factur-X extension schema -->
      <pdfaExtension:schemas>
        <rdf:Bag>
          <rdf:li rdf:parseType="Resource">
            <pdfaSchema:schema>Factur-X extension schema</pdfaSchema:schema>
            <pdfaSchema:namespaceURI>urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#</pdfaSchema:namespaceURI>
            <pdfaSchema:prefix>fx</pdfaSchema:prefix>
            <pdfaSchema:property>
              <rdf:Seq>
                <rdf:li rdf:parseType="Resource">
                  <pdfaProperty:name>DocumentFileName</pdfaProperty:name>
                  <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                  <pdfaProperty:category>external</pdfaProperty:category>
                  <pdfaProperty:description>name of the embedded XML invoice file</pdfaProperty:description>
                </rdf:li>
                <rdf:li rdf:parseType="Resource">
                  <pdfaProperty:name>DocumentType</pdfaProperty:name>
                  <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                  <pdfaProperty:category>external</pdfaProperty:category>
                  <pdfaProperty:description>INVOICE</pdfaProperty:description>
                </rdf:li>
                <rdf:li rdf:parseType="Resource">
                  <pdfaProperty:name>Version</pdfaProperty:name>
                  <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                  <pdfaProperty:category>external</pdfaProperty:category>
                  <pdfaProperty:description>The actual version of the ZUGFeRD XML schema</pdfaProperty:description>
                </rdf:li>
                <rdf:li rdf:parseType="Resource">
                  <pdfaProperty:name>ConformanceLevel</pdfaProperty:name>
                  <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                  <pdfaProperty:category>external</pdfaProperty:category>
                  <pdfaProperty:description>The selected ZUGFeRD profile completeness</pdfaProperty:description>
                </rdf:li>
              </rdf:Seq>
            </pdfaSchema:property>
          </rdf:li>
        </rdf:Bag>
      </pdfaExtension:schemas>
    </rdf:Description>
    <!-- Factur-X core metadata -->
    <rdf:Description xmlns:fx="urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#" rdf:about="">
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
-- @tparam pl.OrderedMap _ Hash map of attachments (ignored currently)
-- @tparam boolean isFacturX Whether the document is a Factur-X invoice
-- @treturn string XMP metadata packet
local function xmpMetadata (documentKey, part, conformance, _, isFacturX)
  local xmpPDFAidSnippet = xmpPDFAIdentification(part, conformance)
  local documentUUID
  if not documentKey then
    SU.warn("XMP Metadata DocumentID is not deterministic as no document key was provided.")
    documentUUID = UUID.v5(UUID.v4())
  else
    documentUUID = UUID.v5(documentKey)
  end
  local instanceUUID = UUID.v4()

  local xmpMediaManagementSnippet = xmpMediaManagement(documentUUID, instanceUUID)
  -- local xmpAssociatedFilesSnippet = xmpAssociatedFiles(attachments) SEE COMMENT ABOVE
  local xmpContent
  if isFacturX then
    local xmpFacturXSnippet = string.format([[
      <fx:DocumentType>INVOICE</fx:DocumentType>
      <fx:DocumentFileName>factur-x.xml</fx:DocumentFileName>
      <fx:Version>1.0</fx:Version>
      <fx:ConformanceLevel>BASIC</fx:ConformanceLevel>]])
    xmpContent = string.format(
      XMPTemplateFacturX,
      xmpPDFAidSnippet,
      xmpFacturXSnippet,
      xmpMediaManagementSnippet,
      "" -- xmpAssociatedFilesSnippet SEE COMMENT ABOVE
    )
  else
    xmpContent = string.format(
      XMPTemplateSimple,
      xmpPDFAidSnippet,
      xmpMediaManagementSnippet,
      "" -- xmpAssociatedFilesSnippet SEE COMMENT ABOVE
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
