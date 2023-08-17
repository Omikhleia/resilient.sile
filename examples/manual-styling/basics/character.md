## Character styles

### Regular styles

A regular character style obeys to the following specification
(with any of the internal elements being optional):

```yaml
⟨style name⟩:
  style:
    font: ⟨font specification⟩
    color: "⟨color specification⟩"
    properties:
      position: "normal|super|sub"
      case: "normal|upper|lower|title"
```

The ⟨font specification⟩ is an object which can contain any of the usual elements, as
used in the SILE `\font` command.

The ⟨color specification⟩ follows the same syntax as defined in the SILE **color** package.

The "properties" might be extended in a future revision; for now they support a position element, to specify a superscript or subscript formatting, and a text case element.
The "normal" values may be used to override a parent style definition, when style inheritance is used.

As an example, the following style results in a blue italic superscript in the Libertinus
Serif font.

```yaml
my-custom-style-name:
  style:
    font:
      family: "Libertinus Serif"
      style: "italic"
    color: "blue"
    properties:
      position: "super"
```

### Number styles

Some styles are applied to number values (e.g. counters), in which case
an additional element may also be used.

```yaml
⟨style name⟩:
  style:
    numbering:
      display: "⟨format⟩"
      before:
        text: "⟨format⟩"
        kern: "⟨dimen⟩"
      after:
        text: "⟨text⟩"
        kern: "⟨dimen⟩"
```

The fields are all optional and define:

 - The display format of the number, as one of the values supported by SILE
   (such as `arabic`, `roman`, etc.---also inclusing ICU-compliant 4-letter
   numeric systems).
 - The text to prepend to the number.
 - The text to append to the number.
 - The kerning space added before the formatted number.
 - The kerning space added after the fomatted number.

The default display format, when not specified, is `arabic`.

The "kern" value is usually a positive non-breakable glue.
Some packages, however, accept negative "before kern" values for specific
use cases.
See, for instance, the section devoted to footnote markers.

#### Note on units {.unnumbered}

As a rule of thumb, the "kern" widths can include stretch and shrink
values (e.g. `10pt plus 2pt minus 1pt`). Be aware, however, that
some packages call for a fixed width in the context of what they
are doing, and may therefore cancel these variations.
The "kern" values are expressed as usual SILE length specifications,
with the following additions:

 - The `nspc` numeric space (a.k.a figure space) unit.
 - The `thsp` thin space unit, as 1/2 fixed inter-word space.[^character-thsp]
 - The `iwsp` inter-word space pseudo-unit.
   The inter-word space is stretchable and shrinkable, so dimensions expressed
   in this pseudo-unit cannot contain extra stretch and shrink values.

[^character-thsp]: The term "thin space" has varying interpretations
depending on typographers. Some make it dependent on the font size (as a
portion of it, e.g. ⅙ of an "em"); others make it relative to the
inter-word (justification) space. We follow here the latter, so as two
be able to have two inter-word spacing options (`2thsp` = `1iwsp` without
stretching or shrinking).

