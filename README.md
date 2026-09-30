# Atlas

**A private, on-device knowledge app for Mac and iPhone that turns recorded lectures into structured study notes — with no cloud.**

Atlas is a native SwiftUI notes library (iOS 18+ / macOS 15+) built around one idea:
a lecture cannot be re-attended, so capturing it must never lose data and must
never leave the device. Press **Record lecture**, and Atlas records audio,
transcribes it with Apple's on-device speech models, reads the slides you
attach, writes and self-reviews notes with a local LLM, generates a quiz, and
files everything into the right class folder.

### Highlights

- **Crash-safe lecture pipeline** — audio hits disk before capture starts, the
  transcript is committed before any model runs, and model failure degrades to
  transcript-derived notes instead of aborting. Nothing later can destroy
  anything earlier.
- **Slides-first transcript repair** — the deck is read before the recording,
  so technical terms the speech model mishears ("society of Martin concept")
  are corrected to what the slides say ("societal marketing concept").
- **Multi-pass local LLM** — outline, draft, review, revise, quiz, and folder
  placement passes against Ollama on `127.0.0.1`, falling back to Apple's
  on-device Foundation model, then to rule-based notes. A `LoopbackGuard`
  refuses every non-loopback host.
- **Editable prompt "skills"** — the nine instruction files the model receives
  are user-editable in Settings, with the JSON output contract appended by the
  app so an edit cannot break parsing.
- **Obsidian-style linking** — `[[links]]` and `![[embeds]]` that unfold a
  companion note in place; nested folders up to six levels.
- **Document ingestion** — PDF, Word, PowerPoint (a small ZIP/OOXML reader, no
  dependencies), Markdown, and `.vtt`/`.srt` imports go through the same pipeline.
- **Trackpad Sketch Pad** — the Mac trackpad as an absolute-position drawing
  surface, filed into notes as embedded sketches.
- **Agent bridge** — a typed, owner-only local protocol that lets AI agents
  search, read, create, and conflict-safely update notes without ever touching
  the database.
- **Self-healing store** — lectures lost to a SwiftData downgrade are rebuilt at
  launch from their source notes and the audio on disk.

### Tech

Swift 6 (strict concurrency) · SwiftUI · SwiftData · AVAudioEngine ·
SpeechAnalyzer / SpeechTranscriber · Foundation Models · Ollama · Keychain ·
Swift Testing. Zero third-party dependencies. **225 unit tests** in the
`AtlasCore` package, plus opt-in live-model and real-lecture suites.

### Layout

| Path | What lives there |
| --- | --- |
| `Atlas/` | The multiplatform SwiftUI app: views, design system, app model |
| `Atlas/Lectures/` | macOS audio capture and the pipeline coordinator |
| `Atlas/Sketch/` | The trackpad Sketch Pad window |
| `packages/AtlasCore/` | Everything testable: models, persistence, Markdown parsing, model clients, transcription, note building |
| `Config/` | Local / Staging / Production build settings (no secrets) |
| `docs/` | [Architecture](docs/architecture.md), [lectures](docs/lectures.md), [agent integration](docs/agent-integration.md), [runbook](docs/runbook.md) |

`AGENTS.md` holds the engineering rules every coding agent working on this repo
follows. The project was built with AI coding agents (OpenAI Codex and
Anthropic Claude Code) under that contract, with every change tested.

The companion Atlas website (`career-hub`) lives in a separate project; the
Markdown content contract is shared between them.

## Open and run

1. Open `Atlas.xcodeproj` in Xcode.
2. Select the **Atlas** scheme.
3. Choose **My Mac** or an iPhone simulator.
4. Press Run.
5. On the welcome screen, choose **Continue with this Mac** to enter the offline workspace.

The Apple sign-in control is intentionally backend-gated. It obtains Apple credentials and sends them only to a configured HTTPS `/v1/auth/apple` service for verification. With no backend URL configured, Atlas reports that remote sign-in is unavailable and never treats an unverified client credential as an authenticated account.

Local Mac builds use a sandbox-only entitlement file, so they can be signed and
launched without falsely claiming an Apple provisioning profile. Production
sign-in keeps the Apple entitlement and remains ready for the owner's developer
team and HTTPS backend.

## Content and storage

- The initial library is bundled in `Atlas/Resources/SeedContent.json`.
- On first launch it is imported into the app's private SwiftData store.
- New collections, new notes, edits, favorites, and deletions persist locally.
- Each `##` Markdown heading becomes a navigable document section.
- Paragraphs, subheadings, lists, task checkboxes, blockquotes, links, code fences, and tables render as distinct native components.
- Headings inside fenced code examples remain code instead of becoming navigation items.
- Existing local data is never silently replaced when the bundled seed changes.

## Folders

Collections are folders, and folders hold folders. Nest up to six levels deep —
School › DS 1800 › Unit 2 — with the disclosure triangles in the sidebar.

- **+** beside FOLDERS makes one at the top level.
- Right-click a folder for **New folder inside** or **Folder settings…**, where
  you can rename it, move it somewhere else, or delete it.
- A folder is only deletable once it is empty, and Atlas says what is still in
  it rather than removing anything silently.
- A folder cannot be moved inside itself or anything it already contains; those
  destinations are simply not offered.
- A parent folder's count reads `2 notes · 5 nested`, so a folder used purely
  for grouping does not look empty.

## Appearance

Use the palette button beside the offline account to open **Personalize Atlas**. Atlas includes System, Light, and Dark display modes; Forest, Ocean, Violet, and Ember color themes; and four selectable vector logo concepts. Appearance choices are device-local preferences and contain no account or note data.

The cross-interface Markdown contract for future content lives in `../career-hub/content/AUTHORING_GUIDE.md`. The bundled starter library is regenerated from that source so Mac, iPhone, and website notes keep the same structure.

## Recording lectures

Press **Record lecture** in the sidebar, or use the waveform menu bar item, and
press **End lecture** when class finishes. Atlas transcribes the recording with
Apple's on-device speech models, writes notes with a local model, and files the
result into the right class as two linked notes: readable study notes, and a
source note holding the full transcript and deeper explanations for assistant
use.

Attach the slides or reading for a lecture and Atlas reads their text too,
using the written wording to correct terms the audio misheard. The source file
holding the full transcript stays out of your note lists — it is written for an
assistant, not for reading.

## Telling Atlas about a class

A transcript cannot say what the course *is*. Without that, a language named
once in an aside looks exactly like the subject, and the notes confidently
describe the wrong thing.

- **Class context** beside a folder's New note: plain sentences about the
  course. Saved once, used on every lecture in that folder, and inherited by
  folders inside it. It outranks the transcript — where they disagree, Atlas
  treats the audio as misheard.
- **Course material** in the same place: a syllabus or module outline, read once
  and quoted to the model on every lecture in the class.
- **Tell Atlas about this lecture**, inside a recording's row: what this one
  recording needs, or what the notes got wrong. **Save and rewrite notes**
  reruns note writing from the existing transcript — no re-recording, no
  re-transcribing.

Where the notes are filed is also a judgement, so the model makes it with your
folder tree in front of it. Its answer is checked against that tree before
anything is written: a folder it invented is discarded and token matching
decides instead. A new class is created beside your other classes rather than at
the top level next to the folder holding them.

## How a lecture is read

The slides are read **first**, not alongside.

A transcript is a machine's guess at sounds, and technical vocabulary is what it
guesses worst: a marketing lecture arrives saying "society of Martin concept",
"Spotify rap", "customer invasion part". The deck says *societal marketing
concept*, *Spotify Wrapped*, *customer engagement*. So Atlas reads the deck
before the recording and takes from it the lecture's skeleton — its title, the
learning objectives it states, its section order, and every term spelled
correctly — then puts that in front of every pass that touches the transcript,
with the instruction that a sound resembling one of those terms *is* that term.

Reading the two independently and merging afterwards, which is what happened
before, never taught the transcript pass the right word.

Then the draft is read back. A review pass compares it against the transcript
and lists what is wrong; a revision pass applies the list. **Settings → Notes →
Checking the notes** sets this to off, one pass, or two.

## Noise, and what to do with it

A recording does not pause for group work. Half an hour into a class the
transcript becomes several students talking over each other, half-heard, and
none of it is what the lecturer taught.

Atlas treats an activity as a thing that happened rather than as content. It
records what the class was asked to do and what the lecturer drew out of it
afterwards, in an **In class** section, and discards the discussion. The review
pass is told to look for leaked crosstalk before anything else, because it is
the most common way these notes go wrong — and the source note tells an
assistant not to reconstruct an activity from the transcript, because those
minutes are chatter.

## Testing yourself

Every lecture gets five to ten questions written from the finished notes, with
the answers folded away behind **Show answer** so a quiz is a quiz rather than a
list of facts. Each question records whether it came from the lecture, the
slides, or both. Turn it off in **Settings → Notes**.

## Importing notes

**Lectures → Import notes** takes text you already have — a reading, a page you
copied, a transcript from somewhere else, someone else's notes — and gives it
the same treatment a recording gets: outline, terms, review, companions, quiz,
and filing into a class. Paste it, or choose a PDF, Word, PowerPoint, Markdown,
plain text, or `.vtt`/`.srt` file.

An import is deliberately the same object as a recording, minus transcription,
so it cannot drift out of step with the pipeline lectures use.

## Settings

The gear beside the account opens four tabs.

- **Notes** — which sections a lecture note contains, and how much detail. The
  detail setting is sent to the model, so it writes to that length rather than
  being cut down to it.
- **Instructions** — the nine files the local model is actually given, in the
  order they run: the house style, what Atlas already knows, reading the slides,
  writing notes, reading attachments, pulling the lecture together, checking the
  notes, writing the quiz, choosing a folder. Edit one and the next set of notes
  is written differently; each has a Restore default. Atlas appends the JSON
  shape it needs on top, so an edit cannot break note writing by leaving it out.

  The **house style** is the one to read first. It goes on top of every other
  pass and is where the goal lives: what these notes are for, what the sections
  are and what each is for, what good looks like, and what is not content.
  Changing it changes all nine passes at once.
- **Local model** — which installed Ollama model to prefer.
- **Appearance** — colour, light/dark, and the Atlas mark.

## Linked and embedded notes

When the model decides one idea needs a full work-through, it writes a companion
note and references it the way Obsidian does.

- `[[Note title]]` is a link: it opens that note.
- `![[Note title]]` is an embed: the note unfolds in place, inside the section
  that mentions it, without leaving the page.

A companion is placed under the outline heading it belongs to rather than listed
at the bottom, and it does not appear loose in the folder — the main note is the
way in. Following a link and then coming back returns you to the section you
left from, not the top of the page.

Notes come from Ollama on `127.0.0.1:11434` when it is running, Apple's
on-device model otherwise, and from the transcript itself when neither is
available. Lecture text is never sent to a non-loopback address. See
[`docs/lectures.md`](docs/lectures.md).

## Sketch Pad (macOS)

**Sketch Pad** in the sidebar opens a drawing window that treats the trackpad
as an absolute-position surface: where your finger is on the pad is where the
pen is in the frame. The page is larger than the frame — hold **W A S D** to
pan, zoom in and out, and follow your place on the minimap. Undo is per stroke.

**Save** files the sketch either as a new note in a folder, or into an existing
lecture's notes under a `## Sketches` section. A sketch is referenced from the
note body by an `atlas-sketch://<id>` embed line, so it renders inline and
survives edits to the text around it.

## Agent tools

The macOS app exposes an owner-only local bridge for typed note search, read,
create, conflict-safe update, and read-only lecture operations. See
[`docs/agent-integration.md`](docs/agent-integration.md). Atlas remains the only
process that touches its SwiftData store, and deletion is not exposed to agents.

## Environments

The Xcode project has **Local**, **Staging**, and **Production** configurations. Local and Staging builds display their environment in the interface. Backend URLs are deliberately blank in committed configuration. When a backend exists, set `ATLAS_API_BASE_URL` to its HTTPS origin using an uncommitted developer or CI configuration layer.

## Validation

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/AtlasCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Local -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Local -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Those two `xcodebuild` lines check that it compiles. **Do not run the app they
produce.** `CODE_SIGNING_ALLOWED=NO` strips the entitlements, and an unsandboxed
Atlas reads a different, empty library at
`~/Library/Application Support/AtlasLibrary.store` instead of your real one in
`~/Library/Containers/com.nickmadaio.atlas.local/`. To build something runnable,
sign it ad-hoc so the sandbox entitlement is applied:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Local -destination 'platform=macOS' -derivedDataPath .derived CODE_SIGN_IDENTITY="-" build
```

Never open your library with a build of Atlas older than the lecture feature.
Core Data migrates the store down to whatever model that build declares, which
drops the lecture and attachment tables. Atlas rebuilds what it can at the next
launch — the source notes hold the transcript and the details table, and the
audio is untouched on disk — but the rows themselves are gone until it does.

Signing, Sign in with Apple, real-device testing, TestFlight, notarization, support URLs, and App Store privacy declarations require the owner's Apple Developer team and release decisions. They are not represented as completed by a local unsigned build.

For automated Local-build visual inspection only, `--atlas-open-offline` opens directly into the offline workspace, `--atlas-open-first-note` selects the first available note, and `--atlas-open-assistant` presents the contextual helper. These switches are compiled out of Staging and Production builds.
