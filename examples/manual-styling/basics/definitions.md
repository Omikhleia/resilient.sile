# Style definitions

The style file contains all style definitions used by the document class and
the loaded packages.
It is written in a subset of [YAML](https://en.wikipedia.org/wiki/YAML),
a lightweight human-readable data-representation language.
This chapter describes the style specification basics, for you
to be able to modify them.

## Base structure and inheritance model

A style is a named object.

```yaml
⟨style name⟩:
  inherit: "⟨other style name⟩"
  style:
    ⟨style specification details⟩
```

The `inherit` element is optional, and may refer to the name of another style.
When set, the declared style inherits the properties from another style.
This simple style inheritance mechanism is quite powerful, allowing
you to re-use existing styles and just override the elements you want.
This way, you can build a complex style hierarchy, with common properties
defined at an appropriate parent level, so as to be shared with all
descendant styles.

Then comes the `style` structure, whose details are provided in the
following sections.
