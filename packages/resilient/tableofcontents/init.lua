--
-- Re-implementation of the tableofcontents package.
-- Hooks are removed and replaced by styles, allowing for a fully customizable TOC
-- 2021-2023, Didier Willis
-- License: MIT
--
local base = require("packages.resilient.base")
local utils = require("resilient.utils")

local package = pl.class(base)
package._name = "resilient.tableofcontents"

local tocStyles = {
  -- level0 ~ part
  { font = { weight = 800, size = "1.15em" },
    toc = { numbered = true, pageno = false },
    paragraph = { before = { skip = "medskip", indent = false, },
                  after = { skip = "medskip", vbreak = false } } },
  -- level1 ~ chapter
  { font = { weight = 800, size = "1.1em" },
    toc = { dotfill = false},
    paragraph = { before = { indent = false },
                  after = { skip = "smallskip" } } },
  -- level2 ~ section
  { font = { size = "1em" },
    toc = {},
    paragraph = { before = { indent = false },
                  after = { skip = "smallskip" } } },
  -- level3 ~ subsection
  { toc = { dotfill = false },
    paragraph = { before = { indent = true },
                  after = { skip = "smallskip" } } },
  -- level4 ~ subsubsection
  { toc = { pageno = false },
    paragraph = { before = { indent = true },
                  after = { skip = "smallskip" } } },
  -- level5 ~ figure
  { toc = { numbered = true },
    paragraph = { before = { indent = false },
                  after = { skip = "smallskip" } } },
  -- level6 ~ table
  { toc = { numbered = true },
    paragraph = { before = { indent = false },
                  after = { skip = "smallskip" } } },
  -- extra loosely defined levels, so we have them at hand if need be
  { toc = { pageno = false },
    paragraph = { before = { indent = true } } },
  { toc = { pageno = false },
    paragraph = { before = { indent = true } } },
  { toc = { pageno = false },
    paragraph = { before = { indent = true } } },
}

local tocNumberStyles = {
  -- level0 ~ part
  {},
  -- level1 ~ chapter
  {},
  -- level2 ~ section
  {},
  -- level3 ~ subsection
  {},
  -- level4 ~ subsubsection
  {},
  -- level5 ~ figure
  { font = { features= "+smcp" },
    numbering = { before = { text = "Fig. " }, after = { text = ".", kern = "2spc" }} },
  -- level6 ~ table
  { font = { features= "+smcp" },
    numbering = { before = { text = "Table " }, after = { text = ".", kern = "2spc" }} },
  -- extra loosely defined levels, so we have them at hand if need be
  {},
  {},
  {},
}
function package:_init (options)
  base._init(self, options)
  SILE.scratch.tableofcontents = SILE.scratch.tableofcontents or {}
  SILE.scratch._tableofcontents = SILE.scratch._tableofcontents or {}
  self.class:loadPackage("infonode")
  self.class:loadPackage("leaders")
  if not SILE.scratch.tableofcontents then
    SILE.scratch.tableofcontents = {}
  end
  self.class:registerHook("endpage", self.moveTocNodes)
  self.class:registerHook("finish", self.writeToc)
end

function package:moveTocNodes ()
  local node = SILE.scratch.info.thispage.toc
  if node then
    for i = 1, #node do
      node[i].pageno = self.packages.counters:formatCounter(SILE.scratch.counters.folio)
      table.insert(SILE.scratch.tableofcontents, node[i])
    end
  end
end

function package.writeToc (_)
  local tocdata = pl.pretty.write(SILE.scratch.tableofcontents)
  local tocfile, err = io.open(SILE.masterFilename .. '.toc', "w")
  if not tocfile then return SU.error(err) end
  tocfile:write("return " .. tocdata)
  tocfile:close()

  if not pl.tablex.deepcompare(SILE.scratch.tableofcontents, SILE.scratch._tableofcontents) then
    io.stderr:write("\n! Warning: table of contents has changed, please rerun SILE to update it.")
  end
end

function package.readToc (_)
  if SILE.scratch._tableofcontents and #SILE.scratch._tableofcontents > 0 then
    -- already loaded
    return SILE.scratch._tableofcontents
  end
  local tocfile, _ = io.open(SILE.masterFilename .. '.toc')
  if not tocfile then
    return false -- No TOC yet
  end
  local doc = tocfile:read("*all")
  local toc = assert(load(doc))()
  SILE.scratch._tableofcontents = toc
  return SILE.scratch._tableofcontents
end

function package:registerCommands ()

  -- Warning for users of the legacy tableofcontents
  self:registerCommand("tableofcontents:title", function (_, _)
    SU.error("The resilient.tableofcontents package does not use the tableofcontents:title command.")
  end)

  -- Skip the fluent mess for now...
  self:registerCommand("tableofcontents:notocmessage", function (_, _)
    SILE.typesetter:typeset("Rerun SILE to process table of contents!")
  end)

  self:registerCommand("tableofcontents", function (options, _)
    local depth = SU.cast("integer", options.depth or 3)
    local start = SU.cast("integer", options.start or 0)
    local linking = SU.boolean(options.linking, true)

    local toc = self:readToc()
    if toc == false then
      SILE.call("tableofcontents:notocmessage")
      return
    end

    -- Temporarilly kill footnotes and labels (fragile)
    local oldFt = SILE.Commands["footnote"]
    SILE.Commands["footnote"] = function () end
    local oldLbl = SILE.Commands["label"]
    SILE.Commands["label"] = function () end

    local tocItems = {}
    for i = 1, #toc do
      local item = toc[i]
      if item.level >= start and item.level <= start + depth then
        tocItems[#tocItems + 1] = utils.createCommand("tableofcontents:item", {
          level = item.level,
          pageno = item.pageno,
          number = item.number,
          link = linking and item.link
        }, utils.subTreeContent(item.label))
      end
    end
    SILE.call("style:apply:paragraph", { name = "toc" }, tocItems)

    SILE.Commands["footnote"] = oldFt
    SILE.Commands["label"] = oldLbl
  end, "Output the table of contents.")

  -- Flatten a node list into just its string representation.
  -- (Similar to SU.contentToString(), but allows passing typeset
  -- objects to functions that need plain strings).
  local function nodesToText (nodes)
    local spc = SILE.measurement("0.8spc"):tonumber() -- approx. see below.
    local string = ""
    for i = 1, #nodes do
      local node = nodes[i]
      if node.is_nnode or node.is_unshaped then
        string = string .. node:toText()
      elseif node.is_glue or node.is_kern then
        -- What we want to avoid is "small" glues or kerns to be expanded as
        -- full spaces. Comparing to a "decent" ratio of a space is fragile and
        -- empirical: the content could contain font changes, so the comparison
        -- is wrong in the general case. It's still better than nothing.
        -- (That's what the debug text outputter does to, by the way).
        if node.width:tonumber() > spc then
          string = string .. " "
        end
      elseif not (node.is_zerohbox or node.is_migrating) then
        -- Here, typically, the main case is an hbox.
        -- Even if extracting its content could be possible in regular cases
        -- (e.g. \raise), we cannot take a general decision, as it is a versatile
        -- object (e.g. \rebox) and its outputYourself could moreover have been
        -- redefine to do fancy things. Better warn and skip.
        SU.warn("Some content could not be converted to text: " .. node)
      end
    end
    -- Trim leading and trailing spaces, and simplify internal spaces.
    return string:match("^%s*(.-)%s*$"):gsub("%s+", " ")
  end

  local dc = 1
  self:registerCommand("tocentry", function (options, content)
    local dest
    if SILE.Commands["pdf:destination"] then
      dest = "dest" .. dc
      SILE.call("pdf:destination", { name = dest })
      if SU.boolean(options.bookmark, true) then
        SILE.typesetter:pushState()
        -- Temporarilly kill footnotes and labels (fragile)
        local oldFt = SILE.Commands["footnote"]
        SILE.Commands["footnote"] = function () end
        local oldLbl = SILE.Commands["label"]
        SILE.Commands["label"] = function () end

        SILE.process(content)

        SILE.Commands["footnote"] = oldFt
        SILE.Commands["label"] = oldLbl

        local title = nodesToText(SILE.typesetter.state.nodes)
        SILE.typesetter:popState()

        SILE.call("pdf:bookmark", {
          title = title,
          dest = dest,
          level = options.level
        })
      end
      dc = dc + 1
    end
    SILE.call("info", {
      category = "toc",
      value = {
        label = utils.subTreeContent(SU.stripContentPos(content)),
        level = (options.level or 1),
        number = options.number,
        link = dest
      }
    })
  end, "Register an entry in the current TOC - low-level command.")

  local linkWrapper = function (dest, content)
    if dest and SILE.Commands["pdf:link"] then
      return {
        utils.createStructuredCommand("pdf:link", { dest = dest }, content)
      }
    end
    return content
  end

  self:registerCommand("tableofcontents:item", function (options, content)
    local level = SU.cast("integer", SU.required(options, "level", "tableofcontents:levelitem"))
    if level < 0 or level > #tocStyles - 1 then
      SU.error("Invalid TOC level " .. level)
    end

    local hasFiller = true
    local hasPageno = true
    local tocSty = self:resolveStyle("toc-level" .. level)
    if tocSty.toc then
      hasPageno = SU.boolean(tocSty.toc.pageno, true)
      hasFiller = hasPageno and SU.boolean(tocSty.toc.dotfill, true)
    end

    SILE.settings:temporarily(function ()
      SILE.settings:set("typesetter.parfillskip", SILE.nodefactory.glue())
      local itemContent = {}
      if options.number then
        itemContent[#itemContent + 1] = utils.createCommand("tableofcontents:levelnumber", {
          level = level,
          text = options.number
        })
      end
      itemContent[#itemContent + 1] = utils.subTreeContent(content)
      itemContent[#itemContent + 1] = utils.createCommand(hasFiller and "dotfill" or "hfill")
      if hasPageno then
        itemContent[#itemContent + 1] = utils.createCommand("style:apply", {
          name = "toc-pageno"
        }, {options.pageno})
      end
      SILE.call("style:apply:paragraph", {
        name = "toc-level" .. level
      }, linkWrapper(options.link, itemContent))
    end)
  end, "Typeset a TOC entry - internal.")

  self:registerCommand("tableofcontents:levelnumber", function (options, _)
    local text = SU.required(options, "text", "tableofcontents:levelnumber")
    local level = SU.cast("integer", SU.required(options, "level", "tableofcontents:levelnumber"))
    if level < 0 or level > #tocStyles - 1 then
      SU.error("Invalid TOC level " .. level)
    end

    local tocSty = self:resolveStyle("toc-level" .. level)
    if tocSty.toc and SU.boolean(tocSty.toc.numbered, false) then
      SILE.call("style:apply:number", {
        name = "toc-number-level" .. level,
        text = text
      })
    end
  end, "Typeset the (section) number in a TOC entry - internal.")
end

function package:registerStyles ()
  -- The interpretation after the ~ below are just indicative, one could
  -- customize everything differently. It corresponds to their use in
  -- the resilient.book class, and their default (proposed) styling specifications
  -- are based on the latter.
  self:registerStyle("toc", {}, {})
  self:registerStyle("toc-level-base", {}, {})
  self:registerStyle("toc-number-base", {}, {
    numbering = {
      after = {
        text = ".",
        kern = "2thsp"
      }
    }
  })

  for i = 1, #tocStyles do
    self:registerStyle("toc-level"..(i-1), { inherit = "toc-level-base" }, tocStyles[i])
  end
  for i = 1, #tocNumberStyles do
    self:registerStyle("toc-number-level"..(i-1), { inherit = "toc-number-base" }, tocNumberStyles[i])
  end

  self:registerStyle("toc-pageno", {}, {})
end

package.documentation = [[\begin{document}
The \autodoc:package{resilient.tableofcontents} package is a re-implementation of the
default \autodoc:package{tableofcontents} package from SILE. As its original ancestor,
it provides tools for classes to create tables of contents.

Documents with a table of contents need to be processed at least
twice —once to collect the entries and work out which pages they are on,
then to write the table of contents.

At a low-level, when you are implementing sectioning commands such
as \autodoc:command[check=false]{\chapter} or \autodoc:command[check=false]{\section}, your
class should call the \autodoc:command{\tocentry[level=<integer>, number=<string>]{<section title>}}
command to register a table of contents entry. Or you can alleviate your work by using a package
that does it all for you, such as \autodoc:package{resilient.sectioning}.

From a document author perspective, this package just provides the above-mentioned
\autodoc:command{\tableofcontents} command.

It accepts a \autodoc:parameter{depth} option to control the depth of the content added to the table
(defaults to 3) and a \autodoc:parameter{start} option to control at which level the table
starts (defaults to 0)

If the \autodoc:package{pdf} package is loaded before using sectioning commands,
then a PDF document outline will be generated.
Moreover, entries in the table of contents will be active links to the
relevant sections. To disable the latter behavior, pass \autodoc:parameter{linking=false} to
the \autodoc:command{\tableofcontents} command.

As opposed to the original implementation, this package clears the table header
and cancels the language-dependent title that the default implementation provides.
This author thinks that such a package should only do one thing well: typesetting the table
of contents, period. Any title (if one is even desired) should be left to the sole decision
of the user, e.g. explicitely defined with a \autodoc:command[check=false]{\chapter[numbering=false]{…}}
command or any other appropriate sectioning command, and with whatever additional content
one may want in between. Even if LaTeX has a default title for the table of contents,
there is no strong reason to do the same. It cannot be general: One could
want “Table of Contents”, “Contents”, “Summary”, “Topics”, etc. depending of the type of
book. It feels wrong and cumbersome to always get a default title and have to override
it, while it is so simple to just add a consistently-styled section above the table…

Moreover, this package does not support all the “hooks” that its ancestor had.
Rather, the entry level formatting logic entirely relies on styles.

The styles are \code{toc-level0} to \code{toc-level9}. They provides several
specific options that the original package did not have, allowing you to customize
nearly all aspects of your tables of contents.
Number styles are \code{toc-number-level0} to \code{toc-number-level9} control
how section numbers, when shown, are formatted.
In addition, the page number is style with \code{toc-pageno}.

\end{document}]]

return package
