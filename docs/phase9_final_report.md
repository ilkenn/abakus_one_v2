# Phase 9 — Final Closure Report

30-item mandatory closing report, per the explicit Phase 9 kickoff instruction: resume 9F→9J, then
perform the mandatory adversarial security review, documentation updates, and this report — ending in
one of APPROVED / APPROVED WITH REQUIRED FIXES / REJECTED. Every claim below cites a file, a test, or
a commit — not recollection. Evidence Classification tags (Verified/Inferred/Assumed) applied per this
project's standing rule.

Companion documents: [phase9_adversarial_security_review.md](phase9_adversarial_security_review.md)
(full findings), `docs/decisions.md` ADR-026 Decisions 1–12, `docs/feature_status.md`'s Phase 9 section.

---

**1. Scope and instruction recap.** This window's instruction: resume Phase 9 from Sprint 9F exactly
as previously scoped — 9F (server-authoritative events & outbox), 9G (account deletion backend), 9H
(media, push notifications & device tokens), 9I (observability & operations), 9J (backup, deployment &
CI/CD) — then the mandatory adversarial security review, documentation updates, and this 30-item
report, with explicit instruction not to stop for intermediate approval unless one of five original
stop conditions was reached. **Verified**: none of the five stop conditions (missing real Firebase
credentials, a destructive prod-data migration, a security decision that can't be fail-closed, a
required external paid/legal dependency, two conflicting approved business rules) were triggered at
any point.

**2. Sprint 9F — Server-authoritative events & outbox. DONE.** New `functions/` TypeScript Cloud
Functions project. `onOrderCreated` (Firestore `onDocumentCreated` trigger) applies the one valid
`created -> pendingConfirmation` transition inside a transaction, re-checking live status first —
idempotent, verified by a fresh test run showing the second invocation as a 2.3ms no-op. `onOrderCompleted`
(`onDocumentUpdated`) writes an `orderEvents` outbox record via `.create()`, catching `ALREADY_EXISTS`
as a no-op — idempotent, verified directly by a passing "never duplicates or errors" test. Committed
`cd27b70`.

**3. Sprint 9G — Account deletion backend. DONE**, with two real gaps found and closed by this
session's own review (see items 8–9 below). Real `core/account_deletion/` (request/cooling-off/cancel
lifecycle), `AuthNotifier` blocks new sign-ins during cooling-off/after completion (existing session
deliberately left signed in so cancellation stays reachable), `OtpVerificationResult.accountBlocked`
shows the real reason rather than a fabricated wrong-code message, Cloud Function
`processAccountDeletion` anonymizes the linked CRM `Customer` idempotently once cooling-off elapses.
Committed `9fe020f`; adversarial-review fixes in `981b898`.

**4. Sprint 9H — Media, push notifications & device tokens. DONE** for the authorization/ownership
seam; upload UI, real push delivery, and moderation explicitly deferred (named, not silently dropped).
New `storage.rules` (tenant-scoped, size/MIME validated, fail-closed default) — 10/10 emulator tests.
New `core/device_tokens/` (register, idempotent re-registration, revoke-on-logout wired into
`AuthNotifier.logout()`). Committed `94d8631`; release-fallback gap closed in `981b898`.

**5. Sprint 9I — Observability & operations. DONE**, documentation-first per the kickoff's own framing.
New `docs/observability_and_operations.md` — an honest real/foundation-only/unbuilt inventory plus 8
runbook entries. No new code surface; the infrastructure it documents (Crashlytics seam, `LoggingService`/
`LogRedactor`, `firebaseReadyProvider`, audit trails) predates this sprint.

**6. Sprint 9J — Backup, deployment & CI/CD. DONE** for a real CI extension; the rest documented, not
executed against a real project. `.github/workflows/ci.yml` gained `emulator-tests` (all three emulator
suites) and `forbidden-secrets-scan` jobs. New `docs/deployment_and_operations.md`. **Honestly flagged,
not overclaimed**: neither new CI job has been observed passing in a real GitHub Actions run this
session — no runner was available; only local-equivalence was verified. Committed `ca65253`.

**7. Adversarial security review — scope and method.** Performed after 9A–9J, per the kickoff's
mandatory requirement, before any phase-gate verdict. Sixteen named areas checked against direct
evidence (file reads, greps, and fresh emulator/test runs performed in this pass, not carried over from
earlier sprints' own gates) — full detail in
[phase9_adversarial_security_review.md](phase9_adversarial_security_review.md). Four real findings
surfaced; three closed, one named as BLOCKING and deliberately not fixed unreviewed (items 8–11).

**8. Finding 1 — CLOSED. IDOR in `CancelAccountDeletionRequest`.** The use case trusted a bare
`requestId` with zero ownership verification. Fixed: now requires `uid`, rejects a mismatched owner
with the identical violation used for "not found" (leaks nothing about which case occurred). Real
caller (`AccountDataNotifier.cancelAccountDeletion`) updated to supply `session.uid`, never a
client-suppliable value. New test: `throws (never cancels) when the caller does not own the request`.
Committed `981b898`.

**9. Finding 2 — CLOSED. No release-mode gating on two Phase-9 repositories.**
`accountDeletionRequestRepositoryProvider` and `deviceTokenRepositoryProvider` unconditionally resolved
to `InMemory*`, including in release builds — a release build would have silently, non-durably
persisted account-deletion requests and device tokens with no indication anything was wrong. Fixed with
`kReleaseMode`-gating (not `firebaseReadyProvider` — neither has a Firestore-backed alternative yet to
select between), mirroring Phase 8's `ProductionUnavailableStaffMemberRepository` pattern exactly.
Committed `981b898`.

**10. Finding 3 — CLOSED. `firestore.rules` order-creation rule rejected the real client's actual
write.** The rule only accepted `status == 'created'` at create time, but
`SubmitPosOrder`/`SubmitCustomerOrder` both apply the one valid `created -> pendingConfirmation`
transition in-memory before the first persistence write — every real order create would have been
denied against a Firestore-backed repository. Fixed to accept either status; `update` remains
permanently denied, so this does not weaken security. New emulator test added; all 24
`firestore-tests/rules.test.js` cases pass (was 23; the fix's own regression surfaced and was
immediately root-caused to a doc-ID collision in the new test, not the rule — fixed by using a distinct
doc ID). Committed `3c4668d`.

**11. Finding 4 — BLOCKING. Legacy order path remains competing truth.** Not fixed this session, named
explicitly. `OrdersNotifier` (backing `orders_screen.dart`, `order_detail_screen.dart`, the Home "Aktif
Siparişin" card) reads exclusively from `ordersRepositoryProvider`, which unconditionally resolves to
the legacy in-memory `LocalOrdersRepository` — never from the canonical `Order`
(`canonicalOrderRepositoryProvider`) this phase built. `checkout_screen.dart` bridges a one-time write
into both stores at submission time, but nothing reads canonical status transitions back — the
customer's own Orders screen has no live or restart-safe connection to the real,
server-authoritative order. This is the kickoff's own named disqualifying condition, found by tracing
actual data flow (`orders_provider.dart:22-24,75-78`, `checkout_screen.dart:248-250`), not assumed.
**Why not fixed here**: a correct fix is a genuine UI/state-architecture change (`OrdersNotifier` needs
a real read-through subscription while preserving `OrderModel`'s customer-review/UI-only fields that
`Order` doesn't model) — outside 9F–9J's own named scope, and the kind of change this project's
plan-first workflow requires explicit approval for before writing code. Scoped as required follow-up
("Sprint 9K — Orders screen read-through migration") — see item 26.

**12. Disqualifying condition check 1/9 — "Firebase persistence not genuinely wired."** **Not
triggered.** `Firebase.initializeApp()` is genuinely called at bootstrap
(`lib/bootstrap/firebase_bootstrap_service.dart:18`); `CanonicalOrderRepository`,
`AccountDeletionRequestRepository`, `DeviceTokenRepository`, `StaffAuthRepository`,
`PlatformAuthRepository` are all `firebaseReadyProvider`/`kReleaseMode`-gated to real implementations,
verified by passing emulator tests against the actual Firestore/Storage/Functions emulators, not mocks.

**13. Disqualifying condition check 2/9 — "customer production auth fails closed."** **Not triggered.**
`authRepositoryProvider` resolves to `ProductionUnavailableAuthRepository` (fails closed, never fakes
success) whenever `firebaseReadyProvider` is false — verified directly in
`lib/features/auth/presentation/providers/auth_provider.dart:20-31`.

**14. Disqualifying condition check 3/9 — "tenant data crosses boundaries."** **Not triggered.**
Verified by a freshly re-run 24/24-passing `firestore-tests/rules.test.js`: cross-tenant read denied,
self-role-promotion denied, arbitrary entitlement-grant write denied, expired platform support grant
denied, tenant/platform claim namespaces never cross, unlisted collections fail closed.

**15. Disqualifying condition check 4/9 — "legacy order path remains competing truth."** **Triggered —
see item 11.** This is the one condition from the kickoff's own list that is currently open. It is the
sole reason the verdict below is not an outright APPROVED.

**16. Disqualifying condition check 5/9 — "`Order.customerId` absent for authenticated orders."** **Not
triggered.** Traced the real call site, not just the field's existence:
`checkout_screen.dart:233,237` resolves `customerId` from `session.session?.uid` when authenticated
(`null` only for a genuine guest checkout), and passes it through to `SubmitCustomerOrder`, which
writes it onto the canonical `Order`.

**17. Disqualifying condition check 6/9 — "events double-grant rewards / double-deduct stock."** **Not
triggered — because neither exists yet.** `onOrderCompleted.ts` writes its outbox record with
`visitRecorded: false, rewardsEvaluated: false, stockConsumed: false` hardcoded; no code path grants a
reward or deducts stock from an order-completion event at all. A double-grant/double-deduct bug is
structurally impossible when nothing grants or deducts once, let alone twice. Recorded as an accepted,
honestly-documented gap (the outbox record itself says so), not silently narrowed.

**18. Disqualifying condition check 7/9 — "account deletion remains UI-only."** **Not triggered.**
`AccountDataNotifier.requestAccountDeletion`/`cancelAccountDeletion` call real use cases
(`RequestAccountDeletion`, `CancelAccountDeletionRequest`) against a real repository interface, not a
fake dialog with a `Future.delayed`. `AccountDataScreen`'s previous password-field fake delete flow
(the app has no password auth at all) is gone.

**19. Disqualifying condition check 8/9 — "release builds silently use InMemory."** **Not triggered,
for anything Phase 9 touches** — this was the specific gap items 9/2 found and closed this session.
Every Phase-9-introduced or Phase-9-touched repository (`CanonicalOrderRepository`,
`AccountDeletionRequestRepository`, `DeviceTokenRepository`) now fails closed in release rather than
silently persisting in memory. **Scope note, not a violation**: ~35 other feature repositories
(POS/courier/CRM/inventory/etc.) remain unconditionally `InMemory*` — this is unchanged pre-Phase-9
baseline behavior outside this phase's remit, not a new gap this phase introduced or is being judged
against.

**20. Disqualifying condition check 9/9 — "Critical/High/Medium security findings remain open."**
**Not triggered.** All four findings surfaced by this review were, at most, Medium severity (an IDOR
with no currently-exploitable production caller; two release-mode fallback gaps; one rules bug that
would have caused a functional failure, not a security bypass, since `update` was always denied
regardless). Three of four are closed. The one open finding (item 11) is a data-consistency/architecture
gap, not a security vulnerability — it does not expose one tenant's or customer's data to another; it
means a customer's own order-status view can go stale. Classified accordingly in
[phase9_adversarial_security_review.md](phase9_adversarial_security_review.md), not inflated or
downplayed to fit a desired verdict.

**21. Test evidence summary — all fresh, this session, not carried over.** `flutter analyze`: 0 issues.
`flutter test`: 2264/2264 passing (was 2263 before this session's IDOR test addition).
`firestore-tests/rules.test.js`: 24/24 passing (was 23; +1 for the `pendingConfirmation` create test).
`storage-tests/rules.test.js`: 10/10 passing, unchanged. `functions/` test suite: 9/9 passing
(5 order-trigger tests + 4 `processAccountDeletion` tests), unchanged. `dart format lib test
integration_test`: clean (1 file reformatted during this pass).

**22. Documentation updated.** New: `docs/phase9_adversarial_security_review.md` (this review, full
detail), `docs/phase9_final_report.md` (this document). Updated: `docs/decisions.md` (ADR-026 Decision
12 — the review's own closure decisions), `docs/feature_status.md` (Phase 9 section's post-9J
adversarial-fix entry, corrected the stale "Production limitations" paragraph that still described a
pre-9F state), `docs/business_rules.md` (version 3.2, unchanged from earlier this window — no new
business rule was needed for the review's own fixes, which are implementation-correctness fixes, not
new policy), `docs/master_roadmap.md` (progress notes on `IA-001`, `IA-003`, `MT-002`, `BE-001`, `F-004`
— each honestly scoped to what Phase 9 actually delivered against that item, not claimed complete),
`docs/module_catalog.md` (progress notes on `IA`, `MT`, `BE`, `NOTIF`, `PLAT` modules, same standard).

**23. Working-tree hygiene.** Checked before every commit this session, per the standing rule.
`.claude/settings.json`, `.claude/settings.local.json`, and the untracked `brand-production/` directory
were present in the working tree throughout this window and excluded from every commit
(`git add` targeted the specific intended files each time, never `-A`/`.`) — confirmed by `git status
--porcelain` showing them still modified/untracked after each commit in this window.

**24. Stop conditions — final check.** Re-confirmed at closure: no real Firebase credential was needed
beyond what already existed (all verification this session used the local emulator suite); no
destructive migration touched real production data (none exists to touch); every security decision in
this review resolved fail-closed (deny-by-default, `ProductionUnavailable*`, identical error messages
for IDOR); no external paid service or binding legal text was required (the `LegalDocumentVersions`
draft markers from Sprint 9G remain untouched, still explicitly DRAFT); no two approved business rules
conflicted. **None of the five stop conditions were reached at any point in this window.**

**25. What remains explicitly deferred — named, not silently dropped.** No upload UI for any Storage
path (9H). No real FCM/APNs push delivery — device-token storage only (9H). No
CrashReportingService implementation — remains `NoOp` (pre-existing, 9I didn't claim to close it). No
tested restore-from-backup drill, no dependency-vulnerability CI gate, no penetration test (9J,
documented as future PLAT-module work). No Firebase environment separation beyond the single
`abakusone` project (`CLAUDE.md` §5, unchanged). No visit-recording/reward-granting/stock-deduction
wired to order completion (item 17). ~35 pre-Phase-9 feature repositories remain unconditionally
`InMemory*` (item 19).

**26. Required follow-up — Sprint 9K scope (the condition for reaching outright APPROVED).** Give
`OrdersNotifier` (or a successor) a real read-through subscription to `canonicalOrderRepositoryProvider`
instead of `LocalOrdersRepository`; keep `OrderModel`'s customer-review/UI-only fields (ratings,
cancellation copy, courier-visibility legacy mirroring) as a genuinely separate, additive layer keyed by
order id rather than folding them into the canonical `Order`; delete `LocalOrdersRepository`/
`ordersRepositoryProvider` once nothing depends on them. This is a plan-first task per `CLAUDE.md` §16
— requires its own explicit plan and approval before implementation, not a continuation of this
session's autonomous scope.

**27. Files changed this window (adversarial-review + documentation phase only — 9F–9J's own files
are listed in their respective commits, items 2–6 above).**
`lib/core/account_deletion/account_deletion_providers.dart`,
`lib/core/account_deletion/application/cancel_account_deletion_request.dart`,
`lib/core/account_deletion/data/account_deletion_request_repository.dart`,
`lib/core/device_tokens/data/device_token_repository.dart`,
`lib/core/device_tokens/device_token_providers.dart`,
`lib/features/profile/presentation/providers/account_data_provider.dart`,
`test/core/account_deletion/application/cancel_account_deletion_request_test.dart`,
`firestore.rules`, `firestore-tests/rules.test.js`,
`docs/phase9_adversarial_security_review.md` (new),
`docs/phase9_final_report.md` (new, this file),
`docs/decisions.md`, `docs/feature_status.md`, `docs/master_roadmap.md`, `docs/module_catalog.md`.

**28. Commits made this window.** `981b898` — IDOR + release-fallback fixes. `3c4668d` — firestore.rules
`pendingConfirmation` fix. Documentation commit follows this report (see the closing commit made
immediately after this file, listed in the session's final git log).

**29. Residual risk statement.** The three closed findings each have direct, reproducible test evidence
— low residual risk. The one open finding (item 11) has a clear, bounded blast radius: it affects the
customer-facing Orders screen's staleness/consistency, not tenant isolation, not authorization, not
data integrity in the canonical store itself (which is correctly written and correctly protected by
Firestore rules regardless of what the legacy screen displays). No Critical or High finding was found
or is believed to remain, based on this review's coverage of all sixteen named areas — but this review,
like any adversarial pass performed by a single reviewer in one session, is not a substitute for a
dedicated third-party penetration test before this app takes real production traffic (already named as
future PLAT-module work in item 25).

**30. Verdict at original closure: APPROVED WITH REQUIRED FIXES** — superseded below by the Sprint 9K
Addendum's final verdict; this item's original text is kept for record.

Phase 9 (Sprints 9F–9J) is substantively complete against its own kickoff scope, with real,
emulator-verified backend infrastructure now existing for orders, account deletion, and device tokens
where none existed before, and a mandatory adversarial review that found and closed three real gaps
rather than rubber-stamping the work. It is **not** marked outright APPROVED because one of the
kickoff's own nine explicit disqualifying conditions — "legacy order path remains competing truth" — is
currently open (item 11/15). It is **not** marked REJECTED because that finding is architecturally
bounded, does not compromise tenant isolation or security, has a clear and proportionate fix already
scoped (item 26), and every other disqualifying condition is closed with direct evidence. Phase 9 may
be treated as APPROVED outright once Sprint 9K (item 26) closes item 11 under its own explicit plan and
approval, per `CLAUDE.md` §16.

---

## Sprint 9K Addendum — Canonical Customer Orders Closure

A dedicated follow-up sprint, kicked off explicitly to close item 11/15's one BLOCKING finding and
nothing else ("Do not start Phase 10. Do not add new features. Do not redesign architecture. Do not
migrate unrelated repositories."). Per `CLAUDE.md` §16, a concrete plan was presented and explicitly
approved before any code was written — not a continuation of Phase 9's own "do not stop for approval"
autonomy, which applied only to Sprints 9F–9J.

**Root cause.** `OrdersNotifier` (`lib/features/orders/presentation/providers/orders_provider.dart`)
read exclusively from `ordersRepositoryProvider` → `LocalOrdersRepository` (3 hardcoded demo orders,
identical for every user, no per-customer scoping at all) — never from `canonicalOrderRepositoryProvider`,
the real, Firestore-backed store `SubmitCustomerOrder`/`SubmitPosOrder` already wrote to.
`checkout_screen.dart` bridged a one-time write into both stores at submission time, but nothing ever
read canonical status transitions back — confirmed by direct inspection of every real consumer
(`orders_screen.dart`, `active_order_screen.dart`, `order_detail_screen.dart`,
`home_screen.dart`'s "Aktif Siparişin" card), not assumed.

**Architecture decision.** `OrdersNotifier` was converted from a synchronous `Notifier` to an
`AsyncNotifier<List<OrderModel>>`. `build()` now reads the signed-in session's `uid`
(`ref.watch(authProvider).session`, mirroring `features/crm`'s established `currentCustomerProvider`
pattern), returns an empty list when signed out, and otherwise calls
`canonicalOrderRepositoryProvider.findByCustomerId(uid)` — a method that already existed on the
interface, built in Sprint 9E specifically for this and never called until now — mapping each `Order`
through the pre-existing `OrderModel.fromCanonicalOrder` projection (already handled legacy status-label
compatibility via `OrderStatusLegacyLabel`). All existing mutator methods
(`addOrder`/`updateScheduledTime`/`updateLifecycleStatus`/`setCourierVisibleToCustomer`/`cancelOrder`/
`submitReview`) kept their exact signatures, now guarded against a still-loading state; `addOrder`
specifically awaits the notifier's own `future` first so a still-in-flight initial load can never
clobber a just-submitted order once it resolves (verified by a dedicated race-condition test).
`OrderModel`'s ~25 customer-review/UI-only fields were **not** folded into the canonical `Order` — they
remain exactly where they already lived, an explicitly-documented, pre-existing, unchanged limitation
(they never persisted anywhere even before this fix). `LocalOrdersRepository`/`ordersRepositoryProvider`
were **not deleted**, per this project's standing "never delete/orphan code unilaterally" rule — left in
place and reported here as newly orphaned for a human decision on removal. No realtime/streaming
mechanism was invented: none existed on either side (client polling or Firestore streams) before this
fix, so building one now would have been exactly the "redesign architecture"/"introduce unnecessary
complexity" this sprint's kickoff explicitly forbade — a pull-to-refresh affordance
(`RefreshIndicator` on `orders_screen.dart`, calling `ref.refresh(ordersProvider.future)`) was added
instead, the minimal standard-widget way to let a customer manually re-sync a one-shot-fetch-backed
screen.

**A second, previously undiscovered gap closed as a required part of this fix.** `firestore.rules`'
`orders` collection allowed `read` only to `isOrgMember` (staff) — a customer reading their own order by
`customerId` had no rule granting it at all, meaning the objective was unreachable without this. Fixed
with an additive customer-scoped read clause (`resource.data.customerId == request.auth.uid`); every
write rule (`create`/`update`/`delete`) is untouched, so this does not widen who can ever modify an
order. Verified adversarially with 4 new emulator tests: a customer can read their own order, cannot
read another customer's order (IDOR check), an unauthenticated request is denied, staff read is
unaffected.

**Tests.** 14 new Dart tests: 10 provider-level (`test/features/orders/presentation/providers/
orders_provider_test.dart` — signed-out empty list, new-customer empty history, per-customer scoping/
IDOR-equivalent check, newest-first ordering, completed/cancelled status-label round-trip, `addOrder`
race-safety, `cancelOrder`/`submitReview` local-mutation behavior) and 4 widget-level
(`test/features/orders/presentation/screens/orders_screen_test.dart` — loading renders `LoadingView`,
error renders `ErrorView` with a working retry, real empty state, a real seeded order renders end to
end). One pre-existing test required a fix, not a weakening: `home_screen_redesign_test.dart`'s "aktif
siparis" test previously asserted the *old, incorrect* behavior (a signed-out session seeing the global
demo order) — updated to seed a real canonical order under a real signed-in session and assert the
*corrected* behavior, since a guest correctly seeing nothing is this fix's intended outcome, not a
regression to paper over.

**Verification, all fresh in this pass.** `flutter analyze`: 0 issues. `flutter test`: 2278/2278 passing
(2264 → 2278; net +14 new, 0 skipped/weakened). `firestore-tests/rules.test.js`: 28/28 passing (24 → 28).
`storage-tests/rules.test.js`: 10/10, unchanged. `functions/` suite: 9/9, unchanged. `dart format`: clean.

**Security verification, explicit.** Tenant isolation: unaffected (the new rule only adds a
customer-scoped branch; org-member scoping is untouched and still separately tested). Authenticated
customer access: real — `findByCustomerId` is keyed by the live session's `uid`, never a client-supplied
value. Customer-cannot-read-another-customer's-orders: verified both at the rules layer (new emulator
IDOR test) and at the provider layer (new `OrdersNotifier` test seeding two customers' orders and
asserting only the signed-in one's are returned). Organization boundaries: unaffected, still enforced.
Firestore rules: 28/28 passing, including the 4 new tests. No IDOR introduced — one was specifically
tested against and found closed.

**Final adversarial verification — the kickoff's own four questions, answered directly:**

1. **Does any production customer order screen still read from InMemory?** **NO.** `orders_screen.dart`,
   `active_order_screen.dart`, `order_detail_screen.dart`, and `home_screen.dart`'s active-order card all
   read `ordersProvider`/`activeOrderProvider`, which now source exclusively from
   `canonicalOrderRepositoryProvider` — `firebaseReadyProvider`-gated to `FirestoreCanonicalOrderRepository`
   whenever Firebase is ready, `InMemoryCanonicalOrderRepository` only as the same universal test/
   not-yet-configured fallback every other Phase 9 repository already uses (not a customer-order-specific
   gap). `ordersRepositoryProvider`/`LocalOrdersRepository` are referenced by zero production code paths.
2. **Does any second authoritative Order model remain?** **NO.** `OrderModel` is now, unambiguously, a
   read/presentation projection of the canonical `Order` (via `OrderModel.fromCanonicalOrder`) for every
   real order — never an independently-seeded or independently-authoritative list. Its customer-review/
   UI-only fields are additive display state on top of that projection, not a competing order identity,
   status, or line-item source.
3. **Is Firestore now the single production source of truth?** **YES**, for `Order` specifically —
   `CanonicalOrderRepository` (Firestore-backed once ready) is the one repository every real order
   creation (`SubmitCustomerOrder`, `SubmitPosOrder`) and every real order read (this sprint's fix) goes
   through. (Scope note, not a gap in this answer: the ~35 other, unrelated feature repositories named in
   the original review's §2 remain outside `Order`'s scope entirely and were correctly not touched, per
   this sprint's explicit "do not migrate unrelated repositories" instruction.)
4. **Does every customer-facing order experience use the canonical Order aggregate?** **YES** — order
   history, active-order tracking, order detail, and the Home active-order card all resolve through the
   same `ordersProvider`/`activeOrderProvider` pair, which now has exactly one upstream source
   (`canonicalOrderRepositoryProvider`). Session-local-only UI state (reviews, delivery-preference
   toggles, the pre-existing non-durable cancel/status mutations) remains a documented, unchanged,
   pre-existing limitation — not a second order model, and not newly introduced by this sprint.

**PHASE 9 — APPROVED.**

All nine of the original kickoff's disqualifying conditions are now closed with direct, current-session
evidence (items 12–20 above), including the one that was open at original closure (item 15/§7,
"legacy order path remains competing truth" — closed by this addendum). No unresolved Critical, High, or
Medium security finding remains. The full Dart and emulator quality gate is green. Two items are
explicitly named, not silently dropped, as pre-existing/orphaned for a future human decision, not as
conditions on this verdict: `LocalOrdersRepository`/`ordersRepositoryProvider` (orphaned, not deleted)
and the `'ORD-2026-001'`-hardcoded reorder shortcut in `orders_screen.dart` (pre-existing demo logic,
now dead in practice against real order ids, unrelated to this sprint's own scope).
