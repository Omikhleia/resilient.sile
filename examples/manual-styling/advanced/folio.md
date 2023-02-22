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

folio-odd:
  inherit: "folio-base"
  style:
    paragraph:
      align: "right"
```

That common parent style is where we would ideally define the font, for instance
to use old-style numbering in a smaller font size than the main text block.
It is also where we can define the numbering format.

```yaml
folio-base:
  style:
    font:
      features: "+onum"
      size: "0.9em"
    numbering:
      display: "arabic"
```

FIXME: (Nov. 2022)
Frontmatter / mainmatter / backmatter sections are not implement yet.
So for now, the above only documents the "mainmatter" general styling.

FIXME: (Jan. 2023)
Be sure to also address the other non-book classes,
when those are pushed to the repository.
