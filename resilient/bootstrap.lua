--
-- Bootstrap code for the resilient classes and packages.
--
-- License: MIT
-- Copyright (C) 2025 Omikhleia / Didier Willis
--

-- Enforce all inputters to be loaded, so that the user can use them directly.
SU.debug("resilient.bootstrap", "Ensuring extra inputters are loaded")

pcall(function () local _ = SILE.inputters.silm end)
pcall(function () local _ = SILE.inputters.markdown end)
pcall(function () local _ = SILE.inputters.djot end)
pcall(function () local _ = SILE.inputters.pandocast end)

-- HACK: Hard-patch SILE core behavior.
SU.debug("resilient.bootstrap", "Patching SILE core behavior")
require("resilient.patches.lang")

-- FIXME TRANSITIONAL
-- Create the global SILE.resilient namespace, with some state and helper functions.
SILE.resilient = {
   state = {},
}

--- Temporarilly cancels "fragile" commands (normally, such as like footnotes and labels).
-- Such commands break when used in moving arguments (like table of contents entries, headers, etc.)
-- The need to cancel them derives from the fact that AST content is stored and reused in different contexts.
-- For instance, consider a title that contains a footnote.
-- The title AST is stored in the TOC, and reused when typesetting the TOC.
-- The footnote command would try to create a footnote at that point, which is not what one expects.
-- @tparam function func The function to execute without fragile commands
-- @tparam string context A context identifier corresponding to the suppression purpose
function SILE.resilient.cancelContextualCommands (context, func)
  local oldContext = SILE.resilient.state.contextFor -- Nesting occurs, e.g. from toc to header and back
  SU.debug("resilient", "Cancelling contextual commands in context", context, "from", oldContext or "<none>")
  SILE.resilient.state.contextFor = context
  func()
  SILE.resilient.state.contextFor = oldContext
end

---- Make a command "robust", i.e. ignore it in certain contexts.
-- This is useful for commands that are known to be "fragile", such as footnotes and labels.
--
-- TRANSITIONAL: This is for enforcing existing commands to be robust, when they were not
-- declared as such initially.
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

---- Make a command context-switching, i.e. some of its processing needs needs
-- to run in a context where fragile commands are ignored.
-- This is useful for commands that are not fragile per se, but that process
-- content that may contain fragile commands, such as label refs.
--
-- TRANSITIONAL: This is for enforcing existing commands to be context-switching,
-- when they dit not invoke the cancellation of fragile commands initially when processing
-- content.
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
