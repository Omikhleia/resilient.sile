--- Some YAML master file inputter for SILE
--
-- @copyright License: MIT (c) 2023 Omikhleia
-- @module inputters.silm
--
-- FIXME: later refactor to use resilient.utils instead of copy-pasting
-- or consider moving resilient.utils to a separate common library
-- local utils = require("resilient.utils")
-- local Cc = utils.createCommand
local function Cc (command, options, content)
  local result = { content }
  result.col = 0
  result.lno = 0
  result.pos = 0
  result.options = options or {}
  result.command = command
  result.id = "command"
  return result
end

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
          -- tinyyaml converts dates to date-time objects
          -- We don't care about hours, minutes, etc.
          additionalProperties = true,
          properties = {
            year = { type = "number" },
            month = { type = "number" },
            day = { type = "number" }
          }
        },
        ISBN = { type = "string" },
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
    content = {
      type = "array",
      items = { type = "string" }
    },
  }
}

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

local base = require("inputters.base")

local inputter = pl.class(base)
inputter._name = "silm"
inputter.order = 2

function inputter.appropriate (round, filename, _)
  if round == 1 then
    return filename:match("silm$")
  end
  -- No other round supported...
  -- FIXME we could check syntax (YAML file with masterfile field)
  return false
end

function inputter.parse (_, doc)
  local yaml = require("resilient-tinyyaml")
  local master = yaml.parse(doc)

  local ok, err = validate(master, masterSchema)
  if not ok then
    SU.error("Invalid master document (" .. err .. ")")
  end

  local content = {}

  -- Document global settings
  if master.font then
    if type(master.font.family) == "table" then
      content[#content+1] = Cc("use", {
        module = "packages.font-fallback"
      })
      content[#content+1] = Cc("font", {
        family = master.font.family[1],
        size = master.font.size
      })
      for i = 2, #master.font.family do
        content[#content+1] = Cc("font:add-fallback", {
          family = master.font.family[i],
        })
      end
    else
      content[#content+1] = Cc("font", {
        family = master.font.family,
        size = master.font.size
      })
    end
  end
  if master.language then
    content[#content+1] = Cc("language", {
      main = master.language
    })
  end
  local sile = master.sile or {}
  local packages = sile.packages or {}
  if packages then
    for _, pkg in ipairs(packages) do
      content[#content+1] = Cc("use", {
        module = "packages." .. pkg
      })
    end
  end
  local settings = sile.settings or {}
  if settings then
    for k, v in pairs(settings) do
      content[#content+1] = Cc("set", {
        parameter = k,
        value = v
      })
    end
  end
  local metadata = master.metadata or {}
  if metadata.title then
    content[#content+1] = Cc("odd-running-header", {}, { metadata.title })
  end
  -- Document content
  for _, inc in ipairs(master.content) do
    content[#content+1] = Cc("include", { src = inc })
  end

  -- PDF metadata
  -- HACK: inserted at the very end of the document because (at least in SILE 0.14)
  -- it introduces hboxes than can affect indents, centering, page breaks and paragraphs...
  if metadata.title then
    content[#content+1] = Cc("pdf:metadata", {
      key = "Title",
      value = master.metadata.title
    })
  end
  if metadata.authors then
    content[#content+1] = Cc("pdf:metadata", {
      key = "Author",
      value = type(metadata.authors) == "table" and table.concat(metadata.authors, "; ") or metadata.authors
    })
  end
  if metadata.subject then
    content[#content+1] = Cc("pdf:metadata", {
      key = "Subject",
      value = metadata.subject
    })
  end
  if metadata.keywords then
    content[#content+1] = Cc("pdf:metadata", {
      key = "Keywords",
      value = type(metadata.keywords) == "table" and table.concat(metadata.keywords, "; ") or metadata.keywords
    })
  end
  -- Document wrap-up
  local options = master.sile.options or {}

  local tree = {
    Cc("document", {
      class = options.class or "resilient.book", -- Sane default. We Are Resilient.
      layout = options.layout,
      papersize = options.papersize,
      resolution = options.resolution
    }, {
      content
    }),
  }

  return tree
end

return inputter
