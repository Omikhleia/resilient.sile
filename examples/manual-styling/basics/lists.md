## List label styles

The bullet symbol in unordered list items, and the counter in
ordered lists, rely on extended character styles.

### Styles for unordered items

This extended character style specification defines the default character
symbol to use as bullet, in a dedicated "itemize" structure:

```yaml
⟨list style name⟩:
  style:
    ⟨character style specification⟩
    itemize:
      symbol: "⟨character⟩"
```

The bullet can either consist in the actual character to use, or be provided
as a Unicode codepoint in hexadecimal (`U+xxxx`), as a mere convenience.

### Styles for ordered items

Styling the label in an enumeration can rely on two strategies.
A first option is to use a number style, with the same syntax as previously
described, but without the "kern" spacing elements.[^lists-kern]

```yaml
⟨list style name⟩:
  style:
    ⟨character style specification⟩
    numbering:
      display: "⟨format⟩"
      before:
        text: "⟨format⟩"
      after:
        text: "⟨text⟩"
```

[^lists-kern]: More precisely, if these are present, they will be ignored, as
the list environments take care of the positioning.

A second option is to use an extended character style specification.

```yaml
⟨list style name⟩:
  style:
    ⟨character style specification⟩
    enumerate:
      symbol: "⟨character⟩"
```

The symbol must be provided provided as a Unicode codepoint in hexadecimal, supposed to
represent the glyph for "1”. It allows using a subsequent range of Unicode characters
as number labels, even though the font may not include any OpenType feature to enable
these automatically. For instance, one could specify U+2474 (“parenthesized digit one”),
U+2460 (“circled digit one”), U+2776 (“negative digit one”), U+24B6 (“circled latin capital A”),
and so on.

It obviously requires the font to have these characters, and due to the way how Unicode is
done, the enumeration to stay within a range corresponding to expected characters.
This strategy will therefore only work for some choices of characters, and with fairly short
lists.
