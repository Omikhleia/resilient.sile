# Concepts & workflow

## Using a style file

![The resilient styling workflow.](manual-styling/workflow.dot){width=9cm}

When processing your master document, you can provide a style file for it,
going by the same name, and the extension `.sty`.

If you don't have such a style file, no problem. Upon running SILE
for the first time on your document, you obtain, besides the usual PDF,
an output style file (as well as a bunch of other files, not represented
above, used for resolving tables of contents, cross-references, etc.)

All resilient classes and compliant packages provide default style
definitions. When an input style file is available, it is only
overwritten for missing styles.[^basics-overwrite-styles]
Typically, if you add another package dependency to your document,
you will get a bunch of additional style definitions. As a result,
the output style file is complete with the new defitions, keeping
other changes you might have applied to it.[^basics-unused-styles]

In order to customize the styling of a document, you can therefore
edit that style file, change the styles you want to alter,
and process the document again.

Would you wish to reset some unfortunate changes,
but you do not remember what the original settings were,
then remove those styles, and process the document again.
The default style definitions will be back in the output file.

Preciously save your style file with your document; copy and
rename it at convenience for use with other documents.

[^basics-overwrite-styles]: Well, it's not fully true. The
output style files has all styles sorted alphabetically,
and comments may be added to it. What we mean here is that
the existing definitions are kept.

[^basics-unused-styles]: An implication here is that the style
file may contain unused styles. We might address in a future
version the possibility to identify and mark those styles.

## Style definitions

The style file contains all style definitions. It is written
in a small subset of [YAML](https://en.wikipedia.org/wiki/YAML),
a lightweight human-readable data-representation language.

::: {custom-style=admon}
**Warning.** The current draft implementation does not use YAML.
It just dumps a raw Lua table---This not very user-friendly.
:::

FIXME: TODO. Styling rationale. Style inheritance.
