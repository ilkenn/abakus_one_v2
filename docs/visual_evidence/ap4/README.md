# AP-4 Visual Acceptance Evidence

**Status: NOT CAPTURED — 0 of 14 required screenshots.** This is an honest scaffold, not a claim of
progress on the visual-evidence requirement itself. The routed screens these items require ARE real
and reachable (see the wiring evidence in `docs/decisions.md`'s AP-4 Wave D entry and the passing
test suites referenced there) — what's missing here is only the capture step.

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

| # | Item | Real screen / route | Suggested fixture |
|---|------|----------------------|--------------------|
| 1 | Canonical POS remaining amount | `PosCheckoutScreen` — `_SummaryPanel` | An open check with one partial cash tender recorded, remaining > 0 |
| 2 | Item/sub-account payment | `PosCheckoutScreen` — `_TenderPanel`, sub-account allocation picker | A check split across ≥2 sub-accounts, one sub-account's own remaining shown |
| 3 | Mixed payment | `PosCheckoutScreen` — attempts list | A check with both a cash and a card/meal-card attempt recorded |
| 4 | Successful cash payment | `PosCheckoutScreen` — completed state | A cash tender for the full remaining amount, session status `completed` |
| 5 | Card/meal-card provider state | `PosCheckoutScreen` — `_TenderPanel` (sandbox adapter only) | Development/sandbox card adapter selected — must show a visible "sandbox" label, never selectable in a release build |
| 6 | Boncuk payment | `PosCheckoutScreen` — `_TenderPanel` Boncuk field | A tender using `requestedBoncukAmount` > 0 |
| 7 | Partial refund | `PosCheckoutScreen` — `_RefundDialog` / refunds list | A `partial` refund request, showing its approval status |
| 8 | Cash opening | `PosCashRegisterScreen` — open-session dialog | A drawer being opened with a real opening float amount |
| 9 | Cash movement remote approval | `ApprovalInboxScreen` | A pending `cashMovement` approval request, real requester/amount |
| 10 | Cash difference approval | `PosCashRegisterScreen` — count/reconciliation panel | A `short`/`over` count awaiting manager reconciliation |
| 11 | Fiscal outcome-unknown / reconciliation | `AdminFinancialOperationsScreen` — Fiskal Günlük tab, "sadece çözülmemiş" on | A `timedOut` fiscal journal entry in the unresolved queue |
| 12 | Offline queued operation | (not yet reachable — see `docs/decisions.md`'s AP-4 Wave D entry: the checkout screen's offline-capture path is not wired yet, only the sync/replay engine is) | — |
| 13 | Successful reconnection reconciliation | (same blocker as #12) | — |
| 14 | Admin cash/payment/fiscal view | `AdminFinancialOperationsScreen` — any tab | The real branch-wide list, populated with ≥1 row per tab |

Items 12–13 have an additional, disclosed blocker beyond capture: the routed UI path that would
produce the state to photograph doesn't exist yet (see the honest gap noted in this same wave's
`docs/decisions.md` entry). Items 1–11 and 14 are capturable today against a seeded local emulator.

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
