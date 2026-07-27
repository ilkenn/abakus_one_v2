# Firebase Auth Emulator — local development setup

Sprint 1 (P2-004) scope only: the **Auth emulator**, nothing else. No
Firestore/Functions/Storage emulator is configured — none is needed until a
task actually adds one of those products.

## Prerequisites (fresh clone)

1. Node.js and the Firebase CLI: `npm install -g firebase-tools` (or use an
   already-installed one — check with `firebase --version`).
2. Sign in once: `firebase login`. Use the Google account with access to
   the `abakus-one-dev` project (ask the project owner for access if you
   don't have it — the emulator itself needs no real project permissions
   to *run*, but the CLI still needs to resolve a project context from
   `firebase.json`/`.firebaserc`).

## Starting the emulator

From the repository root:

```sh
firebase emulators:start --only auth
```

- **Port**: `9099` (fixed, declared in `firebase.json`'s `emulators.auth.port`
  and mirrored in `lib/bootstrap/firebase_auth_emulator_config.dart`'s
  `FirebaseAuthEmulatorConfig.port` — if you ever change one, change both).
- **Emulator UI**: `http://localhost:4000` (enabled in `firebase.json`) —
  shows the Auth tab, useful for inspecting/adding test users while
  developing.
- Leave it running in its own terminal while you `flutter run
  --dart-define=ENVIRONMENT=development`.

## Which environment connects

Only `AppEnvironment.development` — see
`FirebaseAuthEmulatorConfig.shouldUseEmulator()`. Staging and production
always reach a real Firebase Auth backend; the emulator has no real
security behind it (by design — that's what makes it fast to develop
against), so it must never be reachable from a staging or production build,
the same reasoning `ProductionUnavailableAuthRepository` already applies to
the mock repository in release builds.

**Nothing in the app actually calls `useAuthEmulator()` yet** — that's
`FirebaseAuthRepository`'s job (Sprint 4, once `firebase_auth` is added).
This sprint only establishes the emulator itself and the (tested) decision
of which environment is allowed to use it.

## Test phone number strategy

The Auth Emulator never sends a real SMS for any phone number — every
`verifyPhoneNumber` call against it succeeds without needing a live carrier,
and the generated verification code is visible in the Emulator UI's Auth
tab (`http://localhost:4000/auth`) or in the CLI's own log output. This
requires no seed data or fixed test-number list to get started.

For a *deterministic*, script-friendly number+code pair (useful once
automated emulator-backed tests exist — Sprint 4's `P2-017`), add a fixed
test phone number via the Emulator UI (Authentication → Sign-in method →
Phone numbers for testing) and export it with
`firebase emulators:export ./emulator-seed` so it's reproducible across
machines. Not done in this sprint — no automated test needs one yet, and
`FirebaseAuthRepository` doesn't exist to test against.

## What this file intentionally does not cover

- Firestore, Functions, or Storage emulators — out of Sprint 1 scope.
- Seeding any test *data* (users, documents) — nothing consumes the
  emulator yet.
- CI wiring — decided once `P2-017`'s emulator-backed tests exist and their
  startup time is actually measured (see the Phase 2 backlog, §2.12).

No secret, API key, or credential appears in this file or in
`firebase.json`'s emulator configuration — the emulator needs none to run.
