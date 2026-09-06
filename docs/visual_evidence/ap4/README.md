# AP-4 Visual Acceptance Evidence

**Status (2026-09-06, AP-4 Wave F): 4 of 14 required screenshots genuinely captured** (items #7, #8,
#11, #14 below) — real running app, real local `abakus-one-dev` Firebase emulators, real seeded data
(via `functions/scripts/seed_local_admin.js` + the new `seed_visual_evidence_financial.mjs`), captured
via Playwright against the normally-served Flutter Web app. Each screenshot's exact route/state-source/
capture-method is recorded in the matrix below. 10 items remain open — see each row for its specific
status and, where relevant, its capture caveat.

## Why this wasn't captured automatically this pass

This project's standing rule (recorded in this assistant's own persistent memory, distinct from and
not superseded by anything in the AP-4 Wave D governing instruction) is: **no automated desktop/
screen capture — the human performs all visual QA, screens are left at "Visual Review Bekleniyor."**

AP-3's own evidence pass (`docs/visual_evidence/ap3/README.md`) was different: that pass's governing
instruction *explicitly* authorized automated screenshot capture for that specific task, and even
then only reached 2 of 14 items before a real safety incident (simulated input landing on the user's
own foreground window) caused the automated approach to be abandoned mid-pass. The AP-4 Wave D
instruction asks for evidence to be captured, but does not contain the equivalent explicit override
authorizing automated capture — so the standing rule governs here, and no automation was attempted.

**AP-4 Wave E/F correction (append-only):** the Wave E and Wave F governing instructions both
explicitly authorized safe, application-scoped automation (Playwright restricted to local Abaküs
URLs, Chrome DevTools Protocol via `connectOverCDP`, `flutter drive`, `adb` against an explicitly
connected authorized device) — a bounded, in-context override for this specific task, not a repeal of
the standing preference generally. Wave E attempted capture via `flutter drive` and hit a diagnosed
environment blocker before reaching any real UI state (see ADR-047's Wave E entry). Wave F's own
re-diagnosis and any resulting captures are recorded below this point, still append-only against the
original scaffold above.

**This is a genuine gap, not a formality.** Until a human captures these 14 screenshots from the
real running app (against the local Firebase emulators, per every other AP-4 test in this codebase),
`REAL_VISUAL_ACCEPTANCE_EVIDENCE_COUNT` in any AP-4 closure report must read `0/14`, not a number
implying partial or full completion.

## Required evidence matrix

Screenshots against `PosCheckoutScreen`/`PosCashRegisterScreen` (items #1-6, #9-10) require a real
trusted-device session. On Web, the only way to obtain one for capture purposes is the same
fixture-injected `platform: "android"` technique documented in `docs/decisions.md`'s "Web POS evidence
classification" entry — a real device session is genuinely issued and the screen genuinely renders real
data, but this does **not** demonstrate Web operational POS support (which remains correctly
fail-closed for any real Web client — see that same entry). Each such screenshot's caption below states
this explicitly. Items #7, #8, #11, #14 needed no such session (financial *records*, viewed through the
Admin console, not a live device-bound tender flow) and are unambiguous.

| # | Item | Real screen / route | Status |
|---|------|----------------------|--------|
| 1 | Canonical POS remaining amount | `PosCheckoutScreen` — `_SummaryPanel` | Visual Review Bekleniyor |
| 2 | Item/sub-account payment | `PosCheckoutScreen` — `_TenderPanel`, sub-account allocation picker | Visual Review Bekleniyor |
| 3 | Mixed payment | `PosCheckoutScreen` — attempts list | Visual Review Bekleniyor |
| 4 | Successful cash payment | `PosCheckoutScreen` — completed state | Visual Review Bekleniyor |
| 5 | Card/meal-card provider state | `PosCheckoutScreen` — `_TenderPanel` (sandbox adapter only) | Visual Review Bekleniyor |
| 6 | Boncuk payment | `PosCheckoutScreen` — `_TenderPanel` Boncuk field | Visual Review Bekleniyor |
| 7 | Partial refund | `AdminFinancialOperationsScreen` — İadeler tab | **Captured: `07_partial_refund_pending.png`.** Two real `partial` refund requests, both `Onay Bekliyor` (pendingApproval), real check ids/amounts/timestamps. Web, Admin console, `yonetici@abakus.test`, no device session needed. |
| 8 | Cash opening | `AdminFinancialOperationsScreen` — Kasa Oturumları tab | **Captured: `08_cash_opening.png`.** Four real active cash-drawer sessions with real opening amounts (TRY 500-620). Web, Admin console, no device session needed. |
| 9 | Cash movement remote approval | `ApprovalInboxScreen` | Visual Review Bekleniyor |
| 10 | Cash difference approval | `PosCashRegisterScreen` — count/reconciliation panel | Visual Review Bekleniyor |
| 11 | Fiscal outcome-unknown / reconciliation | `AdminFinancialOperationsScreen` — Fiskal Günlük tab, "Sadece çözülmemiş" | **Captured: `11_fiscal_timeout_unresolved.png`.** A real `timedOut`/"Zaman Aşımı — Sonuç Bilinmiyor" fiscal journal entry (via the test-only deterministic adapter's `FORCE_TIMEOUT` marker — never reachable outside `FUNCTIONS_EMULATOR`), unresolved-only filter visibly on. Web, Admin console, no device session needed. |
| 12 | Offline queued operation | `PosCheckoutScreen` — offline tender path, queued-entries list | Not capturable in this environment — see below |
| 13 | Successful reconnection reconciliation | `PosCheckoutScreen` — post-`_syncOfflineQueue()` state | Not capturable in this environment — see below |
| 14 | Admin cash/payment/fiscal view | `AdminFinancialOperationsScreen` — any tab | **Captured: `14_admin_financial_odemeler.png`** (Ödemeler tab, 2 real completed check payments) **+ `14b_offline_lease_active.png`** (Offline Yetkiler tab, 1 real active lease). All 5 tabs of this screen were verified populated with real rows during this same capture session. Web, Admin console, no device session needed. |

**Corrected 2026-09-06 (AP-4 Wave F)**: items #12-13's blocker is narrower than a prior pass claimed —
not a missing UI path (`pos_checkout_screen.dart` genuinely wires `connectivity_plus`-detected offline
state to `_submitOfflineCashTender`/`CaptureOfflineCashPayment` and shows queued entries, confirmed by
direct inspection), but the lack of an injectable seam to force "offline" state against the real
`connectivity_plus` plugin in this environment (forcing it would mean severing this environment's own
network) — see `docs/decisions.md`'s "Offline capture, restart, reconnection, reconciliation" entry for
the full trace. Items #1-6, #9-10 remain open pending either a native Android device (preferred, avoids
the fixture-injection caveat entirely) or a further capture pass using the same fixture-session
technique already used for the E2E flows.

**Supporting capture, not one of the 14 required items**: `web_pos_fail_closed_gate.png` — navigating
the real Admin app's own "POS" destination on Web, through completely normal in-app navigation (no
fixture, no injected session), renders a real "Bu Platform Desteklenmiyor" gate:
*"Güvenilir cihaz oturumu yalnızca Android, iOS, Windows ve macOS üzerinde kullanılabilir. Web üzerinde
operasyonel POS oturumu açılamaz."* This is direct visual confirmation that **there is no real,
app-navigated path to `PosCheckoutScreen` on Web at all** — captured specifically because it clarifies
why items #1-6/#9-10 are intentionally left uncaptured rather than reproduced via the same
fixture-injection technique the E2E tests use: a screenshot of that bypass would be far more easily
misread out of context ("POS renders on Web") than a test result already carrying its own caveat, and
Section 2 of this wave's governing instruction was specifically about avoiding exactly that kind of
evidence. See `docs/decisions.md`'s "Visual evidence capture, 4/14" entry for the full reasoning.

## How to capture (for whoever performs this step)

1. `firebase emulators:start --only firestore,functions,auth,storage` (with `JAVA_HOME` pointed at a
   JDK 21+ install and `FUNCTIONS_DISCOVERY_TIMEOUT=60000` exported — see `docs/decisions.md` for
   why both are required in this environment).
2. Run the app against the emulator (`--dart-define` emulator flags, matching this repo's existing
   emulator-mode bootstrap).
3. Seed a real tenant/branch/staff/trusted-device/check through the normal flows (or the existing
   `functions/scripts/seed_dev_*.mjs` scripts where applicable), then drive each scenario above.
4. Save each screenshot as `NN_short_description.png` in this folder, replace the matching matrix
   row's "Visual Review Bekleniyor" status with the real filename, and confirm no real customer PII,
   phone number, card PAN, or token is visible in the frame before committing.

Until that happens, every row above remains **Visual Review Bekleniyor**.
