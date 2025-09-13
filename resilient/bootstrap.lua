--- Bootstrap code for re·sil·ient.
--
-- @license MIT
-- @copyright (c) 2025 Omikhkeia / Didier Willis
-- @module resilient.bootstrap

-- Enforce all inputters to be loaded, so that the user can use them directly.
SU.debug("resilient.bootstrap", "Ensuring extra inputters are loaded")

pcall(function () local _ = SILE.inputters.silm end)
pcall(function () local _ = SILE.inputters.markdown end)
pcall(function () local _ = SILE.inputters.djot end)
pcall(function () local _ = SILE.inputters.pandocast end)

-- HACK: Hard-patch SILE core behavior.
SU.debug("resilient.bootstrap", "Patching SILE core behavior")
require("resilient.patches.lang")
require("resilient.patches.overhang")

-- TRANSITIONAL
-- Create the global SILE.resilient namespace, with some state and helper functions.
SILE.resilient = {
   state = {},
}

--- Temporarilly cancels "fragile" commands.
--
-- Typically, these are commands such as footnotes and labels.
--
-- Such commands break when used in moving arguments (like table of contents entries, running headers, etc.)
-- The need to cancel them derives from the fact that AST content is stored and reused in different contexts.
--
-- For instance, consider a title that contains a footnote.
-- The title AST is stored in the TOC, and reused when typesetting the TOC.
-- The footnote command would try to create a footnote at that point, which is not what one expects.
--
-- @tparam string context A context identifier corresponding to the suppression purpose
-- @tparam function func The function to execute without fragile commands
function SILE.resilient.cancelContextualCommands (context, func)
  local oldContext = SILE.resilient.state.contextFor -- Nesting occurs, e.g. from toc to header and back
  SU.debug("resilient", "Cancelling contextual commands in context", context, "from", oldContext or "<none>")
  SILE.resilient.state.contextFor = context
  func()
  SILE.resilient.state.contextFor = oldContext
end

--- Make a command "robust" (cancelled in certain contexts).
--
-- The command will be ignored when in a context where fragile commands are to be cancelled.
--
-- TRANSITIONAL:
-- This utility allows **enforcing** an existing command to be robust globally,
-- when it was not written as such initially.
-- This is useful for commands that are known to be "fragile", such as footnotes and labels,
-- in their original non-context-switching implementation.
--
-- @tparam string command The command name to make robust
function SILE.resilient.enforceContextualCommand (command)
  local oldCmd = SILE.Commands[command]
  if not oldCmd then
    SU.error("Cannot make unknown command '" .. command .. "' contextual")
  end
  SILE.Commands[command] = function (options, content)
    local context = SILE.resilient.state.contextFor
    if not context then
      return oldCmd(options, content)
    else
      SU.debug("resilient", "Skipping contextual command", command, "in context", context)
    end
  end
end

--- Make a command context-switching.
--
-- This utility is useful fwhen a command needs to process content in a context
-- where fragile commands are ignored, but the command itself was not written
-- to switch context for its own processing.
--
-- The command is not fragile itself, _per se_, but it processes content that may
-- contain fragile commands, such as label references, and should have taken care
-- of cancelling them at appropriate times.
--
-- TRANSITIONAL:
-- This utility allows **enforcing** an existing command to be context-switching
-- globally, when it does not invoke the cancellation of fragile commands by itself
-- initially.
--
-- @tparam string context A context identifier corresponding to the suppression purpose
-- @tparam string command The command name to make context-switching
function SILE.resilient.enforceContextChangingCommand(context, command)
  local oldCmd = SILE.Commands[command]
  if not oldCmd then
    SU.error("Cannot make unknown command '" .. command .. "' context-switching")
  end
  SILE.Commands[command] = function (options, content)
    local ret
    SILE.resilient.cancelContextualCommands(context, function ()
      ret = oldCmd(options, content)
    end)
    return ret
  end
end

--- Activate the sile·nt typesetter and the page·ant pagebuilder.
--
-- These are "new" implementations of the typesetter and pagebuilder
-- for re·sil·ient.
--
-- They act as full replacements to SILE's base typesetter and pagebuilder,
-- when processing a resilient document.
--
-- TRANSITIONAL:
-- This is highly linked to the way SILE instantiates typesetters and pagebuilders,
-- which changed multiple times.
--
function SILE.resilient.enforceSilentTypesetterAndPagebuilder ()
  -- SILE typesetter instantiation changed multuple times in the 0.14.x and 0.15.x series.
  -- In 0.15.11 "default" classes were added as noop subclasses of the "base" ones,
  -- with an obscure interdiction to use and modify the base classes directly.
  -- Method hot-patching is discouraged, and making a new class inheriting from the base
  -- oene is the recommended way...
  --
  -- In resilient and its ecosystem,
  -- we had 3rd-party packages instantiating a typesetter and monkey-patching it.
  -- We also had 3rd-party packages inheriting from the "base" typesetter, adding
  -- their own overrides.
  -- And resilient itself (initially via sile·x) was forking the base typesetter.
  --
  -- All this is now a mess, and we need to fix it.
  --
  -- Simple and straightforward, let's stop the shenanigans and sort this out
  -- once and for all.
  --
  -- The sile·nt typesetter and the page·ant pagebuilder are full replacements,
  -- not inheriting from SILE's base or default classes.
  --
  -- We enforce them completely when this utility function is called.
  SILE.typesetters.base = require("typesetters.silent")
  SILE.typesetters.default = require("typesetters.silent")
  SILE.pagebuilders.base = require("pagebuilders.pageant")
  SILE.pagebuilders.default = require("pagebuilders.pageant")

  -- The SILE.pagebuilder instance is set in sile/core/init.lua very early during SILE
  -- initialization.
  -- Which is funny since it's only needed after we have a typesetter and a document class.
  -- It sounds like a wrong design decision, that should be addressed in SILE core at some point.
  -- Anyway, replace it...
  SILE.pagebuilder = SILE.pagebuilders.default()
  -- The SILE.typesetter instance is set in the base document class's _post_init() method,
  -- so after it the latter is fully instantiated.
  -- So we should be safe doing nothing about it here.
end
