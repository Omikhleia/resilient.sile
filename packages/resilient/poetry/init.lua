--
-- A poetry package for SILE
-- 2021, Didier Willis
-- License: MIT
--
local base = require("packages.base")

local package = pl.class(base)
package._name = "resilient.poetry"

function package:_init (options)
  base._init(self, options)
  self.class:loadPackage("rebox")
  self.class:loadPackage("raiselower")
  self.class:loadPackage("inputfilter")
end

function package:registerCommands ()
  local function prosodyFilter(text, content, options)
    local result = {}
    local prosodyAnnotation
    local currentText = ""
    local process
    local processText, insertProsodyAnnotation, insertProsodyText

    local function insertProsody()
      local opts = {}
      if options.mode == "times" then
        if prosodyAnnotation == "x" then
          prosodyAnnotation = "×" -- U+00D7 times
        end
      elseif options.mode == "experimental" then
        if prosodyAnnotation == "x" then
          prosodyAnnotation = "×" -- U+00D7 times
        elseif prosodyAnnotation == "-" then
          prosodyAnnotation = "–" -- endash
        elseif prosodyAnnotation == "u" then
          prosodyAnnotation = "ᵕ" -- some half circle
          opts.lower = SILE.measurement("-0.33ex")
        end
      elseif options.mode == "classical" then
        if prosodyAnnotation == "x" then
          prosodyAnnotation = "×" -- U+00D7 times
        elseif prosodyAnnotation == "-" then
          opts.lower = SILE.measurement("-0.66ex")
          prosodyAnnotation = "¯" -- macron
        elseif prosodyAnnotation == "u" then
          opts.lower = SILE.measurement("-0.66ex")
          prosodyAnnotation = "˘" -- breve
        end
      elseif options.mode == "mixed" then
        if prosodyAnnotation == "x" then
          prosodyAnnotation = "×" -- U+00D7 times
        elseif prosodyAnnotation == "-" then
          prosodyAnnotation = "–" -- endash
        elseif prosodyAnnotation == "u" then
          opts.lower = SILE.measurement("-0.66ex")
          prosodyAnnotation = "˘" -- breve
        end
      end
      opts.name = prosodyAnnotation
      table.insert(result, self.class.packages.inputfilter:createCommand(
        content.pos, content.col, content.line,
        "resilient.poetry:prosody", opts, currentText
      ))
      prosodyAnnotation = nil
    end

    local function insertText()
      if #currentText > 0 then table.insert(result, currentText) end
      currentText = ""
    end

    local function ignore(separator)
      currentText = currentText .. separator
    end

    processText = {
      ["<"] = function (_)
        insertText()
        process = insertProsodyAnnotation
      end
    }

    insertProsodyAnnotation = {
      [">"] = function (_)
        prosodyAnnotation = currentText
        currentText = ""
        process = insertProsodyText
      end
    }

    insertProsodyText = {
      ["<"] = function (_)
        insertProsody()
        currentText = ""
        process = insertProsodyAnnotation
      end,
      ["\n"] = function (separator)
        insertProsody()
        currentText = separator
        process = processText
      end,
    }
    process = processText

    for token in SU.gtoke(text, "[<\n>]") do
      if(token.string) then
        currentText = currentText .. token.string
      else
        (process[token.separator] or ignore)(token.separator)
      end
    end

    if (prosodyAnnotation ~= nil) then
      insertProsody()
    else
      insertText()
    end
    return result
  end

  self:registerCommand("resilient.poetry:prosody", function (options, content)
    local prosodyBox
    local vadjust

    SILE.call("resilient.poetry:prosodyfont", {}, function ()
      vadjust = options.lower or SILE.measurement()
      prosodyBox = SILE.call("hbox", {}, function()
        SILE.typesetter:typeset(options.name)
      end)
    end)

    SILE.typesetter.state.nodes[#(SILE.typesetter.state.nodes)] = nil
    local origWidth = prosodyBox.width
    prosodyBox.width = SILE.length()
    prosodyBox.height = SILE.settings:get("resilient.poetry.lineheight")
    SILE.call("rebox", {height=0, width=0}, function()
      SILE.call("raise", { height = SILE.settings:get("resilient.poetry.offset"):absolute() + vadjust:tonumber()}, function ()
          SILE.typesetter:pushHbox(prosodyBox)
      end)
    end)
    local inVerseBox = SILE.call("hbox", {}, content)
    if inVerseBox.width < origWidth then
    inVerseBox.width = origWidth
    end
  end, "Insert a prosody annotation above the text (theoretically an internal command)")

  self:registerCommand("resilient.poetry:prosodyfont", function (_, content)
    -- Minimally we don't want italics to be applied from the verse line
    SILE.call("font", { style = "normal" }, content)
  end, "Override this command to change prosody style.")

  self:registerCommand("poetry", function (options, content)
    local step = SU.cast("integer", options.step or 5)
    local iVerse = SU.cast("integer", options.start or 1)
    local first = SU.boolean(options.first, false)
    local numbering = SU.boolean(options.numbering, true)

    local nVerse = 0
    for i = 1, #content do
      if type(content[i]) == "table" and content[i].command == "v" then
        nVerse = nVerse + 1
      end
    end

    local indent
    local regularIdent = SILE.length(SILE.settings:get("document.parindent")):absolute()
    if not numbering or nVerse < step then
      indent = SILE.length(SILE.settings:get("document.parindent")):absolute()
    else
      local digitSize
      SILE.settings:temporarily(function ()
        SILE.settings:set("font.size", SILE.settings:get("font.size")*0.9) -- scale
        SILE.settings:set("font.features", "+onum")
        digitSize = SILE.shaper:measureChar("0").width
      end)
      local setback = SILE.length("1.75em"):absolute()
      indent = SILE.length((math.floor(math.log10(nVerse + iVerse)) + 1) * digitSize):absolute()
        + setback
        + SILE.length(SILE.settings:get("document.parindent")):absolute()
    end

    SILE.settings:temporarily(function()
      SILE.settings:set("current.parindent", SILE.length(0))
      SILE.settings:set("document.parindent", SILE.length(0))
      SILE.settings:set("document.lskip", indent)
      SILE.settings:set("document.rskip", regularIdent)
      SILE.typesetter:leaveHmode()
      if SU.boolean(options.prosody, false) then
        SILE.settings:set("document.parskip", SILE.length("0.75bs"))
        SILE.typesetter:pushVglue(SILE.settings:get("document.parskip"))
        SILE.call("smallskip")
      else
        SILE.call("medskip")
      end
      for i = 1, #content do
        if type(content[i]) == "table" then
          if content[i].command == "v" then
            if numbering and (iVerse % step == 0 or (iVerse == 1 and first)) then
              content[i].options.n = iVerse
            end
            content[i].options.mode = options.mode
            content[i].command = "resilient.poetry:v"
            local labelRefs = self.class.packages.labelrefs
            if labelRefs then
              -- Cross-reference support
              labelRefs:pushLabelRef(iVerse)
              SILE.process({ content[i] })
              labelRefs:popLabelRef()
            else
              SILE.process({ content[i] })
            end
            iVerse = iVerse + 1
          elseif content[i].command == "stanza" then
            SILE.call("smallskip")
          else
            SU.error("Unexpected '"..content[i].command.."' in poetry")
          end
          -- FIXME TODO? IDEAS
          -- - Support poem title, perhaps outside this environement
          -- - Support theatrical stuff (name of speaker en smallcaps+centré, mais pas forcément,
          -- - aussi indications de mise en scène = didaskalia)
          -- - Act, scene
          -- - Canto
          -- - Speaker
          -- - inside a \verse, \placehoder{text} to leave a blank space of that size?
          -- - Verses that span on multiple lines (currently not effort)
        end
        -- All text nodes in ignored
      end
      if not SU.boolean(options.prosody, false) then
        SILE.call("medskip")
      end
    end)
  end, "A poetry environment")

  local typesetVerseNumber = function (mark)
    local setback = SILE.length("1.75em"):absolute()
    SILE.settings:temporarily(function ()
        SILE.settings:set("font.size", SILE.settings:get("font.size")*0.9) -- scale
        SILE.settings:set("font.features", "+onum")
        local w = SILE.length("6em"):absolute()

        local h = SILE.call("hbox", {}, { mark })
        table.remove(SILE.typesetter.state.nodes)

        SILE.typesetter:pushGlue({ width = -w })
        SILE.call("rebox", { width = w, height = 0 }, function()
          SILE.typesetter:pushGlue({ width = w - setback - h.width })
          SILE.typesetter:pushHbox(h)
        end)
    end)
  end

  self:registerCommand("resilient.poetry:v", function (options, content)
    local n = options.n and SU.cast("integer", options.n)
    SILE.typesetter:leaveHmode()
    if n then
      typesetVerseNumber(""..n)
    end
    SILE.process(self.class.packages.inputfilter:transformContent(content, prosodyFilter, { mode = options.mode }))
    SILE.typesetter:leaveHmode()
    SILE.typesetter:pushVglue(SILE.settings:get("document.parskip"))
  end, "A single verse (theoretically an internal command).")
end

function package.declareSettings (_)
  SILE.settings:declare({
    parameter = "resilient.poetry.offset",
    type = "length",
    default = SILE.length("2ex"),
    help = "Vertical offset between the prosody annotation and the text."
  })

  SILE.settings:declare({
    parameter = "resilient.poetry.lineheight",
    type = "length",
    default = SILE.length("4mm"),
    help = "Length (height) of the prodosy annotation line."
  })
end

package.documentation = [[\begin{document}
\use[module=packages.resilient.poetry]

If this package is called \autodoc:package{resilient.poetry}, it is not only because
it belongs to Omikhleia’s packages. There are so many ways to compose
poetry that one cannot, probably, cover them all. The art of
typography is hard, but perhaps the art of poetry typography is
even harder.

This package defines a \autodoc:environment{poetry} environment, which can
contain, for now\footnote{Other commands will raise an error
and any text node is silently ignored. This may change in a
future revision.}, only two types of
elements: verses, each with the \autodoc:command[check=false]{\v} command, and
a separator in the form of the \autodoc:command[check=false]{\stanza} command.
The latter just inserts a small vertical skip between verses.
The former, obviously, contains a single verse, though we will
see it comes with a few extras.

First of all, let us illustrate a poem by the French author
Victor Hugo, “\language[main=fr]{En hiver la terre pleure…}”,
using only the above-mentioned commands, without options.

\begin[main=fr]{language}
\begin{poetry}
\v{En hiver la terre pleure ;}
\v{Le soleil froid, pâle et doux,}
\v{Vient tard, et part de bonne heure,}
\v{Ennuyé du rendez-vous.}
\stanza
\v{Leurs idylles sont moroses.}
\v{— Soleil ! aimons ! — Essayons.}
\v{Ô terre, où donc sont tes roses ?}
\v{— Astre, où donc sont tes rayons ?}
\stanza
\v{Il prend un prétexte, grêle,}
\v{Vent, nuage noir ou blanc,}
\v{Et dit : — C’est la nuit, ma belle ! —}
\v{Et la fait en s’en allant ;}
\stanza
\v{Comme un amant qui retire}
\v{Chaque jour son cœur du nœud,}
\v{Et, ne sachant plus que dire,}
\v{S’en va le plus tôt qu’il peut.}
\end{poetry}
\end{language}

As can be seen, verses are automatically numbered, by default. This feature can be disabled
with the \autodoc:parameter{numbering} option set to false. The \autodoc:parameter{start} option
may also be provided, to define the number of the initial verse, would it be
different from one. Quoting \em{Beowulf}, chapter XI, starting at verse 710:
\script{
  -- Conditional in this documentation
  if SILE.Commands["label"] and SILE.Commands["ref"] then
    SILE.registerCommand("conditional:label", function(options, content)
      SILE.call("label", options, content)
    end)
    SILE.registerCommand("conditional:ref", function(options, content)
      SILE.call("ref", options, content)
    end)
  else
    SILE.registerCommand("conditional:label", function(options, content)
      -- ignore
    end)
    SILE.registerCommand("conditional:ref", function(options, content)
      SILE.typesetter:typeset("[reference not available]")
    end)
  end
}

\begin[start=710]{poetry}
\v{Ða com of more    \qquad      under misthleoþum}
\v{Grendel gongan,   \qquad      godes yrre bær;}
\v{mynte se manscaða \qquad      manna cynnes}
\v{sumne besyrwan    \qquad      in sele þam hean.}
\v{Wod under wolcnum \qquad      to þæs þe he winreced,}
\v{goldsele gumena,  \qquad      gearwost wisse,}
\v{fættum fahne.     \qquad      Ne wæs þæt forma sið}
\v{\conditional:label[marker=hrothgar]þæt he Hroþgares  \qquad      ham gesohte;}
\v{næfre he on aldordagum \qquad ær ne siþðan}
\v{heardran hæle,    \qquad      healðegnas fand.}
\end{poetry}

When numbering is left enabled, it goes by a \autodoc:parameter{step} of 5 by default.
You can set the option by that name to any other value that suits you.\footnote{Before
you ask, the large spaces \em{inside} verses in this example just use the standard \autodoc:command{\qquad}
command, so there is nothing special here.} The \autodoc:parameter{first} option may also be
set to true to enforce the first verse to always be numbered, even if it is not
a multiple of the step value. This might be useful if you are quoting just a few
verses and none would be numbered normally.

This is all what we have to say about typesetting simple poetry so far, mostly.
As an advanced feature, the \autodoc:environment{poetry} environment also supports a
\autodoc:parameter{prosody} option, which increases the height (i.e. baseline skip)
of verses so as to leave enough place for metrical or rhythmic annotations, which can
then be provided between angle brackets, that is \code{<…>}\footnote{As in the
standard \autodoc:package{chordmode} package. We actually used the exact same logic.}.
The annotation is placed above the (following) text.
In English, typically, a 2-level notation is often used, as shown
hereafter.\footnote{Arthur Golding, \em{Ovid’s Metamorphoses}, book II, lines 1–2,
scansion from Wikipedia.}

\begin[prosody=true]{poetry}
\v{Th<x>e p</>rince|l<x>y p</>al|<x>ace </>of | th<x>e s</>un || st<x>ood g</>or|g<x>eous t</>o | b<x>eh</>old}
\v{<x>On st</>atel<x>y p</>ill<x>ars b</>uild<x>ed h</>igh | <x>of y</>ell<x>ow b</>urn<x>ished g</>old}
\end{poetry}

The x here represents a \em{nonictus} in metrical scansion or an unstressed syllable in rhythmic scansion,
and the slash an \em{ictus} or a stressed syllable, respectively.
In 3-level notations, the scansion tries to be be both metrical and rhythmic, with
indicators such as a primary stress (/), a secondary stress
or \em{demoted} syllable (\\), and an unstressed syllable (x). These terms have varying
interpretations depending on the prosodist, but whatever they mean, we just want
to check how they would look.\footnote{Alexander Pope, \em{Sound and Sense},
verses 9–10, scansion example from Wikipedia.}

\begin[prosody=true, mode=times]{poetry}
\v{Wh<x>en </>Aj<x>ax str</>ives, s<\\>ome </>rock’s v<\\>ast w</>eight t<x>o thr</>ow,}
\v{Th<x>e l</>ine t<\\>oo l</>ab<x>ours, <x>and th<x>e w</>ords m<\\>ove sl</>ow;}
\end{poetry}

In a document in SILE language, remember to type two \\, as it is a special character.
Notice something else, here, too. Some prosodists are happy with the x, which is easy to
type, while others prefer an ×, i.e. a multiplication sign (as Unicode does not include
a better glyph for it). Obviously, it works if you directly enter that character
between the brackets, but this package also aims at simplifying your efforts:
the \autodoc:parameter{mode=times} option will automatically turn the x characters
into ×.

Let us check we can use other indicators without issue. In English, rhythmic patterns “arise
from the regular repetition of sequences of stressed patterns syllables (S, strong) and
untressed syllables (W, weak).”\footnote{Mark J. Jones & Rachael-Anne Knight, \em{The Bloomsbury
Companion to Phonetics} A&C Black, 2013, p. 134}
In nursery rhymes, S patterns usually correspond to single syllables that are “peaks” of
linguistic stress, W patterns to sequences from zero to three relatively unconstrained
syllables without accentual stress, as illustrated below.\footnote{Scansion of
a popular nursery rhyme in \em{Change de forme. Biologie et prosodie}, ed. 10/18, 1975,
ch. 4, p. 123.}

\begin[prosody=true, numbering=false]{poetry}
\v{S<S>ol\em{o<W>mon} Gr<S>und<W>y}
\v{B<S>orn \em{o<W>n a} <S>Mond<W>ay}
\v{Ch<S>rist\em{<W>ened on} <S>Tuesd<W>ay}
\v{Mar\em{<S>ried <W>on} Wed<S>nesd<W>ay}
\v{T<W>ook i<S>ll-<W>on Th<S>ursd<W>ay}
\v{W<S>orse <W>on F<S>rid<W>ay}
\v{D<S>ied <W>on <S>Sa\em{tur<W>day}}
\v{B<S>u\em{ri<W>ed on} <S>Sund<W>ay}
\v{Th<S>is \em{is<W> the} <S>end}
\v{<W>Of <S>So\em{lo<W>mon} G<S>run<W>dy}
\end{poetry}

For Old English verses, scholars generally use S for stressed patterns, x for unstressed patterns, and sometimes
Sr to mark a lift under resolution.\footnote{Eric Weiskott, \em{English Alliterative Verse}, Cambridge University Press, 2016, p. 30;
the verses are quoted from Robert D. Fulk, \em{A History of Old English Meter}, University of
Pennsylvania Press, 1992, §303–304.}

\begin[prosody=true]{poetry}
\v{\rebox[width=6em]{\em{Maldon} 32b}<x>mid <Sr>gafo<x>le f<x>org<S>yld<x>on}
\v{\rebox[width=6em]{\em{Maldon} 66b}<x>to <S>lang h<x>it h<x>im þ<S>uh<x>te.}
\v{\rebox[width=6em]{\em{Durham} 5b}<x>on fl<S>od<x>a g<x>em<S>ong<x>e.}
\end{poetry}

Other scholars, though, use different notations.\footnote{Scansion of \em{Beowulf}, v. 1391
in \em{Change de forme. Biologie et prosodie}, \em{op. cit.}}

\begin[prosody=true]{poetry}
\v{\em{Gr<Xa>endles m<X>agan g<Xa>ang sc<X>eawigan}}
\end{poetry}

In Old Greek or Latin metre, you may of course use the macron and breve glyphs
directly. Again, to simplify your typesetting, you may prefer using
a minus sign (-) for long syllables, a simple u for short syllables and a
simple x for \em{anceps} or the \em{brevis in longo}. In that case, set the \autodoc:parameter{mode} option to
\code{classical}. The abovementioned characters will then automatically be replaced
by a macron, a breve and the multiplication sign, respectively, as shown
in the following example.\footnote{Homer, \em{The Odyssey}, book I, v. 1–3 (my own scansion).}

\begin[prosody=true, mode=classical]{poetry}
\v{<->Ἄνδρ<u>α μ<u>ο|ι <->ἔνν<u>επ<u>ε, | μ<->οῦσ<u>α, π<u>ο|λ<->ύτρ<u>οπ<u>ον, | <->ὃς  μ<u>άλ<u>α | π<->ολλ<×>ὰ}
\v{πλ<->άγχθ<u>η, <u>ἐ|π<->εὶ Τρ<->οί|<->ης <u>ἱ<u>ε|ρ<->ὸν πτ<u>ολ<u>ί|<->εθρ<u>ον <u>ἔπ|<->ερσ<×>εν·}
\v{π<->ολλ<->ῶν | δ᾽<->ἀνθρ<->ώ|π<->ων <u>ἴδ<u>εν | <->ἄστ<u>ε<u>α | κ<->αὶ ν<u>ό<u>ον | <->ἔγν<x>ω}
\end{poetry}

The resulting macron and breve signs are lowered by some arbitrary amount as an attempt to make the
scansion line more regular visually. One would have hoped for the Unicode standard to define markers that fit right
with each other and that would be implemented in good fonts…

This author however finds the macron and breve glyphs a bit too small and thin, so a mode
named \code{experimental} is also proposed, using an en-dash and a small, slightly lowered, half-circle,
respectively.

\begin[prosody=true, mode=experimental]{poetry}
\v{<->Ἄνδρ<u>α μ<u>ο|ι <->ἔνν<u>επ<u>ε, | μ<->οῦσ<u>α, π<u>ο|λ<->ύτρ<u>οπ<u>ον, | <->ὃς  μ<u>άλ<u>α | π<->ολλ<×>ὰ}
\v{πλ<->άγχθ<u>η, <u>ἐ|π<->εὶ Τρ<->οί|<->ης <u>ἱ<u>ε|ρ<->ὸν πτ<u>ολ<u>ί|<->εθρ<u>ον <u>ἔπ|<->ερσ<×>εν·}
\v{π<->ολλ<->ῶν | δ᾽<->ἀνθρ<->ώ|π<->ων <u>ἴδ<u>εν | <->ἄστ<u>ε<u>α | κ<->αὶ ν<u>ό<u>ον | <->ἔγν<x>ω}
\end{poetry}

Alternately, the \code{mixed} mode is a kind of compromise, using an en-dash for the macron, but keeping
the (lowered) breve.

\begin[prosody=true, mode=mixed]{poetry}
\v{<->Ἄνδρ<u>α μ<u>ο|ι <->ἔνν<u>επ<u>ε, | μ<->οῦσ<u>α, π<u>ο|λ<->ύτρ<u>οπ<u>ον, | <->ὃς  μ<u>άλ<u>α | π<->ολλ<×>ὰ}
\v{πλ<->άγχθ<u>η, <u>ἐ|π<->εὶ Τρ<->οί|<->ης <u>ἱ<u>ε|ρ<->ὸν πτ<u>ολ<u>ί|<->εθρ<u>ον <u>ἔπ|<->ερσ<×>εν·}
\v{π<->ολλ<->ῶν | δ᾽<->ἀνθρ<->ώ|π<->ων <u>ἴδ<u>εν | <->ἄστ<u>ε<u>α | κ<->αὶ ν<u>ό<u>ον | <->ἔγν<x>ω}
\end{poetry}

This package supports cross-references as defined for instance by the \autodoc:package{labelrefs} package, if it is
loaded by the document class. In the \em{Beowulf} extract on page \conditional:ref[marker=hrothgar, type=page],
Hrothgar was mentioned in verse \conditional:ref[marker=hrothgar].

\end{document}]]

return package
