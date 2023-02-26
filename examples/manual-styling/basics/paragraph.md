## Paragraph styles

For the sake of simplicity, what we call a paragraph style in this styling
specification is actually a “paragraph block”---It may contain
more than one actual paragraph in the usual sense of the word.

Such a paragraph style obeys to the following specification
(with any of the internal elements being optional):

```yaml
⟨paragraph style name⟩:
  style:
    ⟨character style specification⟩
    paragraph:
      align: "center|right|left|justify"
      before:
        skip: "⟨glue⟩"
        indent: true|false
        break: true|false
      after:
        skip: "⟨glue⟩"
        indent: true|false
        break: true|false
```

First of all, it is also a character style, so any formatting defined
there will be applied. The specification additionnaly provides:

 - The alignment of the paragraph block (center, left, right or justify---the
   latter is the default but may be useful to overwrite an inherited alignment).
 - Rules applying before the paragraph block:
    - The amount of vertical space before the content, as a variable length or a
      named skip (such as `bigskip`, `medskip`, `smallskip`).
    - Whether paragraph indentation is applied to the first paragraph (defaults
      to `true`). Book sectioning commands, typically, usually set it to `false`,
      for section titles not to be indented.
    - Whether a page break may occur before the block (defaults to
      `true`).
  - Rules applying after the paragraph block
    - The amount of vertical space after the content, as a variable length or a
      named skip (such as `bigskip`, `medskip`, `smallskip`).
    - Whether paragraph indentation is applied to the next paragraph after the
      block (defaults to `true`). Book sectioning commands, typically, may set
      it to `false`, as expected in English.[^styles-par-idents]
    - Whether a page break may occur after the block (defaults to `true\).
      Book sectioning commands, typically, would set it to `false`, for the
      section titles to stay with the contents following them.


[^styles-par-idents]: The usual convention for English books is to disable
the first paragraph indentation after a section title. The French convention,
however, is to always indent regular paragraphs, even after a section title.

::: {custom-style="admon"}
This version of the specification does not provide any way to configure
the margins (left and right text block indents), internal skips, and other
low-level paragraph formatting options (paragraph indent, etc.)[^styles-par-margins]
:::

[^styles-par-margins]: This might be considered in a future revision, but note
that it may also be addressed by defining extra alignment options.
The **resilien.book** class, for instance, defines its own `block` option
(used in block quotes).

Please note that changing an existing character style into a paragraph style
does not imply that the content is magically turned into paragraphs.
When classes or packages expect a character style at some point, only
that part of style definition is used. Classes and packages are responsible
for applying the paragraph part too, depending on context.

