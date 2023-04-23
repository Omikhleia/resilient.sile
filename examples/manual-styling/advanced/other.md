## Other styling considerations

The previous sections describe several usual cases, but cannot be exhaustive.
In brief, all resilient-compatible packages may provide their own styles.
You should therefore read their documentation to learn about them, and look at a newly generated style file to check how they are defined by default.

Readers experienced with SILE’s standard packages also have to be aware that the latter sometimes define hooks, initially intended for users to possibly re-implement in order to override some internal formatting logic. Obviously, in the context of a resilient-compatible class, some of these are already overriden to rely on the styling paradigm presented here.

For instance, the (standard) **url** package provides a `urlstyle` hook command. While you could override it---that is, redefine that command---, please note that this is what the resilient classes already do, so as to delegate the decision to a style conveniently called `urlstyle` too.[^other-sile-hooks]

[^other-sile-hooks]: The same principle actually applies to page numbers, relying on the standard **folio** package. The latter provides a `foliostyle` hook, which the resilient styling system overrides with its own clever logic.

In other terms, even for standard SILE packages, we may already have provided a style-aware version of their original customization hooks.
