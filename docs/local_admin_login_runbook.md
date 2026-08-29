# Local Admin/Staff Login Runbook (AP-3 closure tooling)

**Every command below was actually executed in this environment while writing this document
(re-verified 2026-08-28, Wave 4).** Emulator startup, seeding, and a real, complete Web staff
sign-in through the actual running app are all verified working end-to-end. Windows remains
genuinely blocked (see "Known blockers"), which is why this runbook's "launch the app" step
targets Web.

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

Verified output (2026-08-28, Wave 4 — **`Organization` is now `org-1`, corrected from the
`org-ap3vis` an earlier wave's seed script mistakenly used**; see "The organization-id bug" below):

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

  Organization: org-1   Branch: branch-ap3vis
  Occupied table (live demo data): table-ap3vis-2
  Available table: table-ap3vis-1
```

The script refuses to run at all unless `FIRESTORE_EMULATOR_HOST`/`FIREBASE_AUTH_EMULATOR_HOST` both
resolve to `127.0.0.1:*`/`localhost:*` — see its own `refuseUnlessEmulator()` — so it structurally
cannot touch a real project. Safe to rerun (idempotent).

## 3. Build and serve the Web app

```bash
flutter build web --profile   # --profile, not --release — see "Which build mode" below
```

Serve `build/web` with any static file server that sends `Cache-Control: no-store` (a plain
`flutter build web` output has no dev server of its own). A minimal one:

```js
// static_serve.js
const http = require('http'); const fs = require('fs'); const path = require('path');
const root = process.argv[2]; const port = parseInt(process.argv[3], 10);
const mime = { '.html':'text/html', '.js':'application/javascript', '.json':'application/json',
  '.css':'text/css', '.png':'image/png', '.jpg':'image/jpeg', '.svg':'image/svg+xml',
  '.ico':'image/x-icon', '.wasm':'application/wasm', '.otf':'font/otf', '.ttf':'font/ttf' };
http.createServer((req, res) => {
  let filePath = path.join(root, decodeURIComponent(req.url.split('?')[0]));
  if (filePath.endsWith('/')) filePath = path.join(filePath, 'index.html');
  fs.readFile(filePath, (err, data) => {
    if (err) { fs.readFile(path.join(root, 'index.html'), (e2, d2) => {
      if (e2) { res.writeHead(404); res.end('not found'); return; }
      res.writeHead(200, { 'Content-Type': 'text/html' }); res.end(d2); }); return; }
    res.writeHead(200, { 'Content-Type': mime[path.extname(filePath)] || 'application/octet-stream',
      'Cache-Control': 'no-store, no-cache, must-revalidate' });
    res.end(data);
  });
}).listen(port, '127.0.0.1', () => console.log(`Static server on http://127.0.0.1:${port} serving ${root}`));
```

```bash
node static_serve.js build/web 8900
```

Then open `http://127.0.0.1:8900/#/admin` in a real browser tab (a **fresh** tab/navigation — see
the caching note below) and sign in with the cashier credential from step 2.

**Verified reaching the real Admin shell** (2026-08-28): `kasiyer@abakus.test` /
`GorselKabul2026!` → "Yönetici Paneli" heading, `org-1 · branch-ap3vis` context, real uid, working
`Çıkış Yap` (sign-out) button, real Firestore-backed Customer Directory under "Müşteri 360" (3 real
seeded customers). Same result for `yonetici@abakus.test` (manager, broader nav) and
`sahip@abakus.test` at `/platform` (Platform Owner console).

### Which build mode

Use `--profile`, not `--release`, if you want to see actual screen *content* beyond the sign-in
form. `ModuleReadinessGate` (`lib/features/admin/presentation/widgets/module_readiness_gate.dart`)
hard-blocks every destination that isn't yet `ModuleDeploymentAvailability.production` — which is
every destination in the app today, by design (`CLAUDE.md` §5: nothing has ever been deployed to a
real Firebase project) — behind a "Bu modül henüz production kullanımına açılmadı." placeholder,
but **only when `kReleaseMode` is true**. A `--profile` (or `--debug`) build renders the real screen
with a small "DEMO" badge overlay instead — the honest, intentional disclosure marker, not a bug.
`--release` is still the right build for testing the sign-in flow itself (and for the Web POS
fail-closed screen, which isn't readiness-gated).

### A browser-caching trap when iterating

If you rebuild and re-serve on the **same port** after a code change, a plain browser reload can
serve a stale cached `main.dart.js` even after a full page reload — Chromium does not always treat
"navigate to the same URL again" as cache-busting, especially for a hash-only route change (e.g.
`#/admin` → `#/table/xyz` on an already-loaded page is a same-document SPA navigation, not a fresh
load at all, and won't pick up new code even where you'd expect a genuine reload). Confirmed via
byte-for-byte comparison between the file on disk and the file actually served — they matched, but
the browser was still executing old cached JS. Robust fix: serve on a **new port** after every
rebuild (a different origin has no cache to be stale), or add `Cache-Control: no-store` (included
in the server above) and open a **brand-new tab** rather than reusing/reloading an existing one —
`browser_tabs`/`new tab` in Playwright, or a plain new browser tab for manual testing.

## 4. Automated E2E test (optional, real)

`integration_test/staff_sign_in_e2e_test.dart` drives the real `StaffSignInScreen` end-to-end
(sign in → Admin shell → open Customers → sign out) via `WidgetTester`, against the real running
emulators — no mocks. On Web this needs `flutter drive`, which needs a local WebDriver server:

```bash
npx --yes chromedriver --port=4444 &        # any chromedriver matching your installed Chrome works
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/staff_sign_in_e2e_test.dart \
  -d web-server --browser-name=chrome
```

## PowerShell version (Windows-computer operator, single copyable sequence)

Everything above works identically from Windows PowerShell (5.1). The one difference: PowerShell
uses `$env:NAME = 'value'` instead of `export NAME=value`, and `Start-Process`/background jobs
instead of `&`. Run each block from the repository root (`C:\Projects\abakus_one_v2`).

```powershell
# 1. Start the emulators (separate window/job — this blocks until stopped)
$env:PATH = "C:\path\to\jdk-21\bin;$env:PATH"        # any JDK 21+
$env:GOOGLE_MAPS_PROVIDER_MODE = "fixture"
firebase emulators:start --only firestore,functions,auth,storage --project abakus-one-dev
```

```powershell
# 2. In a second window, once step 1 shows no more "!" warnings — seed deterministic data
Set-Location functions
$env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
$env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099"
$env:GCLOUD_PROJECT = "abakus-one-dev"
node scripts/seed_local_admin.js
Set-Location ..
```

```powershell
# 3. Build and serve the Web app (--profile, not --release — see "Which build mode" above)
flutter build web --profile
node "<path-to-static_serve.js-from-this-doc>" build\web 8900
```

Open a **fresh** browser tab at `http://127.0.0.1:8900/#/admin` and sign in with
`kasiyer@abakus.test` / `GorselKabul2026!` (or `yonetici@abakus.test` for the manager view, or
`http://127.0.0.1:8900/#/platform` with `sahip@abakus.test` for the Platform Owner console — same
password for all three). Verified reaching the real Admin shell, exactly as documented above.

```powershell
# 4. Stop everything (Ctrl+C in each window, or):
Get-Process node, firebase, chrome -ErrorAction SilentlyContinue | Where-Object {
  $_.MainWindowTitle -match "abakus|emulator|firebase" -or $_.Path -match "abakus_one_v2"
} | Stop-Process -Force -ErrorAction SilentlyContinue
```

**Note on step 4**: the filter above is deliberately conservative (matches by path/window title, not
a blanket `Stop-Process -Name node`) — this machine may be running unrelated Node/Chrome processes
you do not want to kill. Prefer `Ctrl+C` in each foreground window when possible; use the filtered
command only for a background/job-based setup.

## Known blockers

**Windows: staff sign-in cannot complete at all — a real, narrow, upstream platform-support gap, not
a bug in this app, and not something to describe as categorically "impossible."**
`cloud_functions` package version 6.3.6's own `pubspec.yaml` declares platform support for
`android`/`ios`/`macos`/`web` only — confirmed independently via
`windows/flutter/generated_plugin_registrant.cc`, which genuinely does not register a Windows
implementation for `cloud_functions`. Staff sign-in needs the `syncOwnStaffClaims` callable, so it
cannot succeed on Windows with this plugin version. A Windows-native REST/HTTP adapter for
`https.onCall` is architecturally possible (the protocol is documented) but is deliberately not the
chosen path for this closure — Web is the sanctioned Windows-computer path. Reproduced via
`integration_test/staff_sign_in_e2e_test.dart -d windows`, which fails fast (~2s) with:
`[firebase_functions/unknown] Unable to establish connection on channel:
"dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call"`.

## The organization-id bug (found and fixed, Wave 4)

An earlier wave's `seed_local_admin.js` seeded its fixture tenant under a self-invented
`org-${RUN_ID}` (`org-ap3vis`) instead of the app's actual hardcoded single-tenant organization id,
`kSingleTenantOrganizationId = 'org-1'` (`lib/core/config/current_organization.dart` — the same
constant the real backend, `functions/src/completeCustomerProfile.ts`'s
`SINGLE_TENANT_ORGANIZATION_ID`, uses). `FirebaseStaffAuthRepository._organizationId()` always
resolves to `'org-1'`, so `claims.rolesFor('org-1')` was always empty despite a fully successful
sign-in + claims sync — `ActorSession.tryFromRaw` correctly failed closed, surfacing as "Giriş
başarısız. Bilgilerinizi kontrol edin." **This was misdiagnosed in earlier waves as a Web-specific
rendering isolate stall** (a separate, unrelated Playwright interaction-timing artifact — a
too-fast click+type sequence that silently failed to land in a form field — produced a superficially
similar symptom during that investigation). Fixed by seeding under `'org-1'`; verified end-to-end
per step 3 above.

**Net effect**: seeding and a real, complete Web staff sign-in are both fully reproducible and
verified end-to-end as of this writing. Windows remains blocked for the documented, narrow platform
reason above.
