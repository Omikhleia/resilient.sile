-- Enforce all inputters to be loaded, so that the user can use them directly
pcall(function () local _ = SILE.inputters.silm end)
pcall(function () local _ = SILE.inputters.markdown end)
pcall(function () local _ = SILE.inputters.djot end)
pcall(function () local _ = SILE.inputters.pandocast end)
