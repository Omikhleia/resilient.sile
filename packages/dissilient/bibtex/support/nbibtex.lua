-- The following functions borrowed from Norman Ramsey's nbibtex,
-- with permission.
-- Thanks, Norman, for these functions!
-- NOTE: Modified in 2024 for CSL compatibility:
--  - nbsp instead of "~" for non-breaking space
--  - added CSL compatibility fields (given, non-dropping-particle, family, suffix)
-- NOTE: Modified in 2025 for UTF-8 compatibility using luautf8

-- The initial implementation was using "~", but we now sanitized the
-- input earlier at parsing to replace those from the input with
-- non-breaking spaces. So we can just use the non-breaking space
-- character now on.
local nbsp = luautf8.char(0x00A0)

local function find_outside_braces (str, pat, i)
   i = i or 1
   local j, k = luautf8.find(str, pat, i)
   if not j then
      return j, k
   end
   local jb, kb = luautf8.find(str, "%b{}", i)
   while jb and jb < j do -- scan past braces
      -- braces come first, so we search again after close brace
      local i2 = kb + 1
      j, k = luautf8.find(str, pat, i2)
      if not j then
         return j, k
      end
      jb, kb = luautf8.find(str, "%b{}", i2)
   end
   -- either pat precedes braces or there are no braces
   return luautf8.find(str, pat, j) -- 2nd call needed to get captures
end

local function split (str, pat, find) -- return list of substrings separated by pat
   find = find or luautf8.find -- could be find_outside_braces
   -- @Omikhelia: I added this check here to avoid breaking on error,
   -- but probably in could have been done earlier...
   if not str then
      return {}
   end

   local t = {}
   local insert = table.insert
   local len = luautf8.len(str)
   local i = 1
   while i <= len + 1 do
      local j, k = find(str, pat, i)
      if j then
         insert(t, luautf8.sub(str, i, j - 1))
         i = k + 1
      else
         insert(t, luautf8.sub(str, i))
         break
      end
   end
   return t
end

local function splitters (str, pat, find) -- return list of separators
   find = find or luautf8.find -- could be find_outside_braces
   local t = {}
   local insert = table.insert
   local j, k = find(str, pat, 1)
   while j do
      insert(t, luautf8.sub(str, j, k))
      j, k = find(str, pat, k + 1)
   end
   return t
end

local function namesplit (str)
   local t = split(str, "%s+[aA][nN][dD]%s+", find_outside_braces)
   for i = 2, #t do
      while luautf8.match(t[i], "^[aA][nN][dD]%s+") do
         t[i] = luautf8.gsub(t[i], "^[aA][nN][dD]%s+", "")
         table.insert(t, i, "")
         i = i + 1
      end
   end
   return t
end

local sep_and_not_tie = "%-"
local sep_chars = sep_and_not_tie .. "%~"
local white_sep = "[" .. sep_chars .. "%s]+"
local white_comma_sep = "[" .. sep_chars .. "%s%,]+"
local trailing_commas = "(,[" .. sep_chars .. "%s%,]*)$"
local sep_char = "[" .. sep_chars .. "]"
local leading_white_sep = "^" .. white_sep

local function isVon(str)
   local lower = find_outside_braces(str, "%l") -- first nonbrace lowercase
   local letter = find_outside_braces(str, "%a") -- first nonbrace letter
   local bs = find_outside_braces(str, "%{%\\(%a+)") -- \xxx
   if lower and lower <= letter and lower <= (bs or lower) then
      return true
   elseif letter and letter <= (bs or letter) then
      return false
   elseif bs then
      lower = luautf8.find(str, "%l") -- first nonbrace lowercase
      letter = luautf8.find(str, "%a") -- first nonbrace letter
      return lower and lower <= letter
   else
      return false
   end
end

-- <set fields of name based on [[first_start]] and friends>=
-- We set long and short forms together; [[ss]] is the
-- long form and [[s]] is the short form.
-- <definition of function [[set_name]]>=
local function set_name(tokens, trailers, start, lim, long, short, inter_token)
   if start >= lim then
      return {}
   end
   -- string concatenation is quadratic, but names are short
   -- An abbreviated token is the first letter of a token,
   -- except again we have to deal with the damned specials.
   -- <definition of [[abbrev]], for shortening a token>=
   local function abbrev(token)
      local first_alpha, _, alpha = luautf8.find(token, "(%a)")
      local first_brace = luautf8.find(token, "%{%\\")
      if first_alpha and first_alpha <= (first_brace or first_alpha) then
         return alpha
      elseif first_brace then
         local i = luautf8.find(token, "%b{}", first_brace)
         if i then
            return luautf8.sub(token, first_brace, i)
         else -- unbalanced braces
            return luautf8.sub(token, first_brace)
         end
      else
         return ""
      end
   end

   local longname = tokens[start]
   local shortname = abbrev(tokens[start])

   for i = start + 1, lim - 1 do
      if inter_token then
         longname = longname .. inter_token .. tokens[i]
         shortname = shortname .. inter_token .. abbrev(tokens[i])
      else
         local ssep = trailers[i - 1]
         local nnext = tokens[i]
         local sep = ssep
         local next = abbrev(nnext)
         -- Here is the default for a character between tokens:
         -- a tie is the default space character between the last
         -- two tokens of the name part, and between the first two
         -- tokens if the first token is short enough; otherwise,
         -- a space is the default.
         -- <possibly adjust [[sep]] and [[ssep]] according to token position and size>=
         if not luautf8.match(sep, sep_char) then
            if i == lim - 1 then
               sep, ssep = nbsp, nbsp
            elseif i == start + 1 then
               sep = luautf8.len(shortname) < 3 and nbsp or " "
               ssep = luautf8.len(longname) < 3 and nbsp or " "
            else
               sep, ssep = " ", " "
            end
         end
         longname = longname .. ssep .. nnext
         shortname = shortname .. "." .. sep .. next
      end
   end

   return { [long] = longname, [short] = shortname }
end

local function parse_name(str, inter_token)
   if luautf8.match(str, trailing_commas) then
      SU.error("Name '%s' has one or more commas at the end", str)
   end
   str = luautf8.gsub(str, trailing_commas, "")
   str = luautf8.gsub(str, leading_white_sep, "")

   local tokens = split(str, white_comma_sep, find_outside_braces)
   local trailers = splitters(str, white_comma_sep, find_outside_braces)

   for i = 1, #trailers do
      if luautf8.match(trailers[i], ",") then
         trailers[i] = ","
      else
         trailers[i] = luautf8.sub(trailers[i], 1, 1)
      end
   end

   local commas = {}
   for i, t in ipairs(trailers) do
      if luautf8.match(t, ",") then
         table.insert(commas, i + 1)
      end
   end

   -- A name has up to four parts: the most general form is
   -- either ``First von Last, Junior'' or ``von Last,
   -- First, Junior'', but various vons and Juniors can be
   -- omitted. The name-parsing algorithm is baroque and is
   -- transliterated from the original BibTeX source, but
   -- the principle is clear: assign the full version of
   -- each part to the four fields [[ff]], [[vv]], [[ll]],
   -- and [[jj]]; and assign an abbreviated version of each
   -- part to the fields [[f]], [[v]], [[l]], and [[j]].
   -- <parse the name tokens and set fields of [[name]]>=

   local n = #tokens

   -- variables mark subsequences; if start == lim, sequence is empty
   local first_start, first_lim, last_lim, von_start, von_lim, jr_lim

   -- The von name, if any, goes from the first von token to
   -- the last von token, except the last name is entitled
   -- to at least one token. So to find the limit of the von
   -- name, we start just before the last token and wind
   -- down until we find a von token or we hit the von start
   -- (in which latter case there is no von name).
   -- <local parsing functions>=
   local function divide_von_from_last()
      von_lim = last_lim - 1
      while von_lim > von_start and not isVon(tokens[von_lim - 1]) do
         von_lim = von_lim - 1
      end
   end

   local commacount = #commas
   if commacount == 0 then -- first von last jr
      von_start, first_start, last_lim, jr_lim = 1, 1, n + 1, n + 1
      -- OK, here's one form.
      --
      -- <parse first von last jr>=
      local got_von = false
      while von_start < last_lim - 1 do
         if isVon(tokens[von_start]) then
            divide_von_from_last()
            got_von = true
            break
         else
            von_start = von_start + 1
         end
      end
      if not got_von then -- there is no von name
         while von_start > 1 and luautf8.match(trailers[von_start - 1], sep_and_not_tie) do
            von_start = von_start - 1
         end
         von_lim = von_start
      end
      first_lim = von_start
   elseif commacount == 1 then -- von last jr, first
      von_start, last_lim, jr_lim, first_start, first_lim = 1, commas[1], commas[1], commas[1], n + 1
      divide_von_from_last()
   elseif commacount == 2 then -- von last, jr, first
      von_start, last_lim, jr_lim, first_start, first_lim = 1, commas[1], commas[2], commas[2], n + 1
      divide_von_from_last()
   else
      SU.error("Too many commas in name '%s'", str)
   end

   local name = {}
   -- A name has up to four parts: the most general form is
   -- either ``First von Last, Junior'' or ``von Last,
   -- First, Junior'', but various vons and Juniors can be
   -- omitted. The name-parsing algorithm is baroque and is
   -- transliterated from the original BibTeX source, but
   -- the principle is clear: assign the full version of
   -- each part to the four fields [[ff]], [[vv]], [[ll]],
   -- and [[jj]]; and assign an abbreviated version of each
   -- part to the fields [[f]], [[v]], [[l]], and [[j]].
   -- <parse the name tokens and set fields of [[name]]>=

   local function merge(part)
      for k, v in pairs(part) do
         name[k] = v
      end
   end

   merge(set_name(tokens, trailers, first_start, first_lim, "given", "given-short", inter_token))
   merge(set_name(tokens, trailers, von_start, von_lim, "dropping-particle", "dropping-particle-short", inter_token))
   merge(set_name(tokens, trailers, von_lim, last_lim, "family", "family-short", inter_token))
   merge(set_name(tokens, trailers, last_lim, jr_lim, "suffix", "suffix-short", inter_token))

   return name
end

return {
   namesplit = namesplit,
   parse_name = parse_name,
}
