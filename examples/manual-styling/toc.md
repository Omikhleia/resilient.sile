## Table of content styles

A table of contents style (or "ToC style" in brief) obeys the following specification
(with any of the elements being optional):

```yaml
⟨toc style name⟩:
  style:
    ⟨character style specification⟩
    ⟨paragraph style specification⟩
    toc:
      pageno: true|false
      dotfill: true|false
      number: true|false
```

Such a style applies to a given sectioning level in the table of contents.
Besides being a paragraph and a character style, it also includes a specific `toc` entry,
which allows:

 - Displaying the page number or not (default `true`).
 - Filling the line with dots or not (only meaningful if the previous option is
   enabled; default `true`).
 - Displaying the section number or not (default `false`).

Styling a table of contents goes much farther than just defining ToC styles
for level items. We will have a more in-depth look at the topic later.
