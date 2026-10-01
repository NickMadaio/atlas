# Atlas runbook

## Current version

Version 1 has no backend, production environment, remote sessions, secrets, deploy, billing, or server backup. Corresponding production procedures are not applicable yet and must be added in the same change that introduces those systems.

## Local recovery

If the app cannot open its library, preserve the existing app container before troubleshooting. Do not delete the application container as a first response because it contains the user's local notes. Rebuild the app and inspect the surfaced error; a corrupt local store must be recovered or explicitly exported before replacement.

## Local installation

The working macOS build is installed at `/Applications/Atlas.app` with bundle
ID `com.nickmadaio.atlas.local`. It uses the sandbox-only Local entitlement and
the existing local signing identity. Replacing the bundle does not
replace its app container or notes. Preserve the prior bundle in a temporary
backup, verify the new signature, launch it normally, and complete a typed
agent read plus conflict-safe update before calling the installation healthy.

The Local build is not a notarized public release. Do not enable the Production
Apple-sign-in entitlement until an Apple Developer team, provisioning profile,
and the verified HTTPS authentication backend are all available.

## Local sign-out

Sign Out removes the refresh-token Keychain item and clears the in-memory access token. Offline note data remains on the device. Remote session revocation cannot exist until the backend is implemented, so production account sign-out must not ship before server revocation is added.

## Release gates

Before any external release, complete real-device testing, signing, privacy disclosures, support/privacy URLs, and—for macOS direct distribution—notarization and stapling.
