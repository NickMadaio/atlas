# Atlas

A notes app for Mac and iPhone that records lectures and turns them into study
notes, entirely on-device. Nothing is sent to the cloud.

Hit **Record lecture**, and Atlas saves the audio, transcribes it with Apple's
on-device speech recognition, reads any slides you attach, writes notes and a
quiz with a local LLM, and files the result into the right class folder.

Built with SwiftUI and SwiftData for iOS 18+ and macOS 15+.

## Features

- **Lecture recording** with on-device transcription (`SpeechAnalyzer`)
- **Slide-aware notes**: the slide deck is read before the transcript, so terms
  the speech model mishears get corrected to what the slides actually say
- **Local LLM pipeline**: outline → draft → review → revise → quiz, using
  Ollama on localhost, falling back to Apple's on-device model, then to
  rule-based notes if neither is available
- **Editable prompts**: every instruction the model gets can be edited in
  Settings
- **Imports**: PDF, Word, PowerPoint, Markdown, and `.vtt`/`.srt` files go
  through the same pipeline as a recording
- **Linked notes**: `[[links]]` and `![[embeds]]`, Obsidian-style, plus nested
  folders
- **Sketch Pad** (macOS): draw with the trackpad and embed sketches in notes
- **Agent bridge** (macOS): a local file-based API so scripts and AI agents can
  search, read, create, and update notes without touching the database

## Design notes

**A lecture can't be re-recorded, so nothing downstream is allowed to lose
data upstream.** Audio is on disk before capture starts, the transcript is
saved before any model runs, and if the model fails the app still produces
notes from the transcript. Re-running note generation updates the same notes
instead of making new ones.

**Privacy.** The app has network access only to reach a model server on
`127.0.0.1`. `LoopbackGuard` rejects any other host before a request is built.

**Recovery.** If the SwiftData store ever loses its lecture tables (e.g. after
opening it with an older build), Atlas rebuilds them at launch from the source
notes and the audio files on disk.

More detail in [`docs/architecture.md`](docs/architecture.md) and
[`docs/lectures.md`](docs/lectures.md).

## Tech

Swift 6 · SwiftUI · SwiftData · AVAudioEngine · Speech · Foundation Models ·
Ollama · Keychain · Swift Testing

No third-party dependencies. The Office file reader is a small ZIP/XML parser
written for this project.

## Project layout

| Path | Contents |
| --- | --- |
| `Atlas/` | SwiftUI app: views, design system, app model |
| `Atlas/Lectures/` | Audio capture and the recording pipeline (macOS) |
| `Atlas/Sketch/` | Sketch Pad window (macOS) |
| `packages/AtlasCore/` | Models, persistence, Markdown parsing, LLM clients, transcription, note building, and tests |
| `Config/` | Local / Staging / Production build settings |
| `docs/` | Architecture, lectures, agent API, runbook |

## Running it

1. Open `Atlas.xcodeproj` in Xcode.
2. Pick the **Atlas** scheme and **My Mac** or an iPhone simulator.
3. Run, then choose **Continue with this Mac** on the welcome screen.

For better lecture notes, install [Ollama](https://ollama.com) and pull a
model. Atlas picks it up automatically. Without it, Atlas uses Apple's
on-device model.

Sign in with Apple is wired up but disabled until there is a backend to verify
credentials against. The app works fully offline without it.

## Tests

```sh
swift test --package-path packages/AtlasCore
```

225 tests cover the library store, Markdown parsing, folder hierarchy, the
lecture pipeline, imports, recovery, and sketches. Two extra suites run against
a real Ollama model and are opt-in via environment variables; see
`LiveModelTests.swift` and `RealLectureTests.swift`.

### Building a runnable Mac app

```sh
xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Local \
  -destination 'platform=macOS' -derivedDataPath .derived CODE_SIGN_IDENTITY="-" build
```

Sign ad-hoc (`CODE_SIGN_IDENTITY="-"`), not with `CODE_SIGNING_ALLOWED=NO`.
An unsigned build runs outside the sandbox and opens a different, empty
library instead of the real one in
`~/Library/Containers/com.nickmadaio.atlas.local/`.

Don't open an existing library with a build older than the lecture feature.
SwiftData migrates the store down to that build's model and drops the lecture
tables. Atlas can rebuild them, but folder nesting is lost.

## Configurations

**Local**, **Staging**, and **Production** build configurations. Backend URLs
are blank in the committed config; set `ATLAS_API_BASE_URL` in an uncommitted
`.xcconfig` when a backend exists.
