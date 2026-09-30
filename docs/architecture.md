# Atlas architecture

## Current boundary

Atlas Native is a full offline-first client. It does not include a backend, authentication authority, remote synchronization, analytics, payments, or third-party data processing. The app is useful without those systems: a user can enter an explicitly labeled offline workspace and manage local notes.

## Repository layout

- `Atlas/` contains the shared multiplatform SwiftUI app and platform presentation.
- `Atlas/Lectures/` contains macOS lecture capture and the pipeline coordinator.
- `packages/AtlasCore/` contains models, SwiftData persistence, Markdown section parsing, Keychain storage, and the one remote authentication client.
- `Config/` contains the three non-secret build configurations.
- `docs/` contains architecture and operational boundaries.
- `../career-hub/` is the independent companion website.

Both Apple platforms use the same app target and the same AtlasCore package. Platform behavior must stay inside small conditional blocks rather than duplicated feature trees.

## Local data

The UI reads from SwiftData through `AtlasLibraryStore`. Seed content is decoded through explicit DTOs, imported only when the local collection store is empty, and then treated as user-owned local data. Mutations validate bounded fields and surface persistence failures.

On macOS, `AtlasAgentBridge` is the only automation boundary. It exchanges
versioned, owner-only request and response files inside Atlas's sandbox
container, then delegates every operation to `AtlasLibraryStore`. Agents never
receive a database path or arbitrary filesystem access. The protocol exposes
collection listing and note search/read/create/conflict-safe update; deletion
remains in the visible app.

## Collection hierarchy

`AtlasCollectionRecord.parentID` is optional, so an existing flat library
migrates with no conversion step and a collection whose parent has vanished is
treated as a root rather than disappearing. `AtlasLibraryStore+Hierarchy`
owns tree building, re-parenting, and deletion; it refuses cycles, caps nesting
at `maximumCollectionDepth`, and will not delete a collection that still holds
notes or subfolders. Tree building also carries a visited set, so a parent chain
corrupted from outside cannot loop the sidebar.

## Lecture capture

Recording, transcription, note writing, and filing run entirely on the device.
`Atlas/Lectures/` holds the capture pieces that need AppKit and the app
lifecycle; `packages/AtlasCore/Sources/AtlasCore/Lectures/` holds everything
testable — the structured output types, the model clients, chunking,
classification, note rendering, and on-device transcription.

The pipeline is ordered so that no later failure destroys an earlier result.
Audio exists on disk before capture starts, the transcript is committed before
any model runs, and model failure degrades to transcript-derived notes rather
than aborting. Re-running note writing updates the same two notes.

One lecture produces two ordinary notes rather than a new record type, so
search, the local assistant, and the agent bridge reach them with no special
casing. `AtlasLectureRecord` holds only the recording itself and the links.

### Network boundary

Atlas ships no backend and makes no remote requests. It does now hold
`com.apple.security.network.client`, for one purpose: reaching a local model
server on `127.0.0.1`. `LoopbackGuard` rejects every non-loopback host before a
request is built, so a mistyped or pasted remote endpoint cannot turn local
note-taking into an upload of a recording of identifiable people. Apple's
on-device model is used when no local server is running, and needs no network
at all.

## Authentication boundary

Offline workspace access is not an authenticated account and is labeled accordingly. Sign in with Apple can become active only when all of the following exist:

1. Apple capabilities and signing are configured for the final bundle identifiers.
2. `ATLAS_API_BASE_URL` points to an HTTPS service.
3. The service implements `/v1/auth/apple`, verifies Apple's signed credential, creates or finds the account, and returns short-lived access plus rotating refresh tokens.
4. The server implements session revocation, rate limits, structured errors, and the complete authorization tests required by `AGENTS.md`.

The client keeps access tokens in memory and stores only the refresh token in the device Keychain. A client credential alone never changes the session to signed-in.

## Next backend gate

Backend language, host, server database, retention, backup, and secrets manager remain deliberately undecided. Selecting them changes the Project Contract and requires explicit user approval before implementation. The first backend change must include a versioned OpenAPI contract, health/readiness routes, the Apple verification endpoint, rate limits, idempotency, and authorization-matrix tests.
