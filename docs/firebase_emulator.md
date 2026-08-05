# Firebase Emulator Suite — local development setup

Auth emulator: Sprint 1 (P2-004). Firestore/Storage/Functions emulators:
Phase 9 Sprint 9A (`docs/decisions.md` ADR-026) — configuration and
connection-decision classes only, mirroring Sprint 1's own "establish the
emulator and the tested decision of which environment may use it, ahead of
a real consumer" scope. No Messaging emulator exists (Cloud Messaging has
no local emulator in the Firebase Emulator Suite as of this writing — real
FCM sends always go through the real backend, even in development).

## Prerequisites (fresh clone)

1. Node.js and the Firebase CLI: `npm install -g firebase-tools` (or use an
   already-installed one — check with `firebase --version`).
2. Sign in once: `firebase login`. Use the Google account with access to
   the `abakus-one-dev` project (ask the project owner for access if you
   don't have it — the emulators themselves need no real project
   permissions to *run*, but the CLI still needs to resolve a project
   context from `firebase.json`/`.firebaserc`).

## Starting the emulators

From the repository root, start everything this app currently configures:

```sh
firebase emulators:start
```

Or start only what a given task needs (faster startup):

```sh
firebase emulators:start --only auth,firestore
```

| Emulator | Port | Config class |
|---|---|---|
| Auth | `9099` | `lib/bootstrap/firebase_auth_emulator_config.dart` (`FirebaseAuthEmulatorConfig`) |
| Firestore | `8080` | `lib/bootstrap/firebase_firestore_emulator_config.dart` (`FirebaseFirestoreEmulatorConfig`) |
| Storage | `9199` | `lib/bootstrap/firebase_storage_emulator_config.dart` (`FirebaseStorageEmulatorConfig`) |
| Functions | `5001` | `lib/bootstrap/firebase_functions_emulator_config.dart` (`FirebaseFunctionsEmulatorConfig`) |
| Emulator UI | `4000` | n/a — `http://localhost:4000` |

Every port is declared in `firebase.json`'s `emulators` block **and**
mirrored by hand in its matching config class — `firebase.json` is read by
the `firebase` CLI, not by this app, so there's no single source of truth
to derive one from the other without adding a JSON-parsing dependency for a
handful of well-known constants. If you ever change one, change both.

Leave the emulator suite running in its own terminal while you
`flutter run --dart-define=ENVIRONMENT=development`.

## Which environment connects

Only `AppEnvironment.development`, for every one of the four config
classes' `shouldUseEmulator()` — staging and production always reach the
real backend. None of the local emulators have real security-rule
enforcement guaranteed under active local edits, and none persist data
reliably across a machine reset — letting staging or production connect
would be the same class of mistake `ProductionUnavailableAuthRepository`'s
`kReleaseMode` gate already exists to prevent for the mock auth repository,
applied identically here to every emulator.

**Nothing in the app actually calls `useFirestoreEmulator()`/
`useStorageEmulator()`/`useFunctionsEmulator()` yet** — connecting real
`FirebaseAuth`/`FirebaseFirestore`/`FirebaseStorage`/
`FirebaseFunctions` SDK instances to these emulators is each consuming
sprint's own job (9B for Firestore, 9H for Storage, 9F for Functions).
This sprint only establishes the emulators themselves and the (tested)
decision of which environment is allowed to use each — the same shape
Sprint 1 already established for Auth, extended to the other three.

## Test phone number strategy

Unchanged from Sprint 1 — see the Auth Emulator UI's own Authentication tab
for adding deterministic test phone numbers once an automated
emulator-backed auth test needs one.

## What this file intentionally does not cover

- Seeding any test *data* (Firestore documents, Storage objects) — nothing
  consumes these emulators yet.
- CI wiring for emulator-backed tests — decided once a real emulator-backed
  test suite exists and its startup time is actually measured.
- Security Rules content — see `firestore.rules`/`storage.rules` (Phase 9
  Sprint 9B) once they exist, not this file.
- Cloud Functions source/deployment — see `functions/` (Phase 9 Sprint 9F)
  once it exists.

No secret, API key, or credential appears in this file or in
`firebase.json`'s emulator configuration — the emulators need none to run.
