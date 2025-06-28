# Setting up _re·sil·ient_

Our User Guide provides an overview of the pre-requisites and steps to set up the _re·sil·ient_ collection.

However, it remains a bit vague on purpose, as you might not need all the features...

Here, we will nevertheless cover the complete “full-fledged” setup, for the most demanding users.

It is also what you will need if you want build the User Guide by yourself. It obviously requires a complete setup, to illustrate all the features of the collection.

## Installation

We will lead you through the steps to configure a `resilient` alias command alias, simplifying the use of the _re·sil·ient_ collection.

You have two options:

 - Either you install all the dependencies on your host system,
 - Or you use a Docker image that contains all the dependencies, if you prefer to be quickly bootstrapped without installing anything on your host system.

### Option 1: Install on your host system

You need to have the following tools installed and configured on your system.

You are on your own checking that you have the right versions of the dependencies and a proper working installation.

 - [**SILE**](https://github.com/sile-typesetter/sile) 0.15.**12** or 0.15.**13**.

   See installation instructions on the SILE website.

 - Several tools which might be already installed on your system, or which you can install using your regular package manager:

   - **lilypond** for music notation
   - **graphviz** for DOT graph rendering
   - **ghostscript** for PDF image conversion
   - **inkscape** for SVG image conversion
   - **graphicsmagick** for image conversion

 - [**LuaRocks**](https://luarocks.org/)

   See installation instructions on the LuaRocks website.

   Some LuaRocks packages and lower-level dependencies need a C compiler to be installed on your system.
   Depending on how SILE was built for your system, this might be an additional requirement.

 - The _re·sil·ient_ collection of classes & packages for SILE, a.k.a. [resilient.sile](https://github.com/Omikhleia/resilient.sile).

   ```bash
   luarocks install resilient.sile
   ```

   Be sure to upgrade to the latest version (_minimaly_ to **3.0.0**).

 - Several fonts: Libertinus, EB Garamond, Zallman Caps, Lato, Hack, Symbola.

   That’s quite a lot, but these are very good fonts, freely available, so you should not have any problem finding them.

Once you have checked that you have all the above tools installed, you can create an alias to simplify the use of the _re·sil·ient_ collection.

```bash
alias resilient='sile -e "require('"'"'resilient.bootstrap'"'"')"'
```

### Option 2: Using a ready-to-go Docker image

This option, of course, requires you to have Docker installed on your system.

Then, you can build and use Docker file to build an image containing SILE, Luarocks, the _re·sil·ient_ collection, other tools used by some of the modules, and a curated set of good fonts, etc.

We recommend checking our [Awesome SILE books](https://github.com/Omikhleia/awesome-sile-books) repository for instructions on how to build such an image.

Once the image is built, you can create an alias to simplify the use of the _re·sil·ient_ collection.

```bash
alias resilient='docker run -it --rm --volume "$(pwd):/data" --user "$(id -u):$(id -g)" silex -e "require('"'"'resilient.bootstrap'"'"')"'
```

Were `silex` is the name of the Docker image you built. Adjust the command if you used a different name for the image.

## Building the User Guide

All commands below are assumed to be run from the root of the repository.

First, build the "resume" sample, which is included as PDF in the User Guide.

```bash
resilient guides/resilient/resume-sample.sil
```

It should generate a 2-page PDF file named `guides/resilient/resume-sample.pdf`.

Next, build the User Guide itself.

```bash
resilient guides/resilient/sile-resilient-manual.silm
```

This will generate a PDF file named `guides/resilient/sile-resilient-manual.pdf` — and you are nearly done.

Run the above command up to three times in total, to ensure that the table of contents, indexes, and other cross-references are properly generated and re-paginated.

Now, you can open the User Guide PDF file in your favorite PDF viewer, or print it out if you prefer a paper version.
