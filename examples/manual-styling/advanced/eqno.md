## Styling equation numbers

Mathematical equations that are displayed on their own line (in the so-called "display" mode) can be numbered.
This feature is not available in Markdown, but is supported for input documents in Djot or SIL.
In Djot, for instance, you can write, using the default `equation` counter:

```
$$`e^{i\pi} = -1`{numbered=true}
```

The equation numbers are then rendered using the `eqno` numbering style, which is defined as follows by default:

```yaml
eqno:
  numbering:
    display: "arabic"
    before:
      text: "("
    after:
      text: ")"
```

But as any style, this can be adjusted to your needs.
For the sake of this example, we could have used old-style numbers, and put the equation numbers in square brackets:

```yaml
eqno:
  font:
    features: "+onum"
  numbering:
    display: "arabic"
    before:
      text: "["
    after:
      text: "]"
```

Moreover, in Djot or SIL, you can also specify a custom counter to be used for numbering an equation, starting from 1 on its first occurrence, and automatically incremented.

```
$$`e^{i\pi} = -1`{counter=myname}
```

By default, the `eqno` style applies, but if your style definion file contains a style appropriately named `eqno-myname`, it will be used instead.
This is something you will likely want to do, for these custom counters to have a distinct appearance.
Style inheritance is useful here, as you can define a general style for equation numbers, and then override a subset of its properties for specific counters.
For instance, we could want to switch to alpha numbering for this sample `myname` counter:

```yaml
eqno-myname:
  inherit: eqno
  numbering:
    display: "alpha"
```
