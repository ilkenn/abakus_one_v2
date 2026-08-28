# Local Admin/Staff Login Runbook (AP-3 closure tooling)

**Every command below was actually executed in this environment while writing this document.**
Emulator startup and seeding are fully verified working. **A full, successful staff sign-in through
the running app was NOT achieved on either platform available in this environment** — see
"Known blockers" below before assuming this runbook gets you all the way to a working session.

## 1. Start the emulators

From the repository root, in Git Bash (or an equivalent POSIX shell):

```bash
export PATH="/c/Users/<you>/Desktop/jdk-21.0.12+8/bin:$PATH"   # any JDK 21+; firebase-tools rejects JDK <21
export GOOGLE_MAPS_PROVIDER_MODE=fixture
firebase emulators:start --only firestore,functions,auth,storage --project abakus-one-dev
```

**`--project abakus-one-dev` is required**, not optional. `.firebaserc`'s default project
(`demo-abakus-one-emulator`) is what the backend Node test suite uses for its own purposes — the
real Flutter app initializes with `abakus-one-dev` (`lib/core/config/app_environment_config.dart`'s
`development.firebaseProjectId`), and `firebase.json`'s `singleProjectMode: true` means the emulator
only serves ONE project id. Starting without `--project abakus-one-dev` leaves the emulator bound to
the wrong project and every real app request 404s.

Wait for `functions: Loaded environment variables from .env.local.` and no more `!` warnings before
continuing.

## 2. Seed deterministic local data

From `functions/`, with the emulators from step 1 still running:

```bash
cd functions
node scripts/seed_local_admin.js
```

Verified output (2026-08-28, this session):

```
Seeding tenant...
Creating staff accounts (email/password)...
Bootstrapping manager as first org admin (idempotent across reruns)...
Granting cashier the staff role + branch access...
Seeding tables...
Seeding three guests with sub-accounts...
Seeding orders (pending / accepted / rejected / proposedChange lines)...
Opening a check and splitting the staff-entered line by product...
Seeding a pending remote approval (financial-adjustment request)...
Seeding tenant + platform customer directory entries...
Creating a Platform Owner account...

DONE. Local login instructions:

  Staff/Admin sign-in  (route /admin -> "Giriş Yap"):
    E-posta : kasiyer@abakus.test
    Şifre   : GorselKabul2026!
  Manager (approvals, branch management):
    E-posta : yonetici@abakus.test
    Şifre   : GorselKabul2026!
  Platform Owner sign-in  (route /platform):
    E-posta : sahip@abakus.test
    Şifre   : GorselKabul2026!

  Organization: org-ap3vis   Branch: branch-ap3vis
  Occupied table (live demo data): table-ap3vis-2
  Available table: table-ap3vis-1
```

The script refuses to run at all unless `FIRESTORE_EMULATOR_HOST`/`FIREBASE_AUTH_EMULATOR_HOST` both
resolve to `127.0.0.1:*`/`localhost:*` — see its own `refuseUnlessEmulator()` — so it structurally
cannot touch a real project. Safe to rerun (idempotent).

## 3. Launch the app

```bash
flutter run -d windows          # native Windows desktop
# or
flutter run -d web-server --web-port=8765 --web-hostname=127.0.0.1   # then open a browser at that URL yourself
```

Navigate to Profile → "İşletme Modu" (or directly to the `/admin` route) to reach the staff sign-in
gate, then enter the cashier credential from step 2.

## Known blockers — read before relying on this runbook for a working session

**Windows: staff sign-in cannot complete at all — this is a real, upstream, structural limitation,
not a bug in this app.** `cloud_functions` package version 6.3.6's own `pubspec.yaml` declares
platform support for `android`/`ios`/`macos`/`web` only — **Windows is not a supported platform for
Cloud Functions in this plugin version**, confirmed independently via
`windows/flutter/generated_plugin_registrant.cc`, which genuinely does not register a Windows
implementation for `cloud_functions` (nor `firebase_crashlytics`/`firebase_messaging` — only
`firebase_app_check`/`firebase_auth`/`firebase_core`/`firebase_remote_config`/`firebase_storage` are
registered for Windows). Since staff sign-in requires the `syncOwnStaffClaims` Cloud Functions
callable, it cannot succeed on Windows regardless of any app-level code change. Reproduced via
`integration_test/staff_sign_in_e2e_test.dart -d windows`, which fails fast (in ~2s, not a hang —
this session's own timeout fix, described below, is what makes it fail fast instead of hanging) with:
`[firebase_functions/unknown] Unable to establish connection on channel:
"dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call"`.

**Web: staff sign-in still hangs indefinitely, for a deeper reason than the bug this pass fixed.**
Web IS a declared-supported `cloud_functions` platform, so this is not the same class of problem as
Windows. This session found and fixed a real bug (`FirebaseStaffAuthRepository` had no bounded
timeout anywhere and `StaffSignInScreen._signIn` had no `try`/`catch`, so ANY failure hung the UI
forever with no error) — but even with that fix in place (a 20-second `.timeout()` on every
network-dependent step), a real sign-in attempt against the local emulator via a release Web build
still shows the loading spinner indefinitely, past 40+ real seconds, with the "zaman aşımı" error
text never appearing. Diagnostic investigation this session found that even an unrelated, purely
local `setState` (tapping the "İlk yönetici hesabını oluştur" link, which does nothing but flip a
boolean) also stopped responding during the same hang — meaning the underlying issue with the actual
credentials-and-claims request is not a plain unresolved Dart `Future.timeout()` was able to observe;
it looks like the whole rendering isolate stalls before that Timer runs. The exact upstream cause was
not identified within this session's time budget. This is a real, open, disclosed technical gap —
not something this runbook or the current code can talk you past. If Android/iOS device or emulator
access becomes available, sign-in should be re-attempted there next — `cloud_functions` genuinely
supports both, and neither of the two structural blockers above applies.

**Net effect**: seeding is fully reproducible and verified end-to-end; a real, complete staff sign-in
through the actual running app is not achievable in this environment as of this writing.
