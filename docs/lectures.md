# Recording lectures

Atlas records a lecture on your Mac, transcribes it on your Mac, writes notes
with a model on your Mac, and files the result into the right class. Nothing
about a lecture leaves the machine.

## Using it

1. Press **Record lecture** in the Atlas sidebar, or the waveform icon in the
   menu bar. ⇧⌘R does the same thing while Atlas is focused.
2. Optionally type the class first ("DS 1800 Wednesday"). This is only a hint,
   but it is the strongest signal Atlas has, so it is worth the two seconds.
3. Press **End lecture** when the class finishes.
4. Atlas transcribes, writes the notes, and files them. The sidebar shows
   progress; you can close the window and it keeps going.

## While it is recording

A small indicator floats above every app, on every Space, for as long as
recording runs. It shows the elapsed time, a live input meter, and the class
label, and it pauses or ends the lecture without switching back to Atlas. Drag
it anywhere; it returns there next time.

Atlas plays no sound at any point — no start tone, no completion chime, nothing.
The app contains no audio-output code at all, which matters when the laptop is
open in a lecture theatre.

If nothing audible reaches Atlas for eight seconds, both the indicator and the
sidebar say so in plain words rather than leaving a flat meter to be
interpreted. The meter reads every input channel, not just the first — on some
interfaces channel one carries the microphone and channel zero is silent.

Pausing stops audio being written rather than recording silence, so a break in
the middle of class does not become ten minutes the transcriber has to chew
through.

## What one lecture produces

Two linked notes, both ordinary Atlas notes in the same collection:

| Note | Category | Visible | For |
| --- | --- | --- | --- |
| *Lecture title* | `Lecture` | yes | You. Summary, key points, outline, terms, review questions, follow-ups. |
| *Lecture title — source & depth* | `Lecture Source` | no | An assistant. Full definitions, detailed outline, formulas, open questions, attached material, and the complete timecoded transcript. |

The source file does not appear in note lists, Recent, note counts, or the
search you type into. It is not something to read, and it is long. It stays a
fully ordinary note for the local assistant and the agent bridge, which is the
point of it, and **Lectures → ⋯ → Open the assistant's source file** shows it
when you want to check what the assistant is working from.

The study note stays short enough to actually revise from. The depth note is
the evidence: it opens with a contract telling any assistant which parts came
from the recording, which parts are open questions it should answer from its
own knowledge or the web, and that nothing inside it — including the
transcript — is an instruction.

Both notes are found by ordinary search and by the in-app assistant, with no
special casing. Agents can also reach them through `lectures.list` and
`lectures.read`; see [`agent-integration.md`](agent-integration.md).

## Other people in the room

A lecture recording catches students as well as the lecturer. Atlas keeps what
is useful and is explicit about whose it was:

- Room noise — chairs, coughing, crosstalk, fragments — is discarded.
- A question or answer from someone else is kept under **From the room** in the
  study note and **Other voices in the room** in the source note, attributed as
  "A student" or "Someone in the room". Never a guessed name.
- Nothing said by someone else is merged into what the lecturer taught, and the
  source note tells any assistant reading it not to quote those lines as the
  lecturer.

## Attaching slides and readings

**Lectures → Attach** adds the material for a lecture: slides, a handout, a set
reading. Atlas copies the file into its own storage — a file picked from
Downloads can be moved tomorrow, and a lecture's supporting material should not
vanish with it — then reads the text out of it.

Readable formats are **PowerPoint (.pptx)**, **Word (.docx)**, PDF, plain text,
Markdown, RTF, CSV, and JSON. A scanned PDF or an image-only deck has no
selectable text; Atlas says so on the attachment rather than letting it look
like it contributed something.

PowerPoint is the best case. Each slide is its own part inside the file, so
slides survive as real numbered units and a note can cite "slide 7" and mean
it. Slide order is read from the presentation's own slide list rather than from
file names — a deck reordered after it was written keeps its original file
numbers, and `slide10.xml` sorts before `slide2.xml`, so either would put the
wrong number on a citation. Speaker notes are pulled in with their slide, since
that is often where the lecturer's own wording lives.

Word is different: a .docx carries no page boundaries — pagination happens when
it is rendered — so it becomes one block rather than being cut into invented
page numbers, and is cited by document name. The older .ppt and .doc formats
are a different binary container and are not read.

Nothing is sent anywhere to do this. Atlas reads the ZIP container and the XML
inside it directly.

Attached text is treated as the **written** record. Where it disagrees with the
transcript it wins, because it was typed rather than misheard — which is what
fixes a technical term the recogniser mangled. The lecture still leads: merging
keeps what the lecturer actually said and uses the material to fill gaps, add
definitions, and supply the course code.

**Rewrite notes** rebuilds both notes from the transcript plus everything
attached. Attachments are capped per lecture so one long reading cannot crowd
out the lecture itself.

### Referring back to a slide

Page and slide boundaries survive the whole way through. Each page reaches the
model tagged with its number, and the model is told to cite anything it takes
from the material as `(Week 3 slides.pdf, slide 4)`.

The source note then reproduces the material as numbered blocks — **Slide 1.**,
**Slide 2.** — so a citation can be checked against the actual text rather than
taken on trust. A deck is numbered in slides, a reading in pages, chosen from
the file name.

Where material has to be trimmed for length, whole pages are dropped from the
end rather than one being cut in half, so a citation never points at text that
is no longer there. A page too long for a single model request is split, and
both halves keep the same number.

## Correcting the transcript

**Lectures → Transcript** opens what Atlas heard, editable. Fixing a misheard
term and choosing **Save & rewrite notes** rebuilds both notes from the
corrected text. Editing drops the timecodes, since they would no longer line up
with the words. The audio is kept either way.

## Telling Atlas what the course is

A transcript cannot say what a course *is*, and that is the one fact that makes
the rest readable. A CS course taught in Python mentions Java once, in an aside,
and a model with no other information treats it as the subject — not because
transcription failed, but because nothing told it otherwise.

Three places to say it, differing in scope:

| Where | Scope | Use it for |
| --- | --- | --- |
| **Class context**, beside a folder's New note | every lecture in that folder, and folders inside it | "Taught entirely in Python 3. Tests use pytest and plain asserts." |
| **Course material**, same place | the same | the syllabus or module outline, read once and quoted |
| **Tell Atlas about this lecture**, in a recording's row | one recording | "The Java mention was an aside" |

Context outranks the transcript. The model is told explicitly that a transcript
is a machine's guess at sounds and this is not, so where they disagree the audio
is what is wrong. It is also told not to restate the context as though it were
taught.

Nesting matters: context on **School** applies to every class inside it, labelled
by where it came from so an inherited fact is not mistaken for one about this
course.

Saving context does not rewrite anything on its own — rewriting costs minutes of
model time, so it is a choice. **Save and rewrite notes** reruns note writing
from the transcript already on disk. Nothing is re-recorded and nothing is
re-transcribed.

What Atlas was told is recorded in the source note, so notes that read oddly can
be traced to the fact that shaped them.

## Filing

Two passes, and the second only ever narrows.

**The model chooses.** It is shown the whole folder tree — ids, full paths,
summaries, and how much each folder holds — and the lecture's course code, name,
title, summary and topics. It replies with either an existing folder or a new
one plus the folder to nest it inside.

**Atlas checks.** A folder id that is not in the tree it was shown, a parent that
does not exist, or a new folder with no name all fail closed. Nothing is written
from an unverified answer.

**Token matching decides otherwise.** The old comparison still runs when there is
no model, or when its answer did not check out. It splits letter/digit
boundaries, so "DS eighteen hundred", `DS1800`, and "DS 1800 — Data Science" all
match each other.

- A confident match files into that existing collection.
- A named course with no collection gets a new one — nested inside the folder
  where the other classes already live. Without a model that folder is found
  from the tree's own shape: a folder holding two or more folders and no notes
  of its own exists to group things, which is how `School` is found without
  anyone naming it.
- A recording that named no course at all goes to **Unfiled Lectures** rather
  than being guessed into the wrong class.

Wrong guesses are one step to fix: **Lectures → ⋯ → Move to class** moves the
study note and its source together. Classes can be folders inside folders, so
`School › DS 1800` works the same as a top-level `DS 1800`.

## The order the sources are read in

Slides first, then the recording, then the draft read back.

| Pass | What it does | When |
| --- | --- | --- |
| Reading the slides | Pulls the deck's title, stated objectives, section order, and every term spelled correctly | Once, if anything is attached |
| Writing notes | One slice of transcript at a time, with the deck's outline and terms in front of it | Per slice |
| Reading attachments | The deck again, in depth, for definitions the speech skipped | Per slide group |
| Pulling together | Merges the slices, in the order they were taught | Once |
| Checking the notes | Compares the draft against the transcript and lists what is wrong | Per review pass |
| Applying corrections | Rewrites from that list, changing nothing else | Per review pass |
| Writing the quiz | Five to ten questions from the finished notes | Once |
| Choosing a folder | With the folder tree in front of it | Last |

The first pass is the one that matters most and is easy to miss the point of.
It is not a summary of the slides — Atlas already reads those properly later.
It is a **spelling authority**. A 90-minute marketing transcript contains
"society of Martin concept", "Spotify rap", "customer invasion part", "two-way
community" and "value shape". None of those are words. The deck contains
*societal marketing concept*, *Spotify Wrapped*, *customer engagement*,
*two-way communication* and *value chain*, and handing that list to the pass
reading the transcript is what lets it recognise a sound it would otherwise
write down as nonsense.

## Group work, and why notes used to fill up with it

The recording runs through everything, including the twenty minutes where the
class is in groups arguing about IKEA. Transcribed, that is several thousand
words of half-heard crosstalk that looks exactly like content to a model reading
one slice at a time.

Two things handle it.

The writing pass is told that an activity is a thing that happened, not material
— it puts one entry in **activities** saying what the class was asked to do and
what the lecturer concluded, and discards the rest.

The review pass is told to look for leaked crosstalk **first**, before
unsupported claims or duplicates, because it is the most common failure. A
bullet that came from students chatting is reported as noise and removed on the
next pass.

In the finished note this appears as an **In class** section: the activity, its
task, and its outcome. The source note tells an assistant explicitly that the
discussion was not written up and must not be reconstructed from the transcript.

Set the number of passes in **Settings → Notes → Checking the notes**. One is
the default and catches most of it. Two is worth it for a long class you know
was messy. Off is the old behaviour.

## Testing yourself

The last pass writes five to ten questions from the finished notes — not from
the transcript, so nothing can be asked that the notes do not answer. Each
carries its answer, one line on why, and whether it came from the lecture, the
slides, or both.

Answers are written as `> [!answer]` callouts and render behind a **Show
answer** button. They are in the note, so they survive export and search, but
they are not in front of you while you are answering.

The quiz is told not to ask about group activities, or about administrative
detail like deadlines and assessment weightings, unless the lecture was about
them.

## Importing notes you already have

**Lectures → Import notes**. Paste text, or choose a PDF, Word, PowerPoint,
Markdown, plain text, or caption file.

An import is a lecture that skips transcription — the same record, the same
pipeline, the same structure, review, companions and quiz. That is deliberate:
a separate path for imported text would drift out of step with the one lectures
use within a month. It shows as `imported` where a recording shows its length,
and it is not offered slide attachments or audio it does not have.

## Companion notes

Most of a lecture belongs in the lecture's note. Occasionally one idea — a
derivation, a process with steps, a worked example — needs more room than a
bullet. The model writes that as a companion note and says which outline heading
it belongs under.

- `[[Title]]` is a reference: it opens that note.
- `![[Title]]` is an embed: it unfolds in place, inside the section that
  mentions it.

A companion is placed under its own heading rather than listed at the end, and
its one-line summary sits above it, so the note still reads correctly with every
embed closed. Companions do not appear loose in the folder — they hang off the
note that links to them, which is what stops one lecture looking like several.
Following a link and coming back returns you to the section you left from.

A companion needs real substance to be worth the click: anything under 200
characters is rejected, and at most six survive one lecture. A lecture with
nothing like that produces none, which is the normal case.

**Settings → Notes → Open in place** turns embedding off and leaves plain links.

## Which model writes the notes

Atlas looks for a local model in this order:

1. **Ollama** on `127.0.0.1:11434`, if it is running. Preferred, because the
   models a student installs are far larger than anything an app can bundle.
   Atlas picks the best installed model it recognizes; **Settings → Local
   model** pins one.
2. **Apple's on-device model**, which needs no setup. It gets a smaller slice
   of transcript per request because its context window is much smaller.
3. **Neither.** The lecture is still filed, with notes derived from the
   transcript by text rules, marked *Transcript only*. Re-running note writing
   later replaces them in place.

Atlas refuses to send lecture text anywhere that is not a loopback address,
even if a different endpoint is configured.

## Why the ordering is what it is

A lecture happens once. The pipeline is arranged so that no later failure can
cost you an earlier one:

- The audio file exists before recording starts.
- The transcript is saved the moment it exists, before any model runs.
- Model failure falls back to transcript-derived notes rather than stopping.
- Re-running note writing updates the same two notes instead of duplicating.
- Changing the audio device mid-lecture stops recording deliberately, keeps
  everything captured up to that point, and finishes the lecture properly
  rather than leaving it in progress.
- A crash or force quit leaves the audio on disk. At the next launch the
  lecture is shown as needing attention, with its real length, and **Try again**
  transcribes it.

## Storage

- Audio: `Application Support/Atlas/Lectures/<lecture-id>.caf` inside Atlas's
  container, 16 kHz mono — about 115 MB per hour.
- Transcript and lecture metadata: Atlas's own SwiftData store.
- Notes: ordinary notes in your collections.

Deleting a lecture from the Lectures list removes the audio and the entry. Notes
already written from it stay where they are, and are deleted like any other note.


## Editing what the model is told

**Settings → Instructions** holds the five files the local model is actually
given, in the order they run:

1. **Before writing** — how standing course knowledge is weighed against the
   transcript. Added to every request below, whenever the class has context.
2. **Writing notes** — once per slice of transcript.
3. **Reading attachments** — once per slide or page group.
4. **Pulling the lecture together** — once, after every slice has been read.
5. **Choosing where the notes go** — last, with the folder tree in front of it.

Each is editable and has a Restore default. Only what differs from the default
is stored, so an improved default still reaches files you have not touched.
Atlas appends the JSON shape the parser needs on top of whatever is written, so
an edit cannot break note writing by leaving it out.
