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

That common parent style is where we would ideally define the font, for instance to use old-style numbering.
Robert Bringhurst says: "It is usual to set folios in the text size"---so we won't change the font size.

```yaml
folio-base:
  style:
    font:
      features: "+onum"
    numbering:
      display: "arabic"
```

The numbering format is defined in another set of numbering styles.
The usual settings is to have roman numbers in the front matter, and arabic numbers in the main and back matters.

```yaml
folio-frontmatter:
  style:
    numbering:
      display: "roman"
folio-mainmatter:
  style:
    numbering:
      display: "arabic"
folio-backmatter:
  style:
    numbering:
      display: "arabic"
```

In books without these high-level divisions, `folio-mainmatter` is implied for the whole document.
As all of these are numbering styles, you can also extend them further, would you want to style the page numbers differently in these divisions.
