# AP-3 Visual Acceptance Evidence

**Status: INCOMPLETE — 2 of 14 required screenshots captured.** This is an honest record of a
genuine, good-faith attempt at automated visual-evidence capture for the AP-3 POS/trusted-device
closure pass, not a claim of success. Read this document in full before trusting the evidence
matrix below — several required screenshots were not achievable within this pass, for disclosed,
investigated reasons (not simply "not attempted").

## Authorization context

The governing instruction for this pass explicitly authorized non-destructive, application-scoped
automated screenshot capture (Playwright web automation, isolated native-app window capture),
superseding an earlier standing project rule against automated visual QA for this specific task.
That authorization was accepted and acted on. What follows is what was actually achieved under it —
including a safety-driven decision to stop one capture method mid-attempt, described below.

## What was captured

| # | Filename | Route/Surface | Viewport | Fixture/Scenario | State proven | Method | Commit |
|---|----------|----------------|----------|-------------------|---------------|--------|--------|
| 1 | `01_admin_route_unauthorized_gate.png` | `/admin` (`AppRouteGuard`) | 1440×900 (headless Chrome) | No active staff session (fresh browser context, no auth) | The real `/admin` route guard's unauthorized state — "Bu alana erişmek için personel/yönetici girişi yapmalısınız." + "Giriş Yap" button, plus the real "Running in emulator mode" banner confirming a genuine Firebase Auth Emulator connection, not a mock | Playwright, release web build (`flutter build web --release`) served locally, pointed at local Firebase emulators (`abakus-one-dev` project id) | (working tree, pre-commit) |
| 2 | `02_staff_admin_sign_in_form.png` | `/admin` → `StaffSignInScreen` | 1440×900 (headless Chrome) | Same as above, after tapping "Giriş Yap" | The real email/password staff sign-in form — "Yönetici / Personel Girişi", E-posta/Şifre fields, "Giriş Yap" button, "İlk yönetici hesabını oluştur" link | Playwright, debug web build (`flutter run -d web-server`) | (working tree, pre-commit) |

Both images were opened and visually inspected (not merely confirmed to exist), and their PNG
headers were read directly to confirm non-zero valid dimensions (both 1440×900, ~19–23KB). Neither
contains any real customer data, phone number, address, credential, private key, token, or secret —
both show only static UI chrome with placeholder/empty form fields.

## What was NOT captured, and why

**Items 1–9 (trusted-device registration/activation, and the full POS three-pane workspace —
branch/table overview, sub-accounts, staff entry, all five split modes, transfer/merge, financial
adjustment, remote-approval banner) — NOT CAPTURED.**

These require a real trusted-device session, which is architecturally impossible on Web by design
(`devicePlatformSupportedProvider` returns `false` for `web` — this is the correct, tested,
intentional "Web POS remains fail-closed" behavior this same AP-3 wave implemented, not a gap).
Capturing them requires a real Android/iOS/Windows/macOS platform.

- **Android/iOS emulator**: not available in this environment — no `adb`, no `emulator`, no
  `ANDROID_HOME`, confirmed via `flutter devices` (only Windows desktop and two web browsers listed).
- **Windows desktop native app** (`flutter build windows --debug` → real, trusted-device-capable
  `.exe`, built successfully): attempted, then **deliberately abandoned for safety reasons before
  any evidence was captured from it.** `SetForegroundWindow`, called from this non-interactive
  automation process, was silently failing to actually focus the target app window — verified
  directly (`GetForegroundWindow()` after several simulated clicks still returned the user's own
  unrelated Chrome/ChatGPT window, not the Abaküs app). This means every simulated mouse click sent
  during that attempt landed on the user's own foreground Chrome window, not the target application
  — a small number of clicks in a browser sidebar area, no keyboard input ever sent, nothing typed
  or submitted, but a real, confirmed instance of automation missing its intended target and
  reaching unrelated user content. On confirming this, all further simulated input was stopped
  immediately, the misdirected screenshot from the same failure mode was deleted without being
  analyzed further, and the Windows app process was terminated. This is disclosed here in full
  rather than silently omitted, per the same transparency this project's standing automation policy
  was built on. No safe, reliable way to guarantee input isolation to a single target window was
  found in the time available — a real UI Automation (accessibility) tree was checked and found
  unavailable for this Flutter Windows build's current window state, which would have been the
  robust alternative to coordinate-based input injection.

**Items 10–11 (customer QR pending-approval / counter-proposal) — NOT ATTEMPTED.** Reaching these
screens requires either a literal camera-based QR scan (Flutter's `mobile_scanner`) — no manual/
debug token-entry fallback exists in `qr_scanner_screen.dart` — or reconstructing a synthetic camera
feed for Chromium (`--use-fake-device-for-media-stream` + a generated QR image), both of which were
judged too large an undertaking to attempt safely within the remaining time after the items-1–9 and
items-12–13 attempts above. Not claimed as captured; not silently skipped either.

**Items 12–13 (Admin Customer Directory, Platform Customer Directory) — NOT CAPTURED**, despite a
genuine, extended, multi-hour attempt. Both require a completed staff sign-in first. That sign-in
consistently hung indefinitely (confirmed via zero outstanding/finished network requests during an
8-second observation window, and via total UI unresponsiveness — even an unrelated, purely local
`setState` triggered by a different button never fired) in **both** a debug web build (`flutter run
-d web-server`) and a from-scratch release web build (`flutter build web --release`), served two
different ways (Dart's own DWDS dev server; a plain static Node file server for the release build).

One real, reproducible bug was found and fixed in the process (see below) — but the fix did not
resolve the hang, meaning a second, separate, and not-fully-diagnosed issue remains. Root-caused as
far as time allowed: a stray helper script accidentally left inside `functions/` mid-session
triggered a Functions-emulator hot-reload failure (`Failed to load function` /
`us-central1-listStaffMembersForOrganization`), which was found and fixed (the files were moved out
of the watched directory) — but the sign-in hang persisted even after the emulator recovered and
resumed serving other callables successfully, so this was a contributing factor investigated and
ruled out as the sole cause, not the final answer. The genuinely remaining cause was not found within
the time available for this pass.

**Item 14 (Web operational POS fail-closed screen) — NOT CAPTURED as specified.** The evidence
captured (screenshot #1 above) shows the `/admin` route's own unauthorized gate, which is a real,
correct fail-closed-adjacent state, but not the specific screen the requirement names: the trusted-
device `TrustedDeviceStatusScreen`'s "Desteklenmeyen Platform" (unsupported platform) state, which
only renders **after** a successful staff sign-in — blocked by the same sign-in hang above.

## A real bug found and fixed during this pass

`lib/features/admin/data/staff_auth_repository.dart`'s `FirebaseStaffAuthRepository.signIn()` and
`.refreshSession()` called `_staffMemberRepository.findByAuthUid()` / `.findById()` with no
`try`/`catch`, despite the class's own documented intent immediately above each call: "a
missing/unavailable member never denies what the real claims would otherwise grant." Firestore
directory lookups against a cold-started local emulator this pass exercised gave that documented
gap a genuine trigger (`StaffDirectoryException(deadline-exceeded)`) — the resulting uncaught
exception aborted `signIn()`/`refreshSession()` before the caller's `setState(() => _busy = false)`
line, leaving the sign-in button permanently disabled with an infinite loading spinner. Fixed by
wrapping both calls in `try`/`catch`, falling back to `null` on any failure — matching the
already-documented, already-intended behavior exactly. Two new regression tests added
(`firebase_staff_auth_repository_test.dart`, now 15/15 passing) using a `_ThrowingStaffMemberRepository`
fake that unconditionally throws from every method, proving neither `signIn` nor `refreshSession`
denies or hangs when the staff directory is unavailable.

This is a real production robustness fix — a slow/unavailable staff directory (a plausible real
Firestore condition, not just an emulator artifact) would previously have made staff sign-in hang
indefinitely for any real user, not just in this test environment.

## Honest conclusion

AP-3's POS/trusted-device implementation itself is real, tested, and gate-verified (see this
session's own closure report and `docs/decisions.md` ADR-041). Real visual acceptance evidence for
it, specifically, is not — two screens were captured (a route guard and a sign-in form, both real,
both correctly rendered, neither the POS workspace itself), a real bug was found and fixed along the
way, and the remaining 12 required screenshots were not achieved despite genuine, disclosed,
multi-method attempts, one of which was correctly aborted mid-attempt on discovering a real safety
issue rather than pushed through.

---

## CORRECTION (append-only) — the closing tag block above was internally inconsistent

The closure report accompanying this pass's commits stated `FULL_QUALITY_GATES_PASSED=YES` in the
same tag block as `HIGH_ISSUES_OPEN=1` (the unresolved staff sign-in hang) and
`REAL_VISUAL_ACCEPTANCE_EVIDENCE_CREATED=PARTIAL` (2/14). Those three facts are mutually exclusive —
a gate suite cannot honestly be reported as fully passed while a high-severity functional defect is
still open and the visual-acceptance requirement is only 2/14 complete. This was a real reporting
error, not a new development — nothing about the underlying engineering state changed; the tag block
itself was simply wrong. The corrected state, effective from this point forward until superseded by a
later, equally explicit correction:

```text
AP3_COMPLETE=NO
FULL_QUALITY_GATES_PASSED=NO
HIGH_ISSUES_OPEN=1
REAL_VISUAL_ACCEPTANCE_EVIDENCE_CREATED=PARTIAL
```

This correction does not retroactively change what was captured, fixed, or tested in the pass above —
it corrects only how that pass's outcome was summarized.

---

## RECOVERY PASS (2026-08-28) — the sign-in hang, root-caused; visual evidence, still not 14/14

A follow-up instruction asked for the sign-in hang to be root-caused and fixed (not just tolerated),
for a reproducible local seed/login runbook, and for a safe (non-OS-input) capture harness. All of
that was attempted honestly; full detail below.

### The bug that was actually there, and its fix

Tracing the real call chain (`StaffSignInScreen._signIn` → `StaffSessionController.signIn` →
`FirebaseStaffAuthRepository.signIn` → `EmailPasswordAuthClient`/`StaffClaimsSyncClient`) found two
real, compounding defects:
1. **No timeout anywhere.** Every network-dependent `await` in `FirebaseStaffAuthRepository` —
   Firebase Auth sign-in, the `syncOwnStaffClaims` callable, the ID-token force-refresh — had no
   bound. A stalled underlying call hung forever.
2. **`StaffSignInScreen._signIn` had no `try`/`catch`** around its one call into the repository,
   unlike its own sibling method in the same file (`_bootstrapFirstAdmin`, which already used
   `try`/`catch`/`finally`). Any exception — including a legitimate one — escaped before
   `setState(() => _busy = false)` could run, leaving the spinner stuck permanently.

Fixed: every network step in `FirebaseStaffAuthRepository` now has an injectable, bounded timeout
(`staffAuthNetworkTimeout`, default 20s) that surfaces as a typed `StaffAuthUnavailableException`;
`StaffSignInScreen._signIn` now has a full `try`/`catch`/`finally` mirroring its sibling, always
clears `_busy`, and shows a distinct, retry-worded message for a timeout vs. an invalid credential vs.
a genuinely unexpected error. 24 new tests prove this: 19 repository-level (`firebase_staff_auth_
repository_test.dart`, including two tests that simulate a network call which never settles at all
and prove it surfaces as `StaffAuthUnavailableException` in well under a second, not a hang) and 5
widget-level (`staff_sign_in_screen_test.dart`, proving the loading state always clears, the right
message is shown for each failure class, and retry genuinely starts a fresh attempt and can succeed).

### What this fix did NOT turn out to fully resolve — two deeper, independently diagnosed findings

Building a real, emulator-backed, end-to-end integration test (`integration_test/
staff_sign_in_e2e_test.dart` — runs the real `bootstrapApp()`, drives the real `StaffSignInScreen`
via `WidgetTester`, no mocks) to prove the fix works in practice, not just in unit tests, surfaced two
further, genuinely separate problems — neither is a bug in this app's own code:

- **Windows: structurally impossible, not a bug.** `cloud_functions` 6.3.6's own `pubspec.yaml`
  declares platform support for `android`/`ios`/`macos`/`web` only. Windows has no plugin
  implementation at all — confirmed independently via `windows/flutter/generated_plugin_registrant
  .cc`, which genuinely never registers a Windows handler for `cloud_functions` (nor
  `firebase_crashlytics`/`firebase_messaging`). Staff sign-in needs the `syncOwnStaffClaims`
  callable, so it cannot succeed on Windows, full stop, regardless of any Dart-level fix. Proof: the
  integration test now fails **fast** (~2s, not a hang — this session's own fix is what makes it fail
  fast instead of hanging) with `[firebase_functions/unknown] Unable to establish connection on
  channel: "...CloudFunctionsHostApi.call"`.
- **Web: a deeper, undiagnosed stall the timeout fix could not observe.** Web IS a declared-supported
  `cloud_functions` platform. Even with the 20s timeout fix built and deployed to a fresh release Web
  build, a real sign-in attempt against the local emulator still hung past 40+ real seconds with no
  error ever shown. Further probing found that an unrelated, purely local `setState` (tapping a
  different button that does nothing but flip a boolean) also stopped responding during the same
  hang — indicating the whole rendering isolate stalls, not just the one network `Future`, which is
  why even a working `.timeout()` Timer never got to fire. Root cause not identified within this
  pass's time budget; flagged here as a real, open, disclosed gap rather than worked around silently.

Given both available platforms are blocked for structurally different reasons, and Android/iOS are
not available in this environment (no `adb`/`emulator`/`ANDROID_HOME` — confirmed via `flutter
devices`), a real, complete, screenshot-verified staff sign-in could not be produced this pass either.
The integration test itself is left in the repository, real and correct, marked with an in-code
comment explaining exactly this rather than silently deleted or left failing without explanation —
see `docs/local_admin_login_runbook.md` for the full runbook and both findings, verified against this
exact environment.

### Consequence for the 14-screenshot requirement

Items 1–9 and 12–14 (everything requiring a completed staff sign-in) remain not captured, now for a
concretely diagnosed reason rather than an unexplained hang. The 2 screenshots already on file
(`01_admin_route_unauthorized_gate.png`, `02_staff_admin_sign_in_form.png`) are unaffected by this
fix (their appearance depends on rendering before any sign-in attempt) and were not recaptured.
`REAL_VISUAL_ACCEPTANCE_EVIDENCE_CREATED` remains `PARTIAL` (2/14). Items 10–11 (customer QR,
camera-dependent) and the QR non-camera deep-link entry point this pass's own instructions also asked
for were not attempted — the sign-in investigation above consumed the pass's available time, and
building a new deep-link entry point is itself a real, separate feature addition this document is not
going to claim was done when it wasn't.
