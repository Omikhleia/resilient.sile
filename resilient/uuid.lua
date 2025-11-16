--- Naive UUID generation for re·sil·ient.
--
-- This module provide a few functions to generate UUIDs (Universally Unique Identifiers),
-- notably used when embedding XMP metadata (in PDF/A-3 compliant files).
--
-- For context, XMP requires a DocumentID and InstanceID, both being UUIDs:
--
--  - InstanceID should be different for each generated file (even for the same document).
--  - DocumentID should be "stable" for a given document.
--
-- In this contect, "stable" means that the UUID should be the same for a given "logical"
-- document.
-- In practice, using the whole document source, whatever this would means, to generate
-- the UUUID isn't practical:
--
--  - An actual document may be assembled from multiple files...
--  - Content may change in minor ways not affecting its logical identity...
--
-- So in practice, the UUID is often generated from a few key fields of a document.
--
-- @license MIT
-- @copyright (c) 2025 Omikhleia / Didier Willis
-- @module resilient.uuid

local sha1 = require("sha1")

-- Bitwise operations are different in various Lua versions...
--
--  - LuaJIT, Lua 5.1-5.2 could use the "bit" library,
--  - Lua 5.2 could use "bit32",
--  - Lua 5.3+ has native bitwise operators.
--
-- But we can have the 5.3+ operators and target older Lua versions...
--
-- These subtle differences being a pain, we avoid bitwise operations altogether.
-- So to keep it simple and compatible, we just use modulo arithmetic here...

-- Oh yes, and while we are at it, Lua 5.1 uses unpack instead of table.unpack...
local tunpack = table.unpack or unpack -- luacheck: ignore

--- Generate a fixed UUIDv5 from given arbitrary data.
--
-- The UUIDv5 is generated using SHA-1 hashing of the input data.
--
-- @tparam string data Input to hash
-- @treturn string UUIDv5
local function v5 (data)
  local hash = sha1.sha1(data) -- returns a hex string of 40 characters
  local bytes = {}
  for i = 1, 16 do
    bytes[i] = tonumber(hash:sub((i - 1) * 2 + 1, (i - 1) *2 + 2), 16)
  end
  -- Set version 5 (SHA-1 name-based)
  -- xxxxxxxx & 0x0F | 0x50 --> 0101xxxx
  -- (xxxxxxxxx % 16) --> xxxx, xxxx + 0x50 --> 0101xxxx
  bytes[7] = (bytes[7] % 16) + 0x50
  -- Set variant (RFC 4122)
  -- xxxxxxxx & 0x3F | 0x80 --> 10xxxxxx
  -- (xxxxxxxxx % 64) --> xxxxxx, xxxxxx + 0x80 --> 10xxxxxx
  bytes[9] = (bytes[9] % 64) + 0x80
  return string.format(
    "uuid:%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
    tunpack(bytes)
  )
end

--- Generate a random UUIDv4.
--
-- The UUIDv4 is generated using random bytes.
--
-- For that purpose, the Lua pseudo-random generator is seeded using
-- the current time.
--
-- @treturn string UUIDv4
local function v4 ()
  local bytes = {}
  math.randomseed(os.time())
  for i = 1, 16 do
    bytes[i] = math.random(0,255)
  end
  -- Set version 4
  -- xxxxxxxx & 0x0F | 0x40 --> 0100xxxx
  -- (xxxxxxxxx % 16) --> xxxx, xxxx + 0x40 --> 0100xxxx
  bytes[7] = (bytes[7] % 16) + 0x40
  -- variant (RFC 4122)
  -- xxxxxxxx & 0x3F | 0x80 --> 10xxxxxx
  -- (xxxxxxxxx % 64) --> xxxxxx, xxxxxx + 0x80 --> 10xxxxxx
  bytes[9] = (bytes[9] % 64) + 0x80
  return string.format(
    "uuid:%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
    tunpack(bytes)
  )
end

--- @export
return {
  v5 = v5,
  v4 = v4,
}
