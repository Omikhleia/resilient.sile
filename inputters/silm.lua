--- Some YAML master file inputter for SILE
--
-- @copyright License: MIT (c) 2023 Omikhleia
-- @module inputters.silm
--
local ast = require("silex.ast")
local createCommand, createStructuredCommand = ast.createCommand, ast.createStructuredCommand

-- SCHEMA VALIDATION
-- Loosely inspired from JSON schema / openAPI specs

local OptionSchema = {
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

local contentSchema = {
  type = "array",
  items = {
    type = { -- oneOf
      { type = "string" },
      { type = "object",
        properties = {
          caption = { type = "string" },
          -- content (self reference, handled below)
        }
      },
      { type = "object",
        properties = {
          file = { type = "string" },
          format = { type = "string" },
          options = OptionSchema,
          -- content (self reference, handled below)
        }
      }
    }
  }
}
contentSchema.items.type[2].properties.content = contentSchema
contentSchema.items.type[3].properties.content = contentSchema

local masterSchema = {
  type = "object",
  additionalProperties = true, -- Allow unknown property for extensibility
  properties = {
    masterfile = {
      type = "number",
    },
    metadata = {
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
    },
    font = {
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
    },
    language = { type = "string" },
    sile = {
      type = "object",
      properties = {
        options = {
          type = "object",
          properties = {
            class = { type = "string" },
            papersize = { type = "string" },
            layout = { type = "string" },
            resolution = { type = "number" }
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
    },
    -- parts and chapters are exclusive, but we don't enforce it here.
    -- We will check it later in the inputter
    parts = contentSchema,
    chapters = contentSchema
  }
}

--- Naive recursive schema validation
---@param obj table parsed YAML object
---@param schema table schema to validate against
---@param context? table parent schema context for error messages
---@return boolean, string true if valid, false and error message otherwise
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

local pdfMetadata = {
  title = "Title",
  subject = "Subject",
  keywords = "Keywords",
  authors = "Author",
}

--- Insert PDF metadata into SILE AST
---@param content table SILE AST for insertion
---@param metadata table Metadata (key, value) table
local function insertPdfMetadata (content, metadata)
  for key, value in pairs(metadata) do
    if pdfMetadata[key] then
      content[#content+1] = createCommand("pdf:metadata", {
        key = pdfMetadata[key],
        value = type(value) == "table" and table.concat(value, "; ") or value
      })
    end
  end
end

--- Returned prepared Djot metadata
---@param metadata table Metadata (key, value) table
---@return table Prefixed metadata table (keys as expected by the Djot inputter)
local function handleDjotMetadata (metadata) -- Naive approach
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
    else
      meta["meta:" .. key] = type(value) == "table" and table.concat(value, ", ") or value
    end
  end
  return meta
end

local Levels = { "part", "chapter", "section", "subsection", "subsubsection" }

--- Recursively process content sections
---@param content table SILE AST for insertion
---@param entries table Content entries to process (list of strings or tables)
---@param shiftHeadings number Shift headings by this amount
---@param metaopts table Metadata options
local function doLevel(content, entries, shiftHeadings, metaopts)
  for _, inc in ipairs(entries) do
    local spec
    if type(inc) == "string" then
      spec = pl.tablex.union(metaopts, {
        src = inc,
        shift_headings = shiftHeadings })
      content[#content+1] = createCommand("include", spec)
    elseif inc.file then
      local fullopts = inc.options and pl.tablex.union(inc.options, metaopts) or metaopts
      spec = pl.tablex.union(fullopts, {
        src = inc.file,
        format = inc.format,
        shift_headings = shiftHeadings })
      content[#content+1] = createCommand("include", spec)
      if inc.content then
        doLevel(content, inc.content, shiftHeadings + 1, metaopts)
      end
    elseif inc.caption then
      local command = Levels[shiftHeadings + 2] or SU.error("Invalid master document (too many nested levels)")
      content[#content+1] = createCommand(command, {}, inc.caption)
      if inc.content then
        doLevel(content, inc.content, shiftHeadings + 1, metaopts)
      end
    elseif inc.content then
      doLevel(content, inc.content, shiftHeadings + 1, metaopts)
    else
      SU.error("Invalid master document (invalid content section)")
    end
  end
end

-- INPUTTER

local base = require("inputters.base")

local inputter = pl.class(base)
inputter._name = "silm"
inputter.order = 2

function inputter.appropriate (round, filename, _)
  if round == 1 then
    return filename:match("silm$")
  end
  -- No other round supported...
  -- FIXME we could check syntax (YAML file with masterfile field, at least)
  return false
end

function inputter:parse (doc)
  local yaml = require("resilient-tinyyaml")
  local master = yaml.parse(doc)
  if type(master) ~= "table" then
    SU.error("Invalid master document (not a table)")
  end
  local ok, err = validate(master, masterSchema)
  if not ok then
    SU.error("Invalid master document (" .. err .. ")")
  end
  if master.parts and master.chapters then
    SU.error("Invalid master document (both parts and chapters)")
  end

  local baseShiftHeadings = self.options.shift_headings or 0

  -- Are we the root document, or some included subdocument?
  -- in the latter case, we only honor some of the fields.
  local isRoot = not SILE.documentState.documentClass

  local content = {}

  local sile = master.sile or {}
  local metadata = master.metadata or {}

  if isRoot then
    -- Document global settings
    if master.font then
      if type(master.font.family) == "table" then
        content[#content+1] = createCommand("use", {
          module = "packages.font-fallback"
        })
        content[#content+1] = createCommand("font", {
          family = master.font.family[1],
          size = master.font.size
        })
        for i = 2, #master.font.family do
          content[#content+1] = createCommand("font:add-fallback", {
            family = master.font.family[i],
          })
        end
      else
        content[#content+1] = createCommand("font", {
          family = master.font.family,
          size = master.font.size
        })
      end
    end
    -- FIXME QUESTION: I start too think that main language should
    -- be class option so that some decisions could be delegated to
    -- the class (e.g. style overrides in the case of resilient classes)
    -- Not sure how to behave with legacy classes though...
    if master.language then
      content[#content+1] = createCommand("language", {
        main = master.language
      })
    end
  end

  local packages = sile.packages or {}
  if packages then
    for _, pkg in ipairs(packages) do
      content[#content+1] = createCommand("use", {
        module = "packages." .. pkg
      })
    end
  end

  if isRoot then
    local settings = sile.settings or {}
    if settings then
      for k, v in pairs(settings) do
        content[#content+1] = createCommand("set", {
          parameter = k,
          value = v
        })
      end
    end
    if metadata.title then
      content[#content+1] = createCommand("odd-running-header", {}, metadata.title)
    end
  end

  -- Document content
  -- FIXME QUESTION: if not a root document, should we wrap the includes
  -- in a language group?
  local metaopts = handleDjotMetadata(metadata)
  if master.parts then
    doLevel(content, master.parts, baseShiftHeadings - 1, metaopts)
  elseif master.chapters then
    doLevel(content, master.chapters, baseShiftHeadings, metaopts)
  end

  if isRoot then
    -- PDF metadata
    -- NOTE: inserted at the very end of the document because (at least in SILE 0.14)
    -- it introduces hboxes than can affect indents, centering, page breaks and paragraphs...
    insertPdfMetadata(content, metadata)
  end

  -- Document wrap-up
  local options = master.sile.options or {}
  local classopts = isRoot and {
      class = options.class or "resilient.book", -- Sane default. We Are Resilient.
      papersize = options.papersize,
      layout = options.layout,
      resolution = options.resolution
    } or {}

  local tree = {
    createStructuredCommand("document", classopts, content),
  }
  return tree
end

return inputter
