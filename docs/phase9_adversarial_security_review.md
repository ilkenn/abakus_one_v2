# Phase 9 — Mandatory Adversarial Security Review

Status: **COMPLETE**. Performed at the close of Phase 9 (Sprints 9A–9J), per the
explicit kickoff instruction to run a mandatory adversarial security review before
any phase-gate verdict. Every finding below is graded against direct evidence — a
file read, a grep, or a test run performed in this session — not recollection.
Evidence Classification tags (Verified / Inferred / Assumed) are used throughout per
this project's standing rule.

See [phase9_final_report.md](phase9_final_report.md) for the 30-item closing report
and phase-gate verdict this review feeds into.

## How to read this document

Each named check area gets one of three classifications:

- **CLOSED** — a real gap was found and a real fix now exists, verified by a passing
  test (unit, widget, or emulator).
- **ACCEPTED LOW RISK / OUT OF SCOPE** — no gap, or a gap that pre-dates Phase 9,
  belongs to a feature Phase 9 never touched, or is explicitly deferred future work
  already documented elsewhere (not silently re-scoped as "fine" — the reasoning is
  given every time).
- **BLOCKING** — a real, currently-open gap inside Phase 9's own remit that the
  original kickoff named as disqualifying for an outright APPROVED verdict.

Per the kickoff's own rule: **no unresolved Critical, High, or Medium finding may
remain** for Phase 9 to be marked APPROVED outright. Any BLOCKING item below forces
the verdict to at best APPROVED WITH REQUIRED FIXES.

---

## 1. Firebase production selection

**CLOSED / Verified.** Every Phase-9-relevant repository/service now selects its
real implementation deterministically from build state, never from a flag a client
could spoof:

- `authRepositoryProvider` — `firebaseReadyProvider`-gated
  (`lib/features/auth/presentation/providers/auth_provider.dart`).
- `canonicalOrderRepositoryProvider` — `firebaseReadyProvider`-gated, resolves to
  `FirestoreCanonicalOrderRepository` once ready, `InMemoryCanonicalOrderRepository`
  otherwise (`lib/features/orders/presentation/providers/orders_provider.dart:42-56`).
- `staffAuthRepositoryProvider`/`platformAuthRepositoryProvider` —
  `firebaseReadyProvider`-gated (Phase 8).
- `accountDeletionRequestRepositoryProvider`/`deviceTokenRepositoryProvider` —
  `kReleaseMode`-gated (this review's own fix — see §2).

Grep evidence (`select:TodoWrite` search history this session):
`grep -rln "firebaseReadyProvider" lib/` and `grep -rln "kReleaseMode" lib/
--include="*_provider*.dart"` both return exactly the provider files above for
anything Phase 9 touches.

## 2. No release build may silently fall back to InMemory persistence

**CLOSED / Verified**, for everything inside Phase 9's remit.

Two real gaps were found and fixed this session:

- `accountDeletionRequestRepositoryProvider` had zero gating — always resolved to
  `InMemoryAccountDeletionRequestRepository`, including in release builds. Fixed:
  added `ProductionUnavailableAccountDeletionRequestRepository` (throws on `save`,
  returns empty/null on all reads), gated the provider on `kReleaseMode`.
- `deviceTokenRepositoryProvider` had the identical gap. Fixed identically with
  `ProductionUnavailableDeviceTokenRepository`.

Both mirror Phase 8's `ProductionUnavailableStaffMemberRepository` pattern exactly
(`kReleaseMode`, not `firebaseReadyProvider`, because neither repository has a
Firestore-backed implementation yet to fail over *to* — there is nothing for
`firebaseReadyProvider` to gate between). Verified: `flutter analyze` clean,
`flutter test` 2264/2264 passing after the change, committed in `981b898`.

**ACCEPTED / OUT OF SCOPE**: `grep -rl "InMemory.*Repository()" lib/ --include="*provider*.dart"`
returns ~35 additional provider files (POS, courier, CRM, inventory, feedback,
purchasing, etc.) that are still unconditionally `InMemory*` in every build mode,
release included. These all pre-date Phase 9 (Phases 3–8) and sit outside Phase 9's
named remit — "everything is client-side, in-memory mock data" has been this
project's documented baseline since before Phase 9 began, and CLAUDE.md's phase-order
rule keeps work scoped to the current phase. Re-litigating and migrating all ~35 of
them is a future, explicitly separate body of work, not a Phase 9 regression.

## 3. Tenant isolation

**CLOSED / Verified** via a freshly re-run emulator suite this session
(`firebase emulators:exec --only firestore "cd firestore-tests && npm test"`,
24/24 passing):

- `an tenant member can read their own organization` / `cross-tenant read is denied`
  — a member of org-2 cannot read org-1 data.
- `a client cannot assign themselves an organization` / `a client cannot promote
  their own role via memberships` / `a client cannot write an arbitrary entitlement
  grant` — every tenant-boundary write path fails closed.
- `an unlisted collection defaults to fully denied (fail closed)`.

## 4. Restaurant/branch resolution

**ACCEPTED LOW RISK / Verified, documented placeholder.**
`submitCustomerOrderProvider` hardcodes `branchId: 'branch-1'`,
`restaurantId: 'restaurant-1'` (`orders_provider.dart:70-71`) — but this is an
honestly-documented placeholder, not a silent gap: the doc comment directly above it
states there is no restaurant/branch *selection* UI anywhere in the customer app yet,
mirroring the same accepted pattern `currentBranchIdProvider`
(`features/navigation`) already uses. `FirestoreCanonicalOrderRepository`'s
`resolveOrganizationId` closure still does a real lookup through
`restaurantRepositoryProvider.findById(restaurantId)` rather than hardcoding the
organization id directly — the seam for a real multi-restaurant selector to plug into
already exists; only the UI to drive it is missing, and building that UI is out of
Phase 9's remit (it's an app-wide navigation/product feature, not a backend-wiring
task).

## 5. Platform/tenant separation

**CLOSED / Verified** via the same emulator run:

- `a platform member without an active support grant cannot read tenant data
  outside their own scope`
- `a platform member WITH an active, non-expired support grant can read that
  tenant's data`
- `an EXPIRED support grant no longer grants access — time-limited, not permanent`
- `a tenant role claim never grants a platform action, and vice versa — the two
  claim namespaces never cross`

All four pass. Platform-side elevated access is real, scoped, and time-limited —
not a standing backdoor.

## 6. Canonical identity

**CLOSED / Verified.** `AuthSession.uid` (`lib/features/auth/domain/models/
auth_session.dart:10`) is the one backend-issued immutable identity. Traced its real
use, not just its existence:

- `checkout_screen.dart:233`: `final customerId = session.isAuthenticated ?
  session.session?.uid : null;` — the real screen, not a hypothetical.
- `AccountDataNotifier.requestAccountDeletion`/`cancelAccountDeletion` both read
  `session.uid` from the live `authProvider`, not a passed-in or guessable value —
  this is also what closed the IDOR finding in §10.
- `AuthNotifier._isBlockedByDeletionRequest(uid)` checks against this same uid.

## 7. Canonical Order aggregate — sole authoritative model

**BLOCKING.** This is the one finding in this review serious enough to block an
outright APPROVED verdict, found during this review by tracing what the customer's
own Orders screen actually reads from, not what it was designed to read from.

**Evidence:**
- `SubmitCustomerOrder`/`SubmitPosOrder` write real orders into
  `canonicalOrderRepositoryProvider` (`Order` aggregate, Firestore-backed once
  `firebaseReadyProvider` is true) — this part is real and correctly wired.
- But `OrdersNotifier` (`orders_provider.dart:75-241`) — which backs
  `ordersProvider`/`activeOrderProvider`, and in turn `orders_screen.dart`,
  `order_detail_screen.dart`, and the Home "Aktif Siparişin" card — reads its
  *entire* state from `ordersRepositoryProvider`, which unconditionally resolves to
  `LocalOrdersRepository` (`orders_provider.dart:22-24`): in-memory, seeded mock
  data, no Firestore gating at all.
- `checkout_screen.dart:248-250` bridges this at submission time only: after calling
  `submitCustomerOrderProvider` (canonical), it manually calls
  `ordersProvider.notifier.addOrder(OrderModel.fromCanonicalOrder(order))` to also
  push a converted copy into the legacy store — so a customer's own just-placed
  order does appear in their Orders list, in the *same app session*.
- What this bridge does **not** do: read back. Once the Cloud Function
  (`onOrderCreated`, Sprint 9F) transitions the order server-side, or any future
  kitchen/courier action changes canonical status, nothing propagates that change
  back into `OrdersNotifier`'s local state — the customer's own Orders screen has no
  live or restart-safe connection to the canonical, server-authoritative order at
  all. It is a write-once snapshot, not a read-through view.

This is exactly the condition the original Phase 9 kickoff named verbatim as
disqualifying for APPROVED: **"legacy order path remains competing truth."** Two
genuinely different order models (`Order` canonical aggregate vs. `OrderModel`
legacy UI model) back two different screens' worth of state, connected by one
one-directional bridge at submission time only.

**Why this was not fixed in this session, and why that's the right call, not an
excuse:** a proper fix means giving `OrdersNotifier` a real read-through path off
`canonicalOrderRepositoryProvider` (a stream or an explicit refresh), while
preserving the extra fields `OrderModel` carries that `Order` does not yet model
(ratings, reviews, cancellation UI copy, courier-visibility legacy mirroring). That
is a genuine UI/state-architecture change to the screen customers actually use most,
not a backend-wiring task — the kind of change this project's own workflow rules
require a plan and explicit approval for before writing code, and not something
Sprints 9F–9J's own named scope ("server-authoritative events & outbox," "account
deletion," "media/push," "observability," "backup/CI") ever included. Silently
rewriting it now, unreviewed, this late in an already very long session, would trade
one undisclosed risk for another.

**Required fix, scoped for a following sprint ("Sprint 9K — Orders screen
read-through migration"):** give `OrdersNotifier` (or a successor) a real
subscription to `canonicalOrderRepositoryProvider`, keep `OrderModel`'s
customer-review/UI-only fields as a genuinely separate, additive layer keyed by
order id rather than folding them into the canonical `Order`, and delete
`LocalOrdersRepository`/`ordersRepositoryProvider` once nothing depends on it.

## 8. Event idempotency

**CLOSED / Verified**, freshly re-run this session
(`firebase emulators:exec --only firestore,functions "cd functions && npm test"`,
9/9 passing):

- `onOrderCreated.ts:38,57` — re-checks live Firestore status inside a transaction
  before applying `created -> pendingConfirmation`; a second trigger invocation for
  an already-transitioned order is a verified no-op
  (`✔ onOrderCreated ... Finished in 2.2722ms` on the second invocation in the test
  log, vs. the real write on the first).
- `onOrderCompleted.ts:55,72-73` — writes `orderEvents/{orderId}-completed` via
  `.create()`, which fails with `ALREADY_EXISTS`/code 6 on a repeat; that error is
  caught and treated as a no-op, not a failure.
  `✔ onOrderCompleted is idempotent - an unrelated update after completion never
  duplicates or errors the outbox record` passes directly on this.

## 9. Reward/stock single execution — "double-grant rewards / double-deduct stock"

**ACCEPTED / OUT OF SCOPE, Verified.** Grepped `functions/src/*.ts` for the
downstream chain: `onOrderCompleted.ts:66-68` writes the outbox record with
`visitRecorded: false, rewardsEvaluated: false, stockConsumed: false` hardcoded —
none of reward-granting, visit-recording, or stock-deduction is wired to order
completion at all yet, client or server side. The kickoff's disqualifying condition
is "events double-grant rewards / double-deduct stock" — since neither grants nor
deducts anything today, that specific failure mode cannot occur. This is an honestly
documented gap (the outbox record says so directly, in the data itself, not just in
a comment), not a hidden risk — closing it is real future work, not a Phase 9
regression.

## 10. Account deletion

**CLOSED / Verified.**

- IDOR: `CancelAccountDeletionRequest` previously trusted a bare `requestId` with no
  ownership check. Fixed — now requires `uid`, checks `request.uid != uid`, throws
  the identical violation for "not found" and "wrong owner" so the error leaks
  nothing about which case occurred. New test
  `throws (never cancels) when the caller does not own the request — IDOR
  protection` passes; the real caller (`AccountDataNotifier.cancelAccountDeletion`)
  now supplies `session.uid`, not a client-suppliable value.
- Cooling-off clock bug (`canCancel` reading system time internally instead of the
  caller's `now`) — found and fixed earlier in Sprint 9G by the sprint's own tests,
  not shipped unverified; documented in `docs/decisions.md` ADR-026.
- Release fallback — closed, see §2.
- Cloud Function (`processAccountDeletion.ts`) fails closed for not-found/not-due/
  wrong-status via `HttpsError`, is idempotent (`alreadyProcessed: true` on repeat —
  verified by `✔ processAccountDeletion is idempotent` in this session's fresh
  functions test run), and anonymizes inside a transaction.
- No longer UI-only: `AccountDataNotifier.requestAccountDeletion`/
  `cancelAccountDeletion` call the real use cases, not a fake dialog.

## 11. Media paths

**CLOSED / Verified**, freshly re-run this session
(`firebase emulators:exec --only storage "cd storage-tests && npm test"`,
10/10 passing): owner-only customer-photo read, org-scoped staff read, feedback
attachments permanently undeletable, public-read/no-client-write menu images,
org-membership-gated import files, fail-closed catch-all for unlisted paths.

## 12. Secret handling

**CLOSED / Verified.** `forbidden-secrets-scan` CI job
(`.github/workflows/ci.yml:74-99`) greps for private-key and service-account-JSON
shapes across the repo, excluding the standard FlutterFire client-config files
(`firebase_options*.dart`, `google-services.json`, `GoogleService-Info.plist` — not
secrets, just client identifiers). Documented in
`docs/deployment_and_operations.md` as a floor (grep-based, not a dedicated
secret-scanning service), not oversold as complete coverage.

## 13. Authorization before reads/writes

**CLOSED / Verified**, folded into §3/§5's emulator evidence — every Firestore rule
checked in this review requires `isOrgMember`/an active support grant/document
ownership before any read or write; the catch-all denies by default.

## 14. Audit durability

**CLOSED / Verified.** `auditEvents`/`orderEvents`/`accountDeletionAuditEvents` are
all Cloud-Function-only writes (`allow write: if false` for clients), append-only,
never client-deletable — verified directly by the
`audit events are read-only for members, never client-writable (append-only,
server-only)` emulator test.

## 15. Observability

**ACCEPTED / OUT OF SCOPE for this phase**, as the kickoff itself framed 9I as
"runbook foundations," not new instrumentation. `LoggingService` redacts sensitive
values before printing (`LogRedactor`, Phase 1) — real and unchanged.
`CrashReportingService` remains `NoOp` — a pre-existing, already-documented gap
(§5 of CLAUDE.md), not something 9I claimed to close.
`docs/observability_and_operations.md` documents exactly this real/foundation-only/
unbuilt split rather than overclaiming.

## 16. CI checks

**CLOSED / Verified.** `.github/workflows/ci.yml` now runs `quality` (format/
analyze/test — pre-existing), plus two new jobs added this phase: `emulator-tests`
(all three emulator suites — firestore, storage, functions) and
`forbidden-secrets-scan`. Documented honestly as **not independently verified
against a real GitHub Actions run** in this session (no runner available) — only
that the commands mirror what was proven correct locally, run repeatedly across this
session including immediately before this review.

---

## Summary table

| # | Area | Verdict |
|---|------|---------|
| 1 | Firebase production selection | CLOSED |
| 2 | No release InMemory fallback | CLOSED (Phase 9 scope) |
| 3 | Tenant isolation | CLOSED |
| 4 | Restaurant/branch resolution | ACCEPTED LOW RISK |
| 5 | Platform/tenant separation | CLOSED |
| 6 | Canonical identity | CLOSED |
| 7 | Canonical Order — sole truth | **BLOCKING** |
| 8 | Event idempotency | CLOSED |
| 9 | Reward/stock single execution | ACCEPTED / OUT OF SCOPE |
| 10 | Account deletion | CLOSED |
| 11 | Media paths | CLOSED |
| 12 | Secret handling | CLOSED |
| 13 | Authorization before reads/writes | CLOSED |
| 14 | Audit durability | CLOSED |
| 15 | Observability | ACCEPTED / OUT OF SCOPE |
| 16 | CI checks | CLOSED |

**One BLOCKING finding remains open** (§7). Per the kickoff's own rule, this forces
the phase-gate verdict to **APPROVED WITH REQUIRED FIXES**, not outright APPROVED —
see [phase9_final_report.md](phase9_final_report.md) item 30.
