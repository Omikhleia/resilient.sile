# YAML Schemas

This folder contains YAML schemas for master documents and style definition files.

## Intended use

When (re)generated, style files start with a comment block:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/Omikhleia/resilient.sile/v2.8.0/schemas/stylefile.json
# $schema: https://raw.githubusercontent.com/Omikhleia/resilient.sile/v2.8.0/schemas/stylefile.json
```

It's a comment, so it has no effect, right? Well, it is actually a hint for external tools that can read and understand JSON schemas.

If your preferred text editor supports an appropriate YAML language server, it will be able to provide you with auto-completion and validation based on the schema. This is a small but useful feature that can help you write your style files more efficiently.

Likewise, you can also (manually) add a similar comment block to your master documents:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/Omikhleia/resilient.sile/v2.8.0/schemas/masterfile.json
# $schema: https://raw.githubusercontent.com/Omikhleia/resilient.sile/v2.8.0/schemas/masterfile.json
```

With editors that support it, you can then benefit from auto-completion and validation for your master documents as well.

This is known to work with **Visual Studio Code**, with the [YAML Language Support by Red Hat](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml) extension. Other editors and plugins may also support this feature.

This is a non-essential feature, but it can be a nice addition to your workflow if you are using such tools.
It might still be somewhat experimental, and the actual code is actually more permissive than the schema, but it should be a good starting point.

## License

These schemas are not considered as source code, but rather as documentation / interface definition files, for interoperability and ease of use.

As such, they are licensed under **CC0 Universal / Public Domain**.
