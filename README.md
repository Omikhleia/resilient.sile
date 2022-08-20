# resilient.sile

[![license](https://img.shields.io/github/license/Omikhleia/resilient.sile)](LICENSE)
[![Luarocks](https://img.shields.io/luarocks/v/Omikhleia/resilient.sile?label=Luarocks&logo=Lua)](https://luarocks.org/modules/Omikhleia/resilient.sile)

This collection of classes and packages for the [SILE](https://github.com/sile-typesetter/sile)
typesetting system provides advanced book classes and tools, 

This is the successor of my previous “[Omikhleia’s classes & packages for SILE](https://github.com/Omikhleia/omikhleia-sile-packages)”,
fully redesigned for SILE v0.14 or upper, and provided as a separate installable module.

Besides all the changes from SILE v0.12 to v0.14 and its new package and class APIs, this redesign entails
many more things, with breaking changes (consider it as v2.0 of the former solution).

It therefore comes under a new name (also used as a namespace here and there), **resilient**.
The name is a pun on "SILE" (as, after all, the initial target was always on redoing a book class that would satisfy my
requirements), but there will be a bit more to it than that, which might become more visible when the collection
expands.

WIP - EARLY VERSION - APIs are unstable, with many breaking changes

## Installation

NOT YET READY

These packages require SILE v0.14 or upper.

Installation relies on the **luarocks** package manager.

To install the latest development version, you may use the provided “rockspec”:

```
luarocks --lua-version 5.4 install --server=https://luarocks.org/dev resilient.sile
```

(Adapt to your version of Lua, if need be, and refer to the SILE manual for more
detailed 3rd-party package installation information.)
