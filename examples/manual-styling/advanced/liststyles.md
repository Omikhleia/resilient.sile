## Styling lists

The **resilient.lists** package, as noted in its documentation, uses
different sets of styles for the `itemize` and the `enumerate`
environments.

 - Style sets `lists-itemize⟨N⟩` and `lists-itemize-alternate⟨N⟩` are
   pre-defined, all of the styles inheriting from a common parent
   style `lists-itemize-base`.
 - Style sets `lists-enumerate⟨N⟩` and `lists-enumerate-alternate⟨N⟩` are
   pre-defined, all of the styles inheriting from a common parent
   style `lists-enumerate-base`.

When styling your lists, you have more than one option.

 - You may, of course, alter these styles at your convenience, whether
   the "main" set, the `alternate` set, or both.
 - You may add a whole new sets, would you need more than one variant
   in your document.

But there's even more than meets the eyes, here. The `itemize` and `enumerate`
environments are just named this way as a mere semantic convenience,
but since you have full control on each item style definition, nothing prevents
you from actually mixing ordered and unordered item styles in a given set.
This will result in a kind of "mixed list", where some levels are numbered
and others marked with bullets.[^styles-lists-mixed]

[^styles-lists-mixed]: Whether it is a sound thing to do this way
is another matter.

