--- A master file support module for re·sil·ient.
--
-- The master file document is a YAML file that describes the document structure,
-- metadata, bibliography, book covers, title pages, endpapers, etc.
--
-- @license MIT
-- @copyright (c) 2023-2025 Omikhleia / Didier Willis
-- @module inputters.silm

SILE.registerCommand("has:book-title-support", function (_, content)
  -- Fairly lame command detection
  if SILE.Commands["book-title"] then
    -- At least resilient.book will do something
    SILE.call("book-title", {}, content)
  end
  -- I am not going to care for the core book class...
end, nil, nil, true) -- HACK (*sigh*)

-- SCHEMA VALIDATION
-- Loosely inspired from JSON schema / openAPI specs

local OptionsSchema = {
  type = "object",
  additionalProperties = {
    type = { -- oneOf
      { type = "string" },
      { type = "boolean" },
      { type = "number" },
    },
  },
  properties = {}
}

local FileSchema = {
  type = "object",
  properties = {
    file = { type = "string" },
    format = { type = "string" },
    options = OptionsSchema
  }
}

local SingleFileSchema = {
  type = { -- oneOf
    { type = "string" },
    FileSchema
  }
}

local CaptionSchema = {
  type = "object",
  properties = {
    caption = { type = "string" },
  }
}

local ContentCaptionSchema = pl.tablex.deepcopy(CaptionSchema)
local ContentFileSchema = pl.tablex.deepcopy(FileSchema)
local ContentSchema = {
  type = "array",
  items = {
    type = { -- oneOf
      { type = "string" },
      ContentCaptionSchema,
      ContentFileSchema,
    }
  }
}
-- Recursive content
ContentCaptionSchema.properties.content = ContentSchema
ContentFileSchema.properties.content = ContentSchema

local InPartCaptionSchema = pl.tablex.deepcopy(CaptionSchema)
local InPartFileSchema = pl.tablex.deepcopy(FileSchema)
-- Recursive structured content
InPartCaptionSchema.properties.chapters = ContentSchema
InPartCaptionSchema.properties.appendices = ContentSchema
InPartFileSchema.properties.chapters = ContentSchema
InPartFileSchema.properties.appendices = ContentSchema
local ContentInPartSchema = {
  type = "array",
  items = {
    type = { -- oneOf
      { type = "string" },
      ContentCaptionSchema,
      ContentFileSchema,
      InPartCaptionSchema,
      InPartFileSchema,
    }
  }
}

local BookSchema = {
  type = "object",
  properties = {
    enabled = { type = "boolean" },
    cover = {
      type = "object",
      properties = {
        image = { type = "string" },
        background = { type = "string" },
        front = {
          type = "object",
          properties = {
            image = { type = "string" },
            background = { type = "string" },
            template = { type = "string" },
          }
        },
        back = {
          type = "object",
          properties = {
            image = { type = "string" },
            background = { type = "string" },
            content = SingleFileSchema,
            ['content-background'] = { type = "string" },
          }
        }
      }
    },
    halftitle = {
      type = "object",
      properties = {
        recto = { type = "string" },
        verso = { type = "string" }
      }
    },
    title = {
      type = "object",
      properties = {
        recto = { type = "string" },
        verso = { type = "string" }
      }
    },
    endpaper = {
      type = "object",
      properties = {
        recto = { type = "string" },
        verso = { type = "string" }
      }
    }
  }
}

local BibliographySchema = {
  type = "object",
  properties = {
    style = { type = "string" },
    language = { type = "string" },
    files = {
      type = { -- oneOf
        { type = "string" },
        { type = "array", items = { type = "string" } },
      },
    },
  }
}

local MetaDataSchema = {
  type = "object",
  properties = {
    title = { type = "string" },
    subtitle = { type = "string" },
    subject = { type = "string" },
    keywords = {
      type = { -- oneOf
        { type = "string" },
        { type = "array", items = { type = "string" } },
      },
    },
    authors = {
      type = { -- oneOf
        { type = "string" },
        { type = "array", items = { type = "string" } },
      },
    },
    translators = { -- oneOf
      type = "string",
      items = { type = "string" }
    },
    publisher = { type = "string" },
    pubdate = {
      type = "object",
      -- tinyyaml converts dates to osdate objects
      -- We don't care about hours, minutes, etc.
      additionalProperties = true,
      properties = {
        year = { type = "number" },
        month = { type = "number" },
        day = { type = "number" }
      }
    },
    isbn = { type = "string" },
    url = { type = "string" },
    copyright = { type = "string" },
    legal = { type = "string" },
  }
}

local FontSchema = {
  type = "object",
  properties = {
    family = {
      type = { -- oneOf
        { type = "string" },
        { type = "array", items = { type = "string" } },
      },
    },
    size = { type = "string" }
  }
}

local SileConfigurationSchema = {
  type = "object",
  properties = {
    options = {
      type = "object",
      properties = {
        class = { type = "string" },
        papersize = { type = "string" },
        layout = { type = "string" },
        resolution = { type = "number" },
        headers = { type = "string" },
        offset = { type = "string" },
      }
    },
    settings = {
      type = "object",
      -- Allow any setting without validation
      additionalProperties = true,
      properties = {
      }
    },
    packages = {
      type = "array",
      items = { type = "string" }
    }
  }
}

local PartPropertiesSchema = {
  type = "object",
  properties = {
    parts = ContentInPartSchema,
  }
}

local ChapterAppendicesSchema = {
  type = "object",
  properties = {
    chapters = ContentSchema,
    appendices = ContentSchema,
  }
}

local PartOrChapterSchema = {
  type = { -- oneOf
    PartPropertiesSchema,
    ChapterAppendicesSchema,
  }
}

local StructuredContentSchema = {
  type = { -- oneOf
    PartPropertiesSchema,
    ChapterAppendicesSchema,
    { type = "object",
      properties = {
        frontmatter = PartOrChapterSchema,
        mainmatter = PartOrChapterSchema,
        backmatter = PartOrChapterSchema,
      }
    },
  }
}

local MasterSchema = {
  type = "object",
  additionalProperties = true, -- Allow unknown property for extensibility
  properties = {
    masterfile = {
      type = "number",
    },
    metadata = MetaDataSchema,
    font = FontSchema,
    language = { type = "string" },
    sile = SileConfigurationSchema,
    book = BookSchema,
    bibliography = BibliographySchema,
    -- Legacy compatibility:
    -- We can have parts and chapters at the root level.
    -- parts, chapters and content are mutually exclusive, but we don't enforce it here.
    -- We will check it later in the inputter
    parts = ContentInPartSchema,
    chapters = ContentSchema,
    -- New recommended way:
    -- content can have parts, chapters or a structured content (frontmatter, mainmatter, backmatter
    -- divisons)
    content = StructuredContentSchema,
  }
}

--- Naive recursive schema validation
--
-- @tparam table obj Parsed YAML object
-- @tparam table schema Schema to validate against
-- @tparam[opt] table context Parent schema context for error messages
-- @treturn boolean Whether the object is valid as per the schema
-- @treturn string|nil Error message if not valid
local function validate (obj, schema, context)
  context = context or ""
  if type(schema.type) == "table" then
    -- oneOf type
    local oneOfMatched = false
    for _, v in ipairs(schema.type) do
      oneOfMatched = validate(obj, v, context)
      if oneOfMatched then
        break
      end
    end
    if not oneOfMatched then
      local ts = pl.tablex.map(function (t)
        return t.type == "array" and "array of " .. t.items.type or t.type
      end, schema.type)
      return false, context .. " must match one of " .. table.concat(ts, ", ")
     end
    return true
  elseif schema.type ~= "array" and schema.type ~= "object" then
    -- primitive type
    if type(obj) ~= schema.type then
      return false, context .. " must be of type " .. schema.type
    end
    return true
  elseif schema.type == "array" then
    -- array type
    if type(obj) ~= "table" then
      return false, context .. " must be an array"
    end
    for key, val in pairs(obj) do
      if type(key) ~= "number" then
        return false, context .. "." .. key .. " is invalid ("
          .. context .. " must be an array)"
      end
      local ok, err = validate(val, schema.items, context .. "." .. key)
      if not ok then
        return false, err
      end
    end
    return true
  elseif schema.type == "object" then
    if type(obj) ~= "table" then
      return false, context .. " must be an object"
    end
    for key, val in pairs(obj) do
      local field = context .. "." .. key or key
      if not schema.properties[key] then
        if not schema.additionalProperties then
          return false, field .. " is not expected in " .. context
        end
      else
        local ok, err = validate(val, schema.properties[key], field)
        if not ok then
          return false, err
        end
      end
    end
    return true
  end
  -- Should not reach this point
  return false, "Internal error - Unknown schema type" .. schema.type
end

-- Metadata

local knownPdfMetadata = {
  title = "Title",
  subject = "Subject",
  keywords = "Keywords",
  authors = "Author",
}

--- Insert PDF metadata into SILE AST
--
-- @tparam table content SILE AST for insertion
-- @tparam table metadata Metadata (key, value) table
local function insertPdfMetadata (content, metadata)
  for key, value in pairs(metadata) do
    if knownPdfMetadata[key] then
      content[#content+1] = SU.ast.createCommand("pdf:metadata", {
        key = knownPdfMetadata[key],
        value = type(value) == "table" and table.concat(value, "; ") or value
      })
    end
  end
end

--- Returned prepared Djot metadata
--
-- @tparam table metadata Metadata (key, value) table
-- @treturn table Prefixed metadata table (keys as expected by the Djot inputter)
local function handleDjotMetadata (metadata)
  local meta = {}
  for key, value in pairs(metadata) do
    if key == "authors" then
      if type(value) == "table" then
        meta["meta:authors"] = table.concat(value, ", ")
        meta["meta:author"] = value[1]
      else
        meta["meta:authors"] = value
        meta["meta:author"] = value
      end
    elseif key == "translators" then
      if type(value) == "table" then
        meta["meta:translators"] = table.concat(value, ", ")
        meta["meta:translator"] = value[1]
      else
        meta["meta:translators"] = value
        meta["meta:translator"] = value
      end
    elseif key == "pubdate" then
      meta["meta:pubdate"] = os.date("%Y-%m-%d", os.time(value)) -- back to string
      meta["meta:pubdate-year"] = tostring(value.year)
      meta["meta:pubdate-month"] = tostring(value.month)
      meta["meta:pubdate-day"] = tostring(value.day)
    else
      meta["meta:" .. key] = type(value) == "table" and table.concat(value, ", ") or value
    end
  end
  return meta
end

local Levels = { "part", "chapter", "section", "subsection", "subsubsection" }

--- Recursively process content sections
--
-- @tparam table content SILE AST for insertion
-- @tparam table entries Content entries to process (list of strings or tables)
-- @tparam number shiftHeadings Shift headings by this amount
-- @tparam table metaopts Metadata options
local function doLevel (content, entries, shiftHeadings, metaopts)
  for _, entry in ipairs(entries) do
    local spec
    if type(entry) == "string" then
      spec = pl.tablex.union(metaopts, {
        src = entry,
        shift_headings = shiftHeadings })
      content[#content+1] = SU.ast.createCommand("include", spec)
    elseif entry.file then
      local fullopts = entry.options and pl.tablex.union(entry.options, metaopts) or metaopts
      spec = pl.tablex.union(fullopts, {
        src = entry.file,
        format = entry.format,
        shift_headings = shiftHeadings })
      content[#content+1] = SU.ast.createCommand("include", spec)
      if entry.content then
        doLevel(content, entry.content, shiftHeadings + 1, metaopts)
      end
      -- Top-level or part-level content, enforced by the schema
      if entry.chapters then
        doLevel(content, entry.chapters, shiftHeadings + 1, metaopts)
      end
      if entry.appendices then
        content[#content+1] = SU.ast.createCommand("appendix")
        doLevel(content, entry.appendices, shiftHeadings + 1, metaopts)
      end
    elseif entry.caption then
      local command = Levels[shiftHeadings + 2] or SU.error("Invalid master document (too many nested levels)")
      content[#content+1] = SU.ast.createCommand(command, {}, entry.caption)
      if entry.content then
        doLevel(content, entry.content, shiftHeadings + 1, metaopts)
      end
      -- Top-level or part-level content, enforced by the schema
      if entry.chapters then
        doLevel(content, entry.chapters, shiftHeadings + 1, metaopts)
      end
      if entry.appendices then
        content[#content+1] = SU.ast.createCommand("appendix")
        doLevel(content, entry.appendices, shiftHeadings + 1, metaopts)
      end
    elseif entry.content then
      doLevel(content, entry.content, shiftHeadings + 1, metaopts)
    end
  end
end

--- Process division content (parts or chapters/appendices)
--
-- @tparam table content SILE AST for insertion
-- @tparam table entry Division content entry
-- @tparam number shiftHeadings Shift headings by this amount
-- @tparam table metaopts Metadata options
local function doDivisionContent (content, entry, shiftHeadings, metaopts)
  if entry.parts then
    doLevel(content, entry.parts, shiftHeadings - 1, metaopts)
  else
    if entry.chapters then
      doLevel(content, entry.chapters, shiftHeadings, metaopts)
    end
    if entry.appendices then
      content[#content+1] = SU.ast.createCommand("appendix")
      doLevel(content, entry.appendices, shiftHeadings, metaopts)
    end
  end
end

--- Process divisions (frontmatter, mainmatter, backmatter)
--
-- @tparam table content SILE AST for insertion
-- @tparam table entry Division content entry
-- @tparam number shiftHeadings Shift headings by this amount
-- @tparam table metaopts Metadata options
local function doDivision (content, entry, shiftHeadings, metaopts)
  if entry.frontmatter then
    content[#content+1] = SU.ast.createCommand("frontmatter")
    doDivisionContent(content, entry.frontmatter, shiftHeadings, metaopts)
  end
  if entry.mainmatter then
    content[#content+1] = SU.ast.createCommand("mainmatter")
    doDivisionContent(content, entry.mainmatter, shiftHeadings, metaopts)
  end
  if entry.backmatter then
    content[#content+1] = SU.ast.createCommand("backmatter")
    doDivisionContent(content, entry.backmatter, shiftHeadings, metaopts)
  end
end

--- Process back cover content (text included in the back cover)
---@tparam table|string entry  Back cover content entry
---@tparam table metaopts Metadata options
---@treturn table SILE AST for insertion
local function doBackCoverContent (entry, metaopts)
  local content
  local spec
  if not entry then
    content = {}
  elseif type(entry) == "string" then
    spec = pl.tablex.union(metaopts, { src = entry })
    content = SU.ast.createCommand("include", spec)
  elseif entry.file then
    local fullopts = entry.options and pl.tablex.union(entry.options, metaopts) or metaopts
    spec = pl.tablex.union(fullopts, {
      src = entry.file,
      format = entry.format })
    content = SU.ast.createCommand("include", spec)
  else
    SU.error("Invalid master document (invalid cover content)")
  end
  return content
end

-- INPUTTER

--- The "master file" inputter for re·sil·ient.
--
-- Extends SILE's `inputters.base`.
--
-- @type inputters.silm

local base = require("inputters.base")

local inputter = pl.class(base)
inputter._name = "silm"
inputter.order = 2

--- (Override) Whether this inputter is appropriate for the given file.
--
-- @tparam number round Detection round (1 = by extension, etc.)
-- @tparam string filename Filename
-- @tparam string _ Document content (not used here)
-- @treturn boolean Whether this inputter is appropriate
function inputter.appropriate (round, filename, _)
  if round == 1 then
    return filename:match("silm$")
  end
  -- No other round supported...
  -- TODO QUESTION:
  -- We could check syntax (YAML file with masterfile field, at least),
  -- but there's no way it seems to properly cache the result and avoid
  -- re-reading the file at later parsing...
  return false
end

--- (Override) Parse the given document and return a SILE AST.
--
-- @tparam string doc Document content
function inputter:parse (doc)
  local yaml = require("resilient-tinyyaml")
  local master = yaml.parse(doc)
  if type(master) ~= "table" then
    SU.error("Invalid master document (not a table)")
  end
  local ok, err = validate(master, MasterSchema)
  if not ok then
    SU.error("Invalid master document (" .. err .. ")")
  end
  if master.parts and master.chapters then
    SU.error("Invalid master document (both parts and chapters)")
  end

  local baseShiftHeadings = self.options.shift_headings or 0
  local content = {}

  -- Are we the root document, or some included subdocument?
  -- in the latter case, we only honor some of the fields.
  local isRoot = not SILE.documentState.documentClass

  if isRoot then
    -- Document global settings
    if master.font then
      if type(master.font.family) == "table" then
        content[#content+1] = SU.ast.createCommand("use", {
          module = "packages.font-fallback"
        })
        content[#content+1] = SU.ast.createCommand("font", {
          family = master.font.family[1],
          size = master.font.size
        })
        for i = 2, #master.font.family do
          content[#content+1] = SU.ast.createCommand("font:add-fallback", {
            family = master.font.family[i],
          })
        end
      else
        content[#content+1] = SU.ast.createCommand("font", {
          family = master.font.family,
          size = master.font.size
        })
      end
    end
    -- TODO QUESTION: I start too think that main language should
    -- be class option so that some decisions could be delegated to
    -- the class (e.g. style overrides in the case of resilient classes)
    -- Not sure how to behave with legacy classes though...
    if master.language then
      content[#content+1] = SU.ast.createCommand("language", {
        main = master.language
      })
    end
  end
  -- TODO QUESTION: if not a root document, should we wrap the includes
  -- in a language group? Mixing documents with different languages
  -- is probably not a good idea, anyhow...

  local sile = master.sile or {}
  local metadata = master.metadata or {}
  local packages = sile.packages or {}

  if packages then
    for _, pkg in ipairs(packages) do
      content[#content+1] = SU.ast.createCommand("use", {
        module = "packages." .. pkg
      })
    end
  end

  if isRoot then
    local settings = sile.settings or {}
    if settings then
      for k, v in pairs(settings) do
        content[#content+1] = SU.ast.createCommand("set", {
          parameter = k,
          value = v
        })
      end
    end
    if SU.boolean(self.options.cropmarks, false) then
      content[#content+1] = SU.ast.createCommand("use", {
        module = "packages.cropmarks"
      })
      content[#content+1] = SU.ast.createCommand("cropmarks:setup")
    end
    if metadata.title then
      content[#content+1] = SU.ast.createCommand("has:book-title-support", {}, { metadata.title })
    end
    if master.bibliography then
      local bibfiles = master.bibliography.files
      if type(bibfiles) == "string" then
        bibfiles = { bibfiles }
      end
      content[#content+1] = SU.ast.createCommand("use", {
        module = "packages.bibtex"
      })
      if #bibfiles > 0 then
        local lang = master.bibliography.language or master.language or "en-US"
        local style = master.bibliography.style or "chicago-author-date"
        content[#content+1] = SU.ast.createCommand("bibliographystyle", {
          style = style,
          lang = lang
        })
        for _, bibfile in ipairs(bibfiles) do
          content[#content+1] = SU.ast.createCommand("loadbibliography", {
            file = bibfile
          })
        end
      end
    end
  end

  local metadataOptions = handleDjotMetadata(metadata)

  local bookmatter = master.book or {}
  bookmatter = {
    halftitle = bookmatter.halftitle or {},
    title = bookmatter.title or {},
    endpaper = bookmatter.endpaper or {},
    cover = bookmatter.cover,
    enabled = SU.boolean(bookmatter.enabled, false)
  }
  local enabledBook = isRoot and SU.boolean(self.options.bookmatter, bookmatter.enabled)
  local enabledCover = isRoot and SU.boolean(self.options.cover, bookmatter.enabled)

  if enabledBook or enabledCover then
    content[#content+1] = SU.ast.createCommand("use", {
      module = "packages.resilient.bookmatters"
    })
  end

  if enabledCover and bookmatter.cover then
    local cover = bookmatter.cover.front
    content[#content+1] = SU.ast.createCommand("bookmatters:front-cover", {
      image = cover and cover.image or bookmatter.cover.image,
      background = cover and cover.background or bookmatter.cover.background,
      template = cover and cover.template,
      metadata = metadataOptions
    })
  end

  if enabledBook then
    content[#content+1] = SU.ast.createCommand("bookmatters:template", {
      recto = bookmatter.halftitle.recto or "halftitle-recto",
      verso = bookmatter.halftitle.verso or "halftitle-verso",
      metadata = metadataOptions
    })
    content[#content+1] =  SU.ast.createCommand("bookmatters:template", {
      recto = bookmatter.title.recto or "title-recto",
      verso = bookmatter.title.verso or "title-verso",
      metadata = metadataOptions
    })
  end

  if master.content then
    if master.content.frontmatter or master.content.mainmatter or master.content.backmatter then
      doDivision(content, master.content, baseShiftHeadings, metadataOptions)
    elseif master.content.parts or master.content.chapters or master.content.appendices then
      -- Assume (implicit) mainmatter
      doDivisionContent(content, master.content, baseShiftHeadings, metadataOptions)
    end
  elseif master.parts or master.chapters or master.appendices then
    -- Before we introduced the "content" field for a cleaner hierarchical structure,
    -- we accepted parts or chapter directly at the root of the master file.
    -- Let's keep that (now undocumented) possibility for backward compatibility.
    doDivisionContent(content, master, baseShiftHeadings, metadataOptions)
  end

  if enabledBook then
    content[#content+1] = SU.ast.createCommand("bookmatters:template", {
      recto = bookmatter.endpaper.recto or "endpaper-recto",
      verso = bookmatter.endpaper.verso or "endpaper-verso",
      metadata = metadataOptions
    })
  end
  if enabledCover and bookmatter.cover then
    local cover = bookmatter.cover.back
    local background = cover and cover.background or bookmatter.cover.background
    local coverContent = cover and cover.content or nil
    content[#content+1] = SU.ast.createCommand("bookmatters:back-cover", {
      image = cover and cover.image or bookmatter.cover.image,
      background = background,
      bgcontent = cover and cover["content-background"] or background,
      metadata = metadataOptions
    }, doBackCoverContent(coverContent, metadataOptions))
  end

  if isRoot then
    -- PDF metadata
    -- NOTE: inserted at the very end of the document because (at least in SILE 0.14)
    -- it introduces hboxes than can affect indents, centering, page breaks and paragraphs...
    insertPdfMetadata(content, metadata)
  end

  -- Document wrap-up
  local options = sile.options or {}
  local classopts = isRoot and {
      class = options.class or "resilient.book", -- Sane default. We Are Resilient.
      papersize = options.papersize,
      layout = options.layout,
      resolution = options.resolution,
      headers = options.headers,
      offset = options.offset,
    } or {}

  local tree = {
    SU.ast.createStructuredCommand("document", classopts, content),
  }
  return tree
end

return inputter
