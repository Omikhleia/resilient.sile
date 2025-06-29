# Example documents

All commands below are assumed to be run from the root of the repository, using the `resilient` command described in the [Setup](../guides/README.md) section.
(This command is just a convenience alias to simplify the command-line use of SILE with the _re·sil·ient_ collection.)

## A sample booklet

Both examples below demonstrate the use of the _re·sil·ient_ collection to create a booklet containing the same article in French.

The first example is a written in Djot, a lightweight markup language similar to Markdown.
It uses a "resilient master dcocument" to define the book structure, and implement the cover, halftitle, title, endpaper and back cover pages in a more high-level way.
A PDF version can be generated with the following command:

```bash
resilient examples/book/book.silm
```

The second example is written in SILE’s default language (SIL in “TeX-like” flavour).
The markup is therefore somewhat lower-level and verbose.
This said, it also demonstrates several features of the _re·sil·ient_ collection — the book class, a dedicated style file, and several packages.
It is intended for authors who prefer to work with SILE's default language, although this author believes that the first approach is much more practical and user-friendly.
A PDF version can be generated with the following command:

```bash
resilient examples/sil/lefevre-tuor-idril.sil
```

## More examples?

You can also check our repository of books and show-cases: [Awesome SILE books](https://github.com/Omikhleia/awesome-sile-books).
It contains several examples of complete books created with the _re·sil·ient_ collection, in French and English, and in a variety of use cases, with bibliographies, math formulas, and more.
