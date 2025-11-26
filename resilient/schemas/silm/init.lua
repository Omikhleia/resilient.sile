--- A master document schema for re·sil·ient.
--
-- The master document is a YAML file that describes the book structure.
--
-- @license MIT
-- @copyright (c) 2023-2025 Omikhleia / Didier Willis
-- @module resilient.schemas.silm

local CommonSchema = require("resilient.schemas.common")
local DateSchema, PrimitiveTypeSchema = CommonSchema.DateSchema, CommonSchema.PrimitiveTypeSchema

local OptionsSchema = {
  type = "object",
  additionalProperties = PrimitiveTypeSchema,
  properties = {}
}

local FileSchema = {
  type = "object",
  properties = {
    file = { type = "string" },
    format = { type = "string" },
    options = OptionsSchema
  }
  -- Making 'file' required breaks other schemas using FileSchema!
  -- TODO: revisit, we may have a mistake somewhere in nested schemas.
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
  },
  required = { "caption" },
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
    pubdate = DateSchema,
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

--- The SILE settings schema.
--
-- @field type "object"
-- @table SettingsSchema
local SettingsSchema = {
  type = "object",
  -- Allow any setting unknown to us
  additionalProperties = PrimitiveTypeSchema,
  properties = {
    -- Some well-known often-used settings can get proper validation
    ["textsubsuper.fake"] = { type = "boolean" },
    ["typesetter.italicCorrection"] = { type = "boolean" },
  }
}

--- The SILE configuration schema.
--
-- @field type "object"
-- @table SileConfigurationSchema
local SileConfigurationSchema = {
  type = "object",
  properties = {
    options = {
      type = "object",
      properties = {
        class = { type = "string", default = "resilient.book" },
        papersize = { type = "string", default = "a4" },
        layout = { type = "string" },
        resolution = { type = "number" },
        headers = { type = "string" },
        offset = { type = "string" },
      }
    },
    settings = SettingsSchema,
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

---- The top-level master document schema.
--
-- @field type "object"
-- @table MasterDocumentSchema
local MasterDocumentSchema = {
  ["$id"] = "urn:example:omikhleia:resilient:masterfile",
  type = "object",
  additionalProperties = true,
  properties = {
    masterfile = {
      type = "number",
    },
    metadata = MetaDataSchema,
    font = FontSchema,
    language = { type = "string", default = "en" },
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

return {
  MasterDocumentSchema = MasterDocumentSchema,
  SileConfigurationSchema = SileConfigurationSchema,
}
