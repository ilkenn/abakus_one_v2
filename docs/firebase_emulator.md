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
one), check, in order:

1. **The Android Gradle product flavor actually installed on the device is
   `development`, independently of `--dart-define=ENVIRONMENT`** — a
   real, confirmed root cause (Paket Servis P.3 device-blocker follow-up,
   2026-08-17; see `docs/decisions.md` Paket Servis P.3 §D12 for the full
   investigation). `--flavor development` (a native Gradle build
   selection, merges `android/app/src/development/AndroidManifest.xml` +
   its `network_security_config.xml`, which is the **only** thing that
   permits cleartext HTTP to `127.0.0.1`/`10.0.2.2`/`localhost` on this
   app) and `--dart-define=ENVIRONMENT=development` (a Dart-only compile
   define, controls `AppEnvironment.current` and therefore whether
   `FirebaseBootstrapService` calls any `use*Emulator` method at all) are
   **two structurally independent selection mechanisms** — Flutter/Gradle
   never cross-validates them, and `AppEnvironment.fromDefine` silently
   defaults to `development` when the dart-define is simply omitted (by
   design, so a plain `flutter run` works). It is entirely possible — and
   is exactly what produced this bug — to run/install a **non**-`development`
   Gradle flavor (e.g. an IDE "Build Variant" left on `productionDebug`
   while the Run/Debug configuration's dart-defines still say
   `ENVIRONMENT=development`) while the compiled Dart code still believes
   it is `development` and unconditionally attempts `useFunctionsEmulator`
   (and the other three `use*Emulator` calls). The resulting plaintext
   `127.0.0.1:5001` connection is then **blocked by Android's default
   cleartext-traffic policy before it ever reaches `adb reverse` or the
   emulator's own HTTP server** — zero request, zero log line, on either
   side — and the low-level platform/network exception that results
   surfaces to Dart as a raw, unhelpful `ExecutionException`/similar
   (which this app's own callable gateways now catch and translate to a
   safe, generic message — see `docs/decisions.md` Paket Servis P.3 §D11/
   §D12 — but the underlying call still never reaches the emulator).
   **Fix**: rebuild/reinstall making sure the Android build variant/flavor
   actually selected is `development` (e.g. `flutter run --flavor
   development --dart-define=ENVIRONMENT=development` from the CLI, or —
   in an IDE — confirm the Build Variant dropdown and the Run
   Configuration's additional args agree, not just one of the two).
2. `adb reverse --list` still shows the binding for that exact port —
   bindings silently drop on device reconnect.
3. The Emulator UI (`http://127.0.0.1:4000`) lists that specific emulator
   as running — `--only auth,firestore` omits Functions/Storage entirely,
   and a missing emulator produces no logs, not an error.

A configuration bug in this app's own `use*Emulator` wiring (`lib/
bootstrap/firebase_bootstrap_service.dart`) is comparatively unlikely to
reach only *one* product's callable and not others, since all four share
one code path — confirmed unaffected by this investigation (bootstrap
ordering, the single shared `FirebaseFunctions.instance` singleton every
callable gateway reads, and the emulator's own project-id handling under
`singleProjectMode` were each individually audited and ruled out; see
`test/bootstrap/functions_emulator_routing_regression_test.dart` for the
permanent regression guard against a *future* gateway silently bypassing
this shared instance via `FirebaseFunctions.instanceFor(...)`).

## Google Maps provider mode (fixture vs. live)

`GOOGLE_MAPS_PROVIDER_MODE` (env var, `functions/src/googleMapsProviderMode.ts`) decides whether
`searchAddressAutocomplete`/`resolveAddressPlace`/`reverseGeocodeAddressPoint` use deterministic,
offline fixtures or the real Google Places/Geocoding APIs. **This is deliberately independent of
whether the Functions emulator is running** (see `docs/decisions.md` Paket Servis P.3 §D13) — running
under the emulator no longer implies fixtures.

| Value | Behavior |
|---|---|
| `GOOGLE_MAPS_PROVIDER_MODE=fixture` | Deterministic, offline fixture data. Used by `functions/package.json`'s `test:emulator` script (set on the `emulators:exec` invocation itself) — automated tests opt in explicitly. |
| anything else, or unset (**default**) | Real Google Places/Geocoding APIs, requiring a valid `GOOGLE_PLACES_SERVER_KEY`. This is the default specifically so staging/production/an unconfigured physical-dev session can never *silently* fall back to fixtures. |

**To manually test the real search/map-recenter UX against the local emulator** (physical device or
otherwise), start the emulator with the mode explicit for clarity:

```sh
GOOGLE_MAPS_PROVIDER_MODE=live firebase emulators:start --project abakus-one-dev
```

This requires a real `GOOGLE_PLACES_SERVER_KEY` to be resolvable locally. Firebase's `defineSecret()`
mechanism (already used by this key in `deliveryPlaces.ts`) reads local secret overrides from a
gitignored `functions/.secret.local` file — if it doesn't exist yet, create it:

```sh
echo "GOOGLE_PLACES_SERVER_KEY=<the real server-side key>" >> functions/.secret.local
```

Never commit this file, never paste its contents anywhere logged, and never put this key into Flutter
`--dart-define` or any client-side code — it must remain server-side only, exactly as
`GOOGLE_PLACES_SERVER_KEY` already is. The key's Google Cloud Console API restrictions must permit both
"Places API (New)" and "Geocoding API". If live mode is selected but the key is missing/unreadable, the
callable fails closed with a clear `failed-precondition` error — it never silently serves fixture data
in place of a real answer.

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

No secret, API key, or credential *value* appears in this file or in `firebase.json`'s emulator
configuration — the emulators need none to run. The "Google Maps provider mode" section above documents
the *mechanism* for supplying `GOOGLE_PLACES_SERVER_KEY` locally (`functions/.secret.local`, gitignored)
for live-mode testing only — never its actual value.
