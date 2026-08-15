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
3. **Java 21 or newer** — recent `firebase-tools` versions refuse to start
   the Firestore Emulator on Java below 21 (`Error: firebase-tools no
   longer supports Java version before 21`). Check with `java -version`;
   if it reports 17 or lower despite a JDK 21 being installed, your
   `PATH` is likely resolving an older `java` first — put the JDK 21
   `bin` directory ahead of it (or fix `JAVA_HOME`/`PATH` so they agree),
   rather than reinstalling. This is a machine setup prerequisite, not
   something any script in this repo works around.

**Test isolation note**: `firestore-tests`/`functions`'s `npm run
test:emulator` scripts use `firebase emulators:exec`, which starts and
tears down a fresh, empty emulator instance per run — the reliable way to
run these suites. Running the underlying `npm test` directly against an
*already-running*, long-lived emulator instance (e.g. one kept open for
manual physical-device testing) works, but test fixtures with fixed
document ids (`orders/order-1`, `deletionRequests/req-1`, etc.) persist
across repeated runs and can collide with themselves — a `create`
silently becomes an `update` against a document a *prior* run already
left behind, and `allow update: if false` then fails the test for a
reason unrelated to the code under test. Prefer `emulators:exec` (this
requires prerequisite 3 above); if you must run against a live instance,
clear the specific fixture documents first.

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

`FirebaseBootstrapService.initialize` (`lib/bootstrap/firebase_bootstrap_service.dart`)
calls `useAuthEmulator`/`useFirestoreEmulator`/`useStorageEmulator`/
`useFunctionsEmulator` for all four products in one pass, every time
`AppEnvironment.current == AppEnvironment.development`, always with
`automaticHostMapping: false` (see that file's own doc comment for why —
in short, the default `true` behavior silently rewrites `127.0.0.1` to
`10.0.2.2` on Android, which `adb reverse` cannot reach). Each connector is
independent and non-fatal: a failure connecting one emulator (e.g. it
isn't running) is caught and logged, and never stops the others from
connecting.

## Physical Android device setup (`adb reverse`)

A physical device has no route to your development machine's `localhost`
by default. `adb reverse` forwards a TCP port *on the device* back to the
same port on the host machine over the USB/ADB connection — run these with
the device connected and the emulator suite already started, before (or
any time before) you exercise the corresponding feature in the running
app:

```sh
adb reverse tcp:9099 tcp:9099   # Auth
adb reverse tcp:8080 tcp:8080   # Firestore
adb reverse tcp:9199 tcp:9199   # Storage
adb reverse tcp:5001 tcp:5001   # Functions
adb reverse tcp:4000 tcp:4000   # Emulator UI (optional, for browsing http://127.0.0.1:4000 from the device's own browser)
```

`adb reverse --list` shows currently active forwards; bindings are lost on
device disconnect/reboot and must be re-run. `FirebaseXEmulatorConfig.host`
defaults to `127.0.0.1` (not `10.0.2.2`) specifically because this is the
real-device workflow this app is built around — see
`firebase_functions_emulator_config.dart`/`firebase_auth_emulator_config.dart`
for the Android-Emulator-only alternative
(`--dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2`, no `adb reverse` needed
since the Android Emulator already resolves `10.0.2.2` to the host).

**If a callable/Firestore/Auth call from a physical device produces no
request in the emulator's own terminal at all** (not even a rejected
one), check, in order: (1) `adb reverse --list` still shows the binding
for that exact port — bindings silently drop on device reconnect; (2) the
Emulator UI (`http://127.0.0.1:4000`) lists that specific emulator as
running — `--only auth,firestore` omits Functions/Storage entirely, and a
missing emulator produces no logs, not an error; (3) the app was actually
built for the `development` flavor/environment (a `production`-flavor
build never calls any `use*Emulator` method at all, by design — see
"Which environment connects" above). A configuration bug in this app's own
`use*Emulator` wiring is comparatively unlikely to reach only *one*
product's callable and not others, since all four share one code path in
`FirebaseBootstrapService.initialize`.

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
