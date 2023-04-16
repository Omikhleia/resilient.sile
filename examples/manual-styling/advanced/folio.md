## Styling page numbers

In two-side documents, such as the **resilient.book** class, dedicated paragraph styles
are used for odd and even pages.
The _default_ definitions just take care the alignment, and defer other
styling decisions to a common parent style.

```yaml
folio-even:
  inherit: "folio-base"
  style:
    paragraph:
      align: "left"
      before:
        indent: false

folio-odd:
  inherit: "folio-base"
  style:
    paragraph:
      align: "right"
      before:
        indent: false
```

That common parent style is where we would ideally define the font, for instance
to use old-style numbering. It is also where we can define the numbering format.
Robert Bringhurst says: "It is usual to set folios in the text size"---so we won't
change the font size.

```yaml
folio-base:
  style:
    font:
      features: "+onum"
    numbering:
      display: "arabic"
```

::: {custom-style="admon"}
Frontmatter / mainmatter / backmatter sections are not implement yet.
So for now, the above only documents the "mainmatter" general styling.
:::
