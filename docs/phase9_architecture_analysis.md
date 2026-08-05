# Phase 9 — Production Backend & Infrastructure: Architecture Analysis

> **STATUS: DRAFT — PROPOSED, NOT APPROVED.** This is an analysis-and-planning document produced in
> response to an explicit "analysis only, do not implement" request. Nothing in this document
> authorizes implementation. No architecture decision recorded here is final until it goes through
> the normal Decision Review process (`ENGINEERING_CONSTITUTION.md`) and is separately recorded in
> `docs/decisions.md` as its own ADR. Nothing in `docs/feature_status.md` should be marked DONE based
> on this document. Produced 2026-08-05, evidence current as of Phase 8 close (commit `16d1e54`,
> 2136 tests passing).

Every material claim below is tagged **VERIFIED** (read directly from source), **INFERRED** (strongly
implied, not independently confirmed), or **ASSUMED** (stated by the codebase's own doc comments,
taken at face value without independent re-verification). This mirrors `ENGINEERING_CONSTITUTION.md`'s
own Evidence Over Assumption rule.

---

## Numbering note (read this first)

This session's own informal "Phase 1–8" work (the foundation/governance and product sprints referenced
throughout `docs/feature_status.md`/`docs/decisions.md`) is **explicitly documented as a separate, ad
hoc numbering, distinct from `docs/master_roadmap.md`'s own canonical Phase 0–18 sequence** — VERIFIED,
stated directly in `CLAUDE.md` and reiterated in `docs/master_roadmap.md`'s own Phase 10 progress note.
"Phase 9" in this document continues that same session-local, informal numbering (i.e., it is the next
sprint after the just-closed session "Phase 8"), **not** `master_roadmap.md`'s own "Phase 9 — Courier"
(already substantially implemented under session "Phase 5"). The roadmap item this document actually
maps onto is primarily **`master_roadmap.md`'s Phase 3 — Backend and Persistence** (`BE-001/002/003`),
which — VERIFIED — carries **zero implementation progress** through Phase 8: `docs/module_catalog.md`'s
`BE` module is the one module with no Phase 6/7/8 progress note appended, unlike every adjacent module.
Secondary roadmap touchpoints: Phase 1 (Identity/Auth — "has not started; login is still fully mocked"
per `CLAUDE.md`), Phase 2 (Multi-Tenant), Phase 17 (SaaS/White-Label), Phase 18 (Production Hardening).

---

## 1. Executive Summary

Abaküs One is, as of Phase 8 close, a **complete, well-tested, well-architected client-only
prototype** — 2136 passing tests, 0 analyzer issues, 184 repository interfaces with 178 matching
in-memory implementations, three cleanly-separated authorization stacks (customer/staff-tenant/
platform), and a genuinely thoughtful multi-tenant *shape* (Organization → Restaurant → Branch,
`organizationId`-scoped authorization with no role exemption). None of it is backed by a real server.
Every write is lost on app restart. Every authorization check is client-side and therefore
**advisory, not enforcing** — a modified client binary could bypass all of it today, because nothing
server-side re-checks anything.

The backend-platform decision is **not open** — `ADR-005` (2026-07-25, Accepted, not superseded)
already committed to Firebase, and three real Firebase projects are provisioned and already partially
wired (Firebase core init, App Check, Remote Config are real; Auth/Firestore/Storage/Crashlytics/
Messaging are not yet added as dependencies). This document **reaffirms** ADR-005 rather than
re-deciding it from zero, per the constitution's "No Silent Decisions"/decisions-are-recorded
discipline — but names a concrete fallback and a set of known limitations to accept explicitly.

The single most consequential finding for Phase 9 sequencing is **not** "there's no backend" — it's
that **the order-creation path is architecturally forked**: POS orders go through a real, tested
11-state `Order` aggregate; customer-app checkout orders go through an entirely separate legacy
`OrderModel` with hand-rolled ids that never touches the real aggregate. Every downstream "automatic"
workflow this analysis reviewed (kitchen → delivery → CRM/loyalty → stock consumption) is well-built,
idempotent, and audited, but is either never triggered in production or is only reachable from the POS
path — because the fork means `customerId` is never populated, `Delivery` is never created, and stock
consumption has no linkage to call from at all. **Building a real-time event architecture on top of the
current fork would formalize a bug, not fix one.** Phase 9 must resolve this before or alongside
introducing a real backend, not after.

**Recommendation, stated up front and justified in §22: PROCEED WITH PROPOSED PHASE 9 — CONDITIONAL.**
The proposed 9A–9H sprint sequence in §17 is sound and evidence-based, but two items require an
explicit human business decision before 9A can start (data-retention/cooling-off policy for account
deletion; whether to unify or explicitly reject unifying the two order paths) — flagged throughout as
**BLOCKED — BUSINESS DECISION REQUIRED** where they occur, consistent with never silently resolving a
product decision.

---

## 2. Verified Current State

Condensed from the five research passes; see the section-by-section detail below for full evidence.
Headline facts, all **VERIFIED**:

- **2136 tests passing**, 431 test files, 0 `flutter analyze` issues, `dart format` clean, single CI
  job (`format` → `analyze` → `test`, no build/deploy/signing stage) as of Phase 8 close.
- **184 repository-shaped interfaces**, **185 `InMemory*` classes** (178 matching repo implementations
  + 7 non-repository in-memory plumbing), only **5 interfaces without an InMemory impl** (all
  correctly use a `Development*`/`ProductionUnavailable*` pair instead — the auth-repository pattern).
  **~39 `NoOp`/`*Unavailable*`/`Unconfigured*`/vendor-stub classes** stand in for every external
  integration this app will eventually need (crash reporting, analytics, GPS, printers, 9 payment
  adapters, marketplace/webhook adapters, AI translation, FX rates).
- **`Firebase.initializeApp()` is genuinely called at every app boot** (`lib/bootstrap/
  firebase_bootstrap_service.dart`) — this corrects a stale claim in `CLAUDE.md` §5, which predates
  this wiring by ~4.5 hours of commit history and was never updated across 6 subsequent phases. Only
  `firebase_core`, `firebase_app_check`, `firebase_remote_config` are real dependencies; `firebase_auth`,
  `cloud_firestore`, `firebase_storage`, `firebase_crashlytics`, `firebase_messaging`, and any
  `cloud_functions` client are **not yet added** to `pubspec.yaml`.
- **Three structurally separate authorization stacks** (customer/`AuthSession`; staff-tenant/
  `ActorSession` + 115-value `PosAuthorizedAction`; platform/`PlatformActorSession` + 8-value
  `PlatformAuthorizedAction`) — confirmed zero shared types by grep, both directions.
  `PosAuthorizedAction` is self-documented as approaching its own previously-recorded ~150-value split
  trigger (currently 115).
- **Only one `Organization`/`Restaurant`/`Branch` is ever seeded** (`org-1`/`restaurant-1`/`branch-1`),
  hardcoded via `currentOrganizationIdProvider`. Real tenant-provisioning use cases
  (`CreateOrganization`/`CreateRestaurant`/`CreateBranch`) exist, are fully authorization-gated, and
  have **zero production call sites** — dead scaffolding.
- **The order-creation path is forked** (§6, §9) — POS (`SubmitPosOrder` → `CartToOrderMapper` → real
  `Order` aggregate with an 11-state machine) vs. customer checkout (`checkout_screen.dart` → legacy
  `OrderModel` → hand-rolled id → `ordersProvider`), never converging. `Order.customerId` is never
  populated at the one real call site that does use the real aggregate.
- **Every "automatic" cross-domain workflow is built but not reliably triggered**: `CreateDelivery`,
  `CompleteKitchenOrderPreparation`, and `ConsumeStockForOrder` are never instantiated in production
  code — only in tests. `CompleteDelivery`, `ApproveCashReconciliation`, and `ManuallyAssignDelivery`
  **are** wired to real screens. Real GPS capture code exists (`geolocator`) but is never instantiated;
  "live" courier tracking is pull-to-refresh, not a subscription. Exactly one `Timer` exists in the
  entire codebase (an OTP-resend UI countdown) — there is **zero** background-job infrastructure.
- **Payment**: domain logic (splits, change, optimistic concurrency, cash reconciliation) is real and
  solid; all 9 payment-provider adapters are hardcoded `notConfigured`, zero real gateway calls exist.
- **Security primitives are largely reusable as-is**: `ErrorMapper`, a 135-subtype
  `BusinessRuleViolation` hierarchy, `LogRedactor` (redacts token/password/secret/otp/pin/cvv/card/
  phone/email/tc/ssn key names + Bearer tokens + labeled secrets + emails + 10–19-digit runs),
  `flutter_secure_storage`-backed session/credential storage (only two consumers in the whole codebase).
- **Account deletion and data export are both fully fake** (confirmed by direct code read — a
  `SnackBar` and a `Future.delayed`, respectively). Privacy policy/terms of use have no real document.
  These are named, self-identified, exact-code-pointer gaps already surfaced by Phase 8's own
  `BuildStoreComplianceSnapshot`.
- **Media is architecturally ready for real storage but has zero storage today** — every media-bearing
  domain type (`CustomerPhoto`, `BrandAssetSet`, feedback attachments) deliberately stores only an
  opaque ref string; no `image_picker`/cloud-storage dependency exists.
- **`docs/current_state_audit.md`** is flagged **ASSUMED stale** (same commit-date proximity to
  `CLAUDE.md`'s stale Firebase claim, not independently re-verified in this pass) — recommend a
  documentation-currency pass before treating either as ground truth for Phase 9 kickoff.

---

## 3. Production Blockers

### BLOCKING BEFORE INTERNAL PILOT (a handful of trusted, known users)

1. **No persistence.** Every write is lost on restart. A pilot needs at minimum Organization/Restaurant/
   Branch/StaffMember/PlatformMember durable, plus whatever the pilot's actual workflow touches.
2. **No real staff/platform authentication.** Development Login (`DevelopmentStaffAuthRepository`/
   `DevelopmentPlatformAuthRepository`) is a bare picker with no credential of any kind — acceptable
   for internal dogfooding only if every pilot user is a known, trusted developer/founder; not
   acceptable the moment a non-developer restaurant employee is involved.
3. **The order-path fork (§6).** A pilot that exercises both POS and customer-app ordering will produce
   two disconnected order records for what should be one flow. Must be resolved or explicitly scoped
   around (e.g., pilot exercises POS only) before pilot start.
4. **Server-side authorization does not exist.** Acceptable risk for an internal pilot with trusted
   users on a controlled build, but must be named and accepted explicitly, not silently carried forward.
5. **No real tenant provisioning.** A pilot with more than one restaurant needs `CreateOrganization`/
   `CreateRestaurant`/`CreateBranch` actually wired to something, even a manual internal tool.

### BLOCKING BEFORE PUBLIC RELEASE

6. **Real server-side tenant isolation** (Firestore Security Rules or equivalent) — the #1 named risk
   for a multi-tenant SaaS, currently enforced nowhere except client code.
7. **Real customer authentication** (Firebase Auth phone OTP replacing the hardcoded `123456` dev code)
   with real OTP abuse protection (rate limiting/reCAPTCHA — Firebase Auth has this natively).
8. **MFA for admin/tenantOwner/platform roles.** The blast radius of these tiers (32 + 5 admin-only
   actions, all 8 platform actions) is too high for phone-OTP-only or password-only.
9. **Account deletion and data export must be real**, not fake — hard App Store/Google Play submission
   blockers, already self-identified with exact code pointers (`AccountDataScreen`, `AccountDataProvider`).
10. **A published privacy policy and terms of use**, plus the public, unauthenticated account-deletion
    URL Apple explicitly requires under Guideline 5.1.1(v) even pre-launch.
11. **Real webhook signature verification** before any real marketplace/payment provider is switched on
    — `UnverifiedWebhookSignatureVerifier` always returns `false` today (fail-closed, but must become
    fail-*correct* the moment a real integration exists; shipping a real integration behind a verifier
    that can never actually verify anything would be worse than not shipping it).
12. **Crash reporting wired for real** (`NoOpCrashReportingService` today) — cannot safely operate a
    public release with zero crash visibility.
13. **A real payment gateway integration** for at least one method, if payment collection is in scope
    for the public release (currently zero real gateway calls exist anywhere).
14. **Backups with at least one proven restore.** An untested backup is not a backup, per
    `docs/module_catalog.md`'s own `PLAT` module framing.

### IMPORTANT AFTER RELEASE

15. Real push notifications (currently 100% simulated, no FCM/APNs dependency).
16. Real courier live-location streaming (GPS capture code exists, never wired to a subscription).
17. Background-job infrastructure for entitlement/reward expiry, scheduled campaigns, retries.
18. Closing the `EntitlementScopeType.restaurant` authorization gap (currently silently skips context —
    dormant today, zero current callers, but a real latent gap once restaurant-scoped grants are used).
19. Real dispatch-scoring automatic courier assignment (built, currently unreachable — manual-only).
20. Marketplace/payment webhook ingestion endpoints (the three "trusted internal primitive" use cases
    are ready to be called; nothing can call them without a real HTTP-receiving backend).
21. Tenant-scoped backup/restore (day-one backups can be all-or-nothing; per-tenant restore is real
    engineering work, reasonably deferred).

### OPTIONAL FUTURE IMPROVEMENT

22. `PosAuthorizedAction`'s eventual split once it crosses its self-declared ~150-value threshold.
23. CDN/image-transform pipeline for menu images/brand assets.
24. Separate-database-per-tenant tier for enterprise customers.
25. AI-assisted retrieval (explicitly named in the request as "later" — no current infrastructure
    exists to evaluate against yet, correctly out of scope for Phase 9).
26. Full build-flavor/app-store tooling for publishing a second, differently-branded white-label app.

---

## 4. Backend-Platform Comparison

**This is a revalidation of an already-Accepted decision (ADR-005, 2026-07-25), not a from-zero choice.**
Per the constitution's "No Silent Decisions"/"Decisions Are Recorded" principles, re-litigating a
settled decision requires new evidence, not habit. The evidence gathered this pass is *consistent with*
ADR-005, with one nuance worth naming explicitly (Firestore Security Rules vs. Postgres RLS for tenant
isolation, the #1 named risk) — covered below, not treated as grounds to reverse the decision.

| Criterion | Firebase | Supabase | Appwrite | Custom |
|---|---|---|---|---|
| Multi-tenant SaaS fit | Good (security rules + custom claims) | Good (RLS is a stronger, more auditable primitive for exactly this) | Weaker RLS story, less mature at this scale | Full control, full burden |
| Strict tenant isolation | Enforced via security rules — correct but hand-written, rule-by-rule | Enforced via Postgres RLS — declarative, closer to the data, arguably easier to audit exhaustively | Weaker | Whatever is built |
| Relational data (recipes/costing/purchasing/reporting) | Weak — Firestore is document-oriented, no joins | **Strong** — real Postgres | Weak (own doc model) | Whatever is chosen |
| Transactions | Single-Firestore-transaction scope only (500-doc write cap, no cross-collection joins) | Real Postgres transactions | Limited | Whatever is chosen |
| Event-driven workflows | Cloud Functions + Firestore triggers — good, GCP-native | Edge Functions + Postgres triggers/logical replication — good | Functions exist, smaller ecosystem | Full flexibility, full burden |
| Offline-first Flutter | **Excellent** — this is Firestore's headline feature, already the reason ADR-005 chose it | Weaker offline story for Flutter specifically | Weaker | Must build from scratch |
| Realtime KDS/POS/courier | **Excellent** — native snapshot listeners | Good — Postgres logical replication-based realtime | Present, less proven at scale | Must build |
| Media/file storage | Firebase Storage — mature, Flutter-first SDK | S3-compatible Storage — solid | Present | Must build/rent |
| OTP (esp. Turkish carriers) | Firebase Phone Auth — native rate-limiting/reCAPTCHA, wide carrier support | Needs a third-party SMS provider (e.g. Twilio) wired in — Turkish carrier coverage is an **unverified unknown** | Same third-party dependency | Same |
| RBAC/ABAC | Custom claims + security rules | RLS + custom claims/JWT | Present, less mature | Full flexibility |
| Server-side rules | Firestore Security Rules (declarative, Firebase-specific DSL) | Postgres RLS (SQL-native, arguably more powerful/auditable) | Present | Whatever is built |
| Audit logs | Cloud Logging (native) + app-level audit collections (already the codebase's own pattern) | Postgres audit-log patterns are mature/standard | Present | Full flexibility |
| Webhooks | Cloud Functions HTTP triggers + Cloud Tasks for retry | Edge Functions | Present | Full flexibility |
| Scheduled jobs | Cloud Scheduler + Cloud Functions | pg_cron (native to Postgres) — arguably simpler | Present | Full flexibility |
| Marketplace/payment integrations | No inherent advantage either way — both call out to Turkish PSPs/marketplaces via server functions | Same | Same | Same |
| Reporting | **Weak natively** — ADR-005 already named BigQuery export as the mitigation | **Strong natively** — real SQL | Weak | Whatever is built |
| AI retrieval (later) | Vertex AI integrates natively with Firebase/GCP | Works via any vector-DB extension (pgvector) — arguably a stronger native fit long-term | Works via external service | Full flexibility |
| Operating cost | Pay-per-read/write; can surprise at scale if unoptimized | Predictable compute-based pricing; Postgres perf tuning is a known discipline | Similar to Supabase | Highest baseline cost (infra + ops) |
| **Maintainability by a non-developer founder** | **Strong** — managed, console-driven, zero server ops | Moderate — managed-cloud tier avoids self-hosting, but SQL/RLS authoring needs more technical fluency than Firestore rules for a non-developer | Weaker — smaller support ecosystem | **Weakest** — requires ongoing DevOps someone must own |
| Vendor lock-in | Real, Firebase-specific SDKs/rules throughout | Lower — Postgres underneath is portable; Supabase-specific bits (Auth/RLS glue) still exist | Real | None (but see cost) |
| Migration path | Data export to any target is possible but rules/functions rewrite is real work | Postgres data is trivially portable | Similar to Firebase | N/A |
| Turkish SMS/payment/marketplace ecosystem | No native advantage; goes through server functions calling Turkish PSPs/marketplaces either way | Same | Same | Same |
| **Already decided/partially built** | **Yes — ADR-005, 3 real projects provisioned, App Check + Remote Config already real** | No | No | No |

**Primary recommendation: reaffirm ADR-005 — Firebase** (Firestore, Cloud Functions, Firebase Auth,
Cloud Storage, Firebase Cloud Messaging, Crashlytics, Performance Monitoring, alongside the
already-real App Check/Remote Config). Rationale: it is already the recorded, Accepted decision with
real infrastructure partially standing; its offline-first/realtime fit for POS/KDS/courier is the
single strongest technical argument in the whole comparison and directly matches this app's dominant
workload shape; its non-developer-founder operability is the best in class. Its known weakness
(relational reporting/joins for recipes/costing/purchasing analytics) is already named and accepted in
ADR-005's own recorded consequence (BigQuery export as the mitigation) — this pass finds no new
evidence to overturn that call.

**Fallback: Supabase (Postgres + RLS)**, named specifically because tenant isolation is the #1 stated
risk in this entire analysis and Postgres RLS is a more declarative, more exhaustively-auditable
enforcement primitive for exactly that property than hand-written Firestore rules. If Phase 9's own
implementation of Firestore Security Rules proves difficult to get right/audit with confidence (a real
risk worth watching, not assumed away), Supabase is the concrete fallback to revisit — not a custom
backend, and not Appwrite (weaker fit against nearly every named requirement, correctly deprioritized).

**Custom backend**: explicitly not recommended for Phase 9 given the non-developer-founder constraint
— named only as a theoretical future path if operating scale (10,000+ restaurants, §16) someday
justifies dedicated infrastructure staff.

**What must remain provider-neutral regardless of this choice**: the Phase 8 Integration/Marketplace/
Payment Hub domain layer (`IntegrationProviderAdapter`, `PaymentProviderAdapter`) is already correctly
provider-neutral at the domain layer — the backend choice affects only how the real implementations
behind these adapters authenticate/call out, never the domain contracts themselves. Similarly,
`AuthRepository`/`StaffAuthRepository`/`PlatformAuthRepository`/all 184 repository interfaces are
already the correct seam — a backend swap means new implementations behind existing interfaces, not
interface redesign (see §8).

**Honest limitation of this comparison**: no hands-on technical spike was performed for either Firebase
or Supabase specifically for this app's workload (matches ADR-005's own stated 82% confidence, no spike
performed either) — this remains a documented, accepted gap, not resolved by this pass.

---

## 5. Recommended Backend Architecture (summary; detail in §6–§16)

- **Firestore** as primary datastore, `organizationId`-keyed shared-schema multi-tenancy (§6).
- **Firebase Auth** (phone OTP primary, email+password+TOTP MFA for admin/platform tiers) as the single
  canonical identity source for all three current session types (§7).
- **Cloud Functions** as the server-authoritative compute layer — order-status transitions, payment/
  refund logic, stock deduction, entitlement/role changes, tenant configuration writes, all move here
  from client-only use cases (§9).
- **Firestore Security Rules** re-deriving `organizationId`/role from Auth custom claims on every read/
  write — the actual tenant-isolation enforcement boundary (§6).
- **Cloud Storage** for all currently-opaque-ref media types, with signed URLs and Storage-rule access
  control (§11).
- **Cloud Messaging** for push, **Cloud Scheduler + Cloud Tasks** for background/retry jobs (§12).
- **Crashlytics + Performance Monitoring + Cloud Logging/Monitoring** for observability (§13), all
  free-tier at pilot/early-public scale.
- **Existing client-side patterns preserved, not redesigned**: idempotency-key discipline, the
  `Failure`/`ErrorMapper` pattern, `LogRedactor`, the 135-subtype `BusinessRuleViolation` hierarchy, the
  repository-interface seam itself.

---

## 6. Multi-Tenant Isolation Model

**Is the current hierarchy sufficient?** VERIFIED yes, in shape: Platform → Organization → Restaurant →
Branch matches what a real multi-location restaurant SaaS needs, and `Organization`'s own doc comment
already frames itself as "the top of the minimum-safe tenant boundary." Two real gaps: no restaurant-
level authorization context key exists at all (`kOrganizationIdAuthorizationContextKey`/
`kBranchIdAuthorizationContextKey` exist; no `kRestaurantIdAuthorizationContextKey` does — confirmed by
grep), and there is zero server-side enforcement of any of it today.

**Canonical tenant boundary**: `Organization` — matches existing domain framing, do not introduce a
new boundary type.

**Data ownership**:
- **Platform-owned**: `PlatformMember`, `PlatformAuditEntry`, the `IntegrationProviderRegistry` catalog
  (which providers exist at all, platform-wide), the global entitlement-module catalog.
- **Tenant-owned**: everything scoped to one `Organization` — `StaffMember` roster, `EntitlementGrant`s,
  `TenantBrandTheme`, `TenantIntegrationConfiguration`, CRM `Customer` records, Marketplace/Payment Hub
  accounts.
- **Brand-owned**: no separate `Brand` entity exists today; `Restaurant` is documented (ADR-023
  Decision 3) as the closest equivalent. **Recommend not inventing a new `Brand` entity in Phase 9**
  unless a real franchise/multi-brand-per-organization requirement is confirmed by the business —
  otherwise this is speculative scope.
- **Branch-owned operational data**: cash, kitchen, most POS state — already correctly branch-scoped
  today.
- **Global customer identity**: must become the real Firebase Auth UID (§7) — canonical across the
  whole platform, not per-tenant.
- **Tenant customer profile**: CRM `Customer` stays organization-scoped (a customer's loyalty/visit
  history at *this* tenant is tenant data) but should reference the global UID directly, not a
  phone-number-derived string (§7 closes the current three-way identity fragmentation).

**Isolation strategy comparison**:

| Strategy | Fit for this app |
|---|---|
| Shared DB/shared schema, tenant key | **Recommended for Phase 9.** Matches existing repository shapes (30 of 184 interfaces already carry `organizationId`), matches Firestore's natural per-document-field model, cheapest, fastest to ship. Risk: a missed rule/query filter is a real leak — mitigated by mandatory server-side rules, never client-only. |
| Shared DB, separate schemas | Doesn't map to Firestore's model at all; a Postgres-only pattern. Not recommended even under the Supabase fallback at this scale. |
| Separate DB per tenant | Strongest isolation, but provisioning/migration-per-tenant automation is real ongoing ops burden — wrong fit for a non-developer-founder-operable MVP. Reserve for a future enterprise tier. |
| Hybrid tiered | **Recommended as the future upgrade path** (§16, 1,000+ restaurant scale): shared schema by default, dedicated project/DB for enterprise tenants who contractually require it. |

**Required guarantees → concrete mechanism**:
- *No cross-tenant read/write*: Firestore Security Rules independently re-deriving `organizationId`
  from the authenticated user's custom claims on every rule evaluation — never trusting a client-
  supplied field for the check itself.
- *No tenant-controlled scope IDs trusted without server validation*: same mechanism — a client may
  *tag* a write with an `organizationId`, but the rule must verify it against the token's own claims,
  not merely echo it back.
- *No client-only authorization as the final boundary*: this is the core Phase 9 mandate. Today
  `RealPosAuthorizationPolicy` is 100% client-side. Production must mirror the *same rule set*
  server-side (Cloud Functions callable wrappers + Firestore rules); the client-side check becomes UX
  only (hide the button), never the enforcement — directly required by
  `ENGINEERING_CONSTITUTION.md`'s own named "Server-Authoritative Design" and "Fail Closed" principles.
- *Platform support access is temporary, justified, audited*: **new capability, does not exist today.**
  Design: a platform admin explicitly requests time-boxed, reason-logged read (rarely write) access to
  a specific tenant; the grant itself is a `PlatformAuditEntry`-logged action with an expiry; Firestore
  rules check for this specific, narrow grant rather than a blanket platform-role bypass.
- *Backups/restores must not mix tenants*: Firestore's native export is collection-level, not
  tenant-level — true per-tenant restore needs a Cloud Function-driven filtered re-import, named as
  real, non-trivial Phase 9+ work, not assumed solved by "we have backups" (§16).

**Repositories most at risk** (from the full inventory, §8): the ~30-interface courier cluster
(location pings, earnings, device sessions, geofence/fraud signals — almost none carry a scoping
parameter at all), `PosOrderRepository`/`CheckRepository`/`CashSessionRepository` (zero scoping
parameter on the interface itself — the tenant boundary lives only inside the stored object, not the
query surface), and **all** CRM and Marketplace repository interfaces (no explicit `organizationId`
parameter found on any of them). These should be prioritized for the addition of a real scoping
parameter *and* rule enforcement together, not rule enforcement alone bolted onto an unscoped query
surface.

---

## 7. Authentication and Identity Design

**Per-role design**:

| Role | Primary mechanism | MFA | Notes |
|---|---|---|---|
| Customer | Phone OTP (unchanged UX decision) via real Firebase Auth | Optional email as recovery | Replaces `DevelopmentLocalAuthRepository`'s hardcoded `123456` |
| Courier | Phone OTP, issued through the staff-auth path (not customer `AuthSession`) | Device trust (skip OTP on a recognized, previously-verified device) | Couriers re-authenticate often on shared/company devices — device trust reduces friction without weakening the boundary |
| Staff / Manager | Phone OTP acceptable | Optional | Lower blast radius (12–52-action tiers) |
| Tenant Admin / Tenant Owner | Email + password | **Mandatory TOTP authenticator MFA** | Highest tenant-side blast radius (32 admin-only + 5 tenantOwner-only actions) |
| Platform Administrator / Owner | Email + password | **Mandatory passkey or authenticator MFA — no SMS-only option** | SIM-swap risk unacceptable at this blast radius (a compromise here affects every tenant); a secure, one-time, never-client-reachable bootstrap process provisions the very first Platform Owner (mirrors the shape Development Login already established, minus the dev-only bypass) |

**Session refresh/revocation**: Firebase Auth ID tokens (short-lived, auto-refreshed) + custom claims
carrying role/branch/organization access (mirrors `ActorSession`'s own shape almost exactly — this is
a genuine advantage of the existing design, not a redesign). Custom-claims updates require a client
token refresh to take effect — document this propagation delay explicitly; the existing
`sessionsRevokedAt` forced-revocation pattern (already built and tested client-side) maps naturally to
"force a refresh via a listened Firestore document on revocation," not a new mechanism.

**Suspicious-login detection**: Cloud Function trigger on new-device/new-location sign-in, alerting the
account owner — new capability, not currently modeled.

**Canonical IDs and identity links** (closes the fragmentation found in research pass 3):

- **Firebase Auth UID becomes the one canonical identity.**
- `AuthSession` (customer) references the UID directly, not `phoneNumber` as today.
- `StaffMember`/`PlatformMember` gain a UID field, linking to the same identity space.
- CRM `Customer` references the same UID directly; the existing `findByPhoneNumber` bridge
  (`ResolveCurrentCustomer`) is retained only as a secondary/migration lookup, not the primary link.
- `Order.customerId` is populated **at submission time**, from the authenticated UID — this single
  change is what reactivates the already-real, already-wired CRM visit/reward engine, which today
  gracefully no-ops specifically because this field is always `null`.

**Migration from current development/in-memory identities**: this is **greenfield**, not a live-data
migration — no real production users exist yet (everything is `InMemory`/seeded/mocked). The actual
"migration" is: (a) replace the three `Development*AuthRepository` implementations with real
Firebase-Auth-backed ones behind the *same* interfaces (already the correct seam), (b) replace the
hand-seeded single `Organization`/`Restaurant`/`Branch`/`StaffMember`/`PlatformMember` with a real
bootstrap script, not committed demo-seed code, and (c) wire the already-built, zero-call-site
`CreateOrganization`/`CreateRestaurant`/`CreateBranch` use cases into a real onboarding screen.

---

## 8. Repository Migration Strategy

Given 184 interfaces, **a big-bang rewrite is explicitly wrong** — matches the request's own "avoid
rewriting all features at once" and the constitution's "Minimize Scope of Changes"/"Reversibility
Bias." Every interface is already a real seam (Riverpod-provider-injected everywhere); the
`Development*`/`ProductionUnavailable*` auth-repository pair already *proves* the swap-behind-the-same-
interface pattern works in this codebase today.

**Classification** (full detail in the underlying inventory; summary here):
- **(a) Trivial swap, same interface**: the ~65 repository interfaces that already carry an explicit
  `organizationId` or `branchId`/`restaurantId` scoping parameter — Organization/Restaurant/Branch,
  StaffMember/PlatformMember, EntitlementGrant, TenantIntegrationConfiguration, most of inventory/
  recipes/costing/purchasing/nutrition/allergens/menu_labels.
- **(b) Needs redesign before backing**: the ~30-interface courier cluster (needs realtime subscription
  support, not just CRUD — `Stream<>` return types, not `Future<List<>>`), the 25 audit-trail
  repositories (need durable, tamper-evident, append-only guarantees a swapped-in `Map`-equivalent
  cannot provide — Firestore's own document model is naturally append-friendly here, but retention/
  export policy needs a decision first, §16), `PosOrderRepository`/`CheckRepository`/
  `CashSessionRepository`/all CRM/all Marketplace interfaces (need a scoping parameter *added*, a
  breaking interface change, before real rule enforcement can attach to them meaningfully).
- **(c) Should stay client-local**: `LocalBowlBuilderCatalogRepository` (explicitly documented
  illustrative placeholder pricing, not real product data), UI-only local state.
- **(d) Should be replaced/redesigned entirely, not migrated**: `reservations/` (an empty 2-line stub —
  needs to be built, not swapped), the fully-simulated `NotificationService`/`MockNotificationRepository`
  (needs a real FCM-backed implementation, but the interface shape is close enough to keep).

**Migration mechanics**: adapter replacement, repository-by-repository, behind the same interface;
feature-flag each swap's real-vs-InMemory selection during rollout (mirrors the existing `kReleaseMode`
gating pattern). **No dual-read/dual-write is needed** — zero real production data exists today, which
significantly de-risks this relative to a typical live-database migration. Schema
versioning/migrations: Firestore has no formal migration framework; recommend a lightweight
`schemaVersion` field per collection + a Cloud-Function-run backfill-script convention as required
tooling to build (does not exist today, not assumed).

**Safest first repositories to migrate** (unblocks the most, smallest data volume, foundational):
1. `Organization`/`Restaurant`/`Branch` — everything else depends on these existing for real; trivial
   volume (currently exactly one of each).
2. `StaffMember`/`PlatformMember` — needed for real auth to have real records to authenticate against.
3. Auth sessions — via Firebase Auth directly, not a custom repository at all.
4. `EntitlementGrant` — small volume, high isolation value, unblocks a real (even if manual) billing
   story.
5. `TenantIntegrationConfiguration` — already has the best-designed tenant-scoping shape in the entire
   codebase (`findByOrganizationAndProvider`/`findByOrganizationId` vs. an explicitly-documented
   cross-tenant-only `findAll()`) — use as the reference implementation pattern for the rest.

**Defer to later waves**: the courier cluster (redesign, not swap) and the audit-trail repositories
(need a retention/export decision first, §16) — explicitly named as deferred, not silently dropped.

---

## 9. Event Architecture

Given "do not invent distributed complexity where unnecessary," the founder's non-developer status, and
the current absence of *any* queue/broker infrastructure: **recommend Cloud Firestore + Cloud Functions
triggers (native `onCreate`/`onUpdate` document triggers) as the event mechanism for internal flows,
not a separate message broker**, reserving **Cloud Tasks** specifically for the one place genuine
retry/backoff/dead-letter semantics are needed: external webhook ingestion.

| Flow | Mechanism | Server-authoritative? |
|---|---|---|
| Order submitted → kitchen accepted → prep completed | The `Order.transitionTo` state-machine logic moves server-side (Cloud Function/rule-enforced), never client-trusted directly | **Yes** |
| Delivery created / courier assigned | Firestore trigger off the kitchen-completion write → Cloud Function creates `Delivery` — closes the "never triggered" gap directly | Yes for creation; assignment can remain manual-first (matches current reality) with automatic scoring as a later addition |
| Delivery completed | Existing `CompleteDelivery` logic, moved/mirrored server-side | Yes |
| Visit recorded / reward evaluated | Firestore trigger off delivery-completed write → server-side equivalent of `RecordCustomerVisitAndEvaluateRewards` | Yes (money-adjacent) |
| Stock deducted | Same trigger-off-completion pattern — **also requires the menu-product↔recipe linkage gap to be closed first**, a real data-model addition, not just wiring | Yes |
| Cancellation / refund / reversal | Cloud Function only, idempotency key required (order id + reversal-attempt id), never client-writable directly | **Yes — highest-stakes flow in this list** |
| Survey/campaign trigger, feedback escalation | Firestore trigger + Cloud Function is sufficient; no special durability beyond Firestore's own guarantees | No |
| Marketplace order ingestion / payment webhook / integration health | **Real HTTP endpoint required** (Cloud Functions HTTP trigger) — external systems will retry, so this is the one place needing genuine idempotency-key + retry + dead-letter handling; recommend **Cloud Tasks** here specifically | Yes |

**Idempotency/versioning/correlation**: the codebase already has a strong idempotency culture
(`ConsumeStockForOrder`, `RecordWebhookDelivery`, `GrantVisitReward`, `SetTenantIntegrationEnabled` are
all documented idempotent-by-key). **Phase 9 should preserve this exact pattern server-side**, not
redesign it — the same idempotency-key parameter shape, just enforced by a Cloud Function instead of a
Dart use case.

**Explicit list of flows that must be server-authoritative** (directly required by
`ENGINEERING_CONSTITUTION.md`'s own named "Server-Authoritative Design" principle): order status
transitions, payment/refund/reversal, stock deduction, cash settlement, delivery completion, role/
entitlement changes, tenant configuration (org/branch creation, staff role assignment). None of these
may be directly client-writable once Phase 9 ships production auth — the client calls a Cloud Function
or writes through a rule-gated path that independently re-validates, never a bare document write.

---

## 10. Offline/Realtime Strategy

Firestore's native offline persistence (the core reason ADR-005 selected it) gives each app tier a
natural default:

| App | Offline capability | Realtime need |
|---|---|---|
| Customer | Browse menu/cart fully offline (local cache) | Order status updates — snapshot listener |
| POS | **Write-when-offline for order-taking** (register network flakiness is real) — Firestore's built-in offline write queue handles this natively | Cash/payment-session actions flagged read-only-if-stale beyond ~60s to avoid two staff double-taking the same table offline |
| KDS | Read-mostly | **Core value prop — must be a live snapshot listener**, replacing today's dead/untriggered orchestration entirely |
| Courier | Location pings should **queue-and-flush** — the `OfflineLocationQueueRepository` interface *already exists* in the inventory, correctly shaped for exactly this; prioritize its migration | Live location needs a genuine subscription (not today's pull-to-refresh) |
| Manager/Admin | Mostly read/reporting, can remain online-only (matches current pull-to-refresh behavior) | Low |

**Conflict resolution**: Firestore transactions for single-document read-modify-write; multi-document
races (e.g. two couriers accepting the same delivery) need an explicit "first-write-wins with a status
guard," which is already how `ManuallyAssignDelivery` is documented (idempotent assignment) — extend
the same pattern, don't invent a new one.

**Server timestamp policy**: use Firestore's `serverTimestamp()` sentinel everywhere a client today
calls `DateTime.now()` for anything audit- or money-adjacent — this solves clock-skew handling natively
rather than trusting device clocks, and is a mechanical, low-risk change.

**Operations that must never silently diverge** (explicit mechanism per item): payment (server-
authoritative, no offline write for the confirmation itself, only session/split *editing* may queue);
reward grant (already idempotent-by-key, safe to retry, never silently duplicate); stock deduction
(same idempotency pattern, needs a real trigger first per §9); cash settlement (require connectivity at
final approval — extends the existing no-self-approval dual-check pattern); delivery completion
(already geofence-gated — also require connectivity at the completion write, not just the GPS check);
role changes and tenant configuration (must be synchronous/online — authorization-critical, no queuing).

---

## 11. Media/File-Storage Architecture

Firebase Storage (already the decided platform). Design:

- **Tenant paths**: `/organizations/{orgId}/{category}/{entityId}/{filename}`.
- **Access control**: Storage security rules mirroring the same `organizationId`-claim check as
  Firestore rules — one consistent enforcement pattern across both.
- **Signed URLs**, time-boxed, for anything not meant to be public (customer photo review, receipts) —
  never bare public URLs for tenant-scoped media.
- **Upload limits**: enforced client-side (UX) **and** in Storage rules (size/MIME allowlist) — never
  client-only, matching every other "no client-only enforcement" finding in this document.
- **MIME validation**: Storage rules check the claimed `contentType`; a Cloud Function on
  upload-complete should re-verify actual bytes, not just the claimed MIME — closes a real spoofing gap
  rules alone can't close.
- **Malware-scanning seam**: name the Cloud Function hook point now (calling a third-party scan API
  later) so it's addable without a later redesign — not built by default in Phase 9.
- **Moderation lifecycle**: `CustomerPhotoStatus` (`pendingReview`/`approved`/`rejected`/`removed`/
  `underReview`) already exists and is correctly shaped — reuse as-is; a real upload should simply land
  in `pendingReview` automatically instead of requiring a fabricated ref.
- **Retention/deletion/anonymization**: ties directly to the account-deletion workflow (§15).
- **CDN/image transforms**: a resize-on-upload Cloud Function (or Cloud CDN in front of Storage) for
  menu images/logos at multiple sizes — **not needed for MVP pilot, explicitly deferred.**
- **Audit metadata**: log the ref + uploader + timestamp only, **never raw bytes/content** — this is
  already the codebase's own established discipline (mirrors `LogRedactor`'s posture), just extended to
  the storage layer.
- **Runtime vs. compile-time brand assets, clarified**: `BrandAssetSet`'s opaque refs are *runtime*
  (per-tenant logo/splash/icon swapped in-app via Storage) — this is genuinely different from a
  compiled app-store listing's actual icon/splash screen, which remains compile-time and would need
  real build-flavor tooling (confirmed not to exist, §3 item 26) before a *second published app* is
  possible. Runtime theming today can re-skin the in-app UI; it cannot re-brand the App Store listing
  itself.

---

## 12. Notifications/Background Jobs

**Push architecture**: Firebase Cloud Messaging (zero current dependency, must be added). Device-token
registration reuses the existing `NotificationRepository` interface (currently `MockNotificationRepository`,
a real no-op) — straightforward swap. Tenant-branded notifications: a Cloud Function reads the tenant's
already-real `BrandAssetSet` theming data before composing a send. Segmentation delivery: the existing,
real, tested `CustomerNotificationCampaign` CRM domain becomes the trigger source for FCM topic/segment
sends. Courier emergency alerts: highest-priority channel, should bypass quiet hours. Campaign
scheduling + failed-delivery retry: Cloud Scheduler/Cloud Tasks (GCP-native, no separate vendor).
Opt-in/opt-out: `NotificationSettingsModel` already exists client-side — needs real server-side
enforcement (currently unclear whether prefs are actually respected anywhere, not independently
verified). Quiet hours: **new requirement, not currently modeled** — small addition to the
notification-settings domain. Token invalidation: handle FCM's own invalid-token responses to prune
dead tokens.

**Background jobs** (Cloud Scheduler + Cloud Functions — no new infra vendor):
entitlement expiration (`EntitlementGrant.expiresAt` already modeled, needs a daily sweep) · session
cleanup · reward/spin-reward expiry · scheduled campaigns (CRM already has the concept) · stale-courier
detection (meaningful only after §10's realtime location work lands) · expiry warnings
(`GetExpiryWarnings` already exists, just needs a scheduled trigger instead of manual refresh) ·
marketplace/webhook retries (§9, via Cloud Tasks) · data-deletion/export jobs (§15) · backups (§16) ·
health checks (§13).

---

## 13. Observability/Support Design

The founder is not a developer — every recommendation below is chosen for **zero/near-zero cost and
minimal new-vendor surface** at pilot/early-public scale, reusing the Firebase ecosystem already
decided.

- **Structured logs**: `LoggingService`/`LogRedactor` are already real and reusable client-side; the
  gap is a **server-side equivalent** — Cloud Functions structured logging to Cloud Logging (GCP-
  native, generous free tier).
- **Correlation IDs**: extend the existing idempotency-key culture to double as a trace/correlation id
  threaded client → Cloud Function → Firestore write → trigger chain — no new concept, just a wider
  application of an existing one.
- **Crash reporting**: Firebase Crashlytics — free, already the ADR-005-named target, directly closes
  the Release Readiness `crashReporting: notReady` gap identified in Phase 8's own work.
- **Performance monitoring**: Firebase Performance Monitoring — same ecosystem, minimal extra cost.
- **Backend metrics / integration health**: Cloud Monitoring (free-tier dashboards for Functions/
  Firestore usage); `BuildPlatformMonitoringSnapshot`/`BuildProviderHealthProjection` already model this
  client-side and should be *extended*, not replaced, once real provider adapters exist.
- **Alert severity/incident records**: Cloud Monitoring alerting policies — no new vendor.
- **Human-readable error IDs**: the existing 135-subtype `BusinessRuleViolation` hierarchy already
  gives structured, named error types — map each to a short, stable, support-facing code (e.g.
  `ERR-PAY-014`) rather than raw exception text, which the codebase already refuses to show users.
- **Tenant-aware diagnostics**: every server log/metric should carry `organizationId` as a Cloud
  Logging label for filterable per-tenant debugging.
- **Safe support impersonation**: the time-boxed, audited "platform support access" concept from §6.
- **Feature kill switches**: `FeatureFlagsService` is already real and wired end-to-end — reuse
  directly; the remaining gap is *setting production values in the Firebase console*, an ops task
  already self-identified by Release Readiness, not new engineering.
- **Rollback**: app-level via standard store staged-rollout percentage (both stores support this
  natively); backend-level via Cloud Functions' native revision traffic-splitting.
- **Runbooks**: a markdown runbook per incident class, living in `docs/` — process work, not infra.
- **Support dashboard**: `PlatformShellScreen`/`BuildPlatformMonitoringSnapshot` are already a real
  foundation — extend with the health/incident data above rather than building a new tool from scratch.
- **No secrets/PII in logs**: `LogRedactor`'s existing discipline extends server-side unchanged.

**Free/open-source-first recommendation**: Firebase's own free-tier suite (Crashlytics, Performance
Monitoring, Cloud Logging/Monitoring) covers nearly everything needed through the "first 100
restaurants" mark at effectively zero cost. Paid observability (Sentry, Datadog, etc.) becomes worth
evaluating only once Firebase's own retention/query limits start to bind — realistically past the
1,000-restaurant mark (§16), not before.

---

## 14. Security Threat Model

| Threat | Primary control(s) |
|---|---|
| Cross-tenant access / IDOR | Server-side rules re-deriving `organizationId` from Auth claims (§6) |
| Privilege escalation | Custom claims settable **only** via Cloud Function, never client-writable; role-change audit trail (already exists client-side, extend server-side) |
| Session theft | Short-lived Firebase Auth ID tokens + refresh rotation (Firebase default); revocation via forced sign-out |
| OTP abuse | Firebase Phone Auth's native rate-limiting/reCAPTCHA — replaces today's fully-fake 30s-cooldown-only client logic |
| Account takeover | MFA for elevated roles (§7); suspicious-login alerting (new) |
| Loyalty/QR/coupon fraud | Move the already-idempotent-by-key reward/discount checks server-side — no rule redesign, just relocation of the enforcement point |
| Marketplace/payment webhook forgery | Real signature verification — closes the exact, already self-documented `UnverifiedWebhookSignatureVerifier` gap; needs a real crypto dependency + the provider's signing secret in Secret Manager |
| Replay attacks | Idempotency keys (existing pattern) + timestamp-window rejection on signature checks |
| Credential leakage | GCP Secret Manager for server-side secrets; `LogRedactor` pattern already trained for the client side |
| Staff insider misuse | The 25 existing audit trails + the time-boxed/audited platform-support-access pattern (§6) for any elevated internal access |
| Recipe/supplier-price leakage | Already largely `organizationId`-scoped per the inventory (§8) — needs the same server-rule enforcement as everything else, no special new control |
| Location privacy | **New requirement, not currently modeled**: customer should see courier location only during an active delivery, never a historical trail beyond a short window — name explicitly, do not assume |
| Photo abuse | MIME/malware scanning (§11) + the existing moderation lifecycle |
| Denial of service | Firebase App Check (**already real and wired**) directly mitigates non-genuine-client abuse; extend its enforcement to every new Cloud Function callable, not just currently-wired surfaces |
| Dependency/supply-chain compromise | CI already runs format/analyze/test — add a dependency-vulnerability-scan step (Dependabot or `dart pub outdated`, free) to the existing single job |

**No Critical/High finding may knowingly ship to public release** — mapped directly: real tenant-
isolation rules (Critical), real webhook signature verification before any real integration goes live
(Critical — currently not-applicable since no real integration exists, but a hard gate the moment §9's
webhook work reaches a real provider), MFA for admin/platform tiers (High), a real account-deletion
backend (High — also a store-submission blocker per §15).

---

## 15. Privacy, Deletion &amp; Store Requirements

**One backend workflow serving both in-app and unauthenticated web deletion requests**:

1. **Identity verification** — in-app: existing Firebase Auth session. Web (unauthenticated): a
   re-verification step (code sent to the phone/email on file), since the requester isn't authenticated
   in a browser context.
2. **Deletion request created** (status: `pending`).
3. **Cooling-off/cancellation window** — 🚧 **BLOCKED — BUSINESS DECISION REQUIRED**: whether to offer
   one (e.g. 7 days, cancelable) is a product/legal decision, not an engineering default to invent
   silently. The system should support an optional window either way; whether it's enabled and its
   length is not this document's call.
4. **Legal retention**: financial/audit records are anonymized, not hard-deleted (matches the existing
   Turkish-language `StoreComplianceCriterion` text's own framing) — PII fields are scrubbed across
   every tenant-scoped record referencing the customer; anonymized transaction/audit records remain.
5. **Status tracking** (pending/processing/completed), surfaced back to the requester.
6. **Completion notification** (email/SMS).
7. **Audit entry recording the deletion event itself, without the deleted PII** — directly matches the
   "audit without unnecessary PII" requirement and the existing `LogRedactor` discipline.

**Data export**: same Cloud-Function-driven pattern — generate a real bundle (JSON/CSV) to Storage,
signed URL, time-boxed, replacing today's 4-second fake delay.

**Consent records / marketing preferences**: extend `NotificationSettingsModel` with an explicit
consent-timestamp + accepted-policy-version pair.

**Privacy policy / terms of use version acceptance**: 🚧 **BLOCKED — BUSINESS DECISION REQUIRED** (and
explicitly out of scope for this document per the user's own instruction not to write legal text) —
needs a real, published document before any client-side "accepted version" field is meaningful.

**Data-retention policy**: needs a business decision per data category (order history, audit logs,
location history) — named as a required decision, not an engineering default.

**Apple Privacy Nutrition Label / Google Data Safety, source of truth**: recommend a single, versioned
internal document (e.g. `docs/data_safety_declaration.md`) enumerating exactly what's collected,
generated from the real Firestore schema + `LogRedactor`'s own marker list — an accurate technical
source, not a marketing team's guess.

**Account deletion public URL**: a real, unauthenticated, published web page hitting the same
Cloud Function endpoint above — Apple explicitly requires this under Guideline 5.1.1(v) even for a
not-yet-published app; already correctly named in Phase 8's own `StoreComplianceCriterion` text.

**Support/legal pages**: same treatment; Firebase Hosting is a natural zero-new-vendor choice, already
implicitly available via the existing Firebase projects.

---

## 16. Backup/DR/Deployment Design

- **Environments**: client-side dev/staging/production separation already exists (3 real Firebase
  projects) — Phase 9 needs the backend-side equivalent actually populated with real resources per
  project, not just client config pointing at empty projects.
- **Secrets management**: GCP Secret Manager for webhook signing secrets/API keys — never in Firestore,
  never in logs.
- **Backups**: Firestore's native scheduled export to Cloud Storage (built-in, just needs enabling +
  a Cloud Scheduler trigger). Point-in-time recovery (Firestore's own PITR, paid tier, 7-day window):
  recommend enabling once past pilot, cost-justified at that point rather than from day one.
- **Tenant restore strategy**: Firestore backups are collection-level, not tenant-level. Recommend
  accepting **all-or-nothing restore at MVP stage** (full-collection restore to a staging project, then
  filtered re-import for the one affected tenant, a slow but workable disaster path) and naming
  true tenant-scoped restore as explicitly deferred capability (§3 item 21) — not silently assumed
  solved by "we have backups."
- **RPO/RTO targets**: propose modest initial targets for pilot (RPO 24h via daily export, RTO
  best-effort/hours), tightening only once paying tenants justify the cost — this should be a stated
  business decision at each scale tier, not an engineering default.
- **Rollback**: app-level via native store staged-rollout; backend-level via Cloud Functions' native
  revision traffic-splitting.
- **DB migrations**: the `schemaVersion`-field + backfill-script convention from §8.
- **Canary/staged rollout**: Cloud Functions traffic splitting (backend) + Play Console/App Store phased
  release (app) — both native, zero new tooling.
- **App version compatibility**: since this isn't a REST API but Firestore+Functions, "API versioning"
  becomes Cloud Function callable versioning + a minimum-supported-app-version check, Remote-Config-
  driven (already real infra) to force an update prompt when needed.
- **Maintenance mode**: already exists client-side, real and audited (Phase 6) — just needs to actually
  gate something once real traffic exists (currently documented as built-but-unread-by-anything).
- **Incident response**: runbook docs (§13).

**Realistic targets by scale**:

| Scale | Target |
|---|---|
| Internal pilot (1–5 restaurants, trusted users) | Manual backups acceptable, no formal RPO/RTO SLA, reuse the existing staging project, founder/dev directly monitors |
| First public release (~20–50 restaurants) | Daily automated Firestore export; Crashlytics + Performance Monitoring live; real account-deletion/data-export shipped (hard store requirement); basic Cloud Functions error-rate alerting |
| 100 restaurants | PITR enabled; RPO &lt;4h; at least semi-manual tenant-scoped restore tooling; on-call rotation or a paid monitoring service considered |
| 1,000 restaurants | Dedicated DB/project tier available for enterprise tenants (the hybrid isolation model from §6); real SLA-backed RPO/RTO (e.g. 1h/4h); BigQuery export live for reporting (ADR-005's own already-recorded consequence); realistically past what one non-developer founder can operate alone — dedicated backend/infra help likely needed |
| 10,000 restaurants | Full production-hardening posture per `master_roadmap.md`'s own Phase 18 (`HARD-001/002/003`); dedicated security audit/pentest (already named there as a non-negotiable gate); formal DR runbooks tested via real restore drills; worth revisiting the Firebase-vs-custom-backend call with real operating-cost data that doesn't exist today |

---

## 17. Proposed Phase 9 Sprints

Deliberately scoped to **unblock internal pilot only** — not the full 10,000-restaurant posture in one
pass, per the request's own "keep the phase focused" instruction. 8 sprints, 3–5 tasks each.

### 9A — Foundation Decisions &amp; Dependency Approval (no code beyond config)
1. **Reaffirm ADR-005**, record this document's revalidation as a short addendum to it (not a new ADR
   unless the human reviewer disagrees with the reaffirmation). *Blocks: everything below.*
2. **Explicit new-dependency approval** (per `CLAUDE.md` §15) for: `firebase_auth`, `cloud_firestore`,
   `firebase_storage`, `firebase_messaging`, `firebase_crashlytics`, `firebase_performance`, a
   `cloud_functions` client if needed, `package_info_plus`, `image_picker`, a real crypto package for
   webhook signatures. Each is a separate, named decision, not a bundle.
3. **Business decisions requested** (🚧 flagged throughout this document): account-deletion cooling-off
   policy; privacy policy/terms of use publication; whether the two order-creation paths (§6 of the
   evidence) should be unified or the customer-app path retired in favor of the POS/real-`Order`
   aggregate.
4. **Documentation currency pass**: correct `CLAUDE.md` §5's stale "Firebase never initializes" claim;
   re-verify `docs/current_state_audit.md` for the same staleness class.
- *Blocks internal pilot: yes (everything downstream depends on 9A-1/9A-2). Blocks public release: yes.*

### 9B — Real Authentication (customer, staff, platform)
1. Real Firebase Auth phone-OTP behind the existing `AuthRepository` interface, replacing
   `DevelopmentLocalAuthRepository` — same interface, new implementation.
2. Real Firebase Auth (email+password+TOTP) behind `StaffAuthRepository`/`PlatformAuthRepository` for
   admin/tenantOwner/platform tiers; phone-OTP path for staff/manager/courier tiers.
3. Custom claims mirroring `ActorSession`/`PlatformActorSession` shape (roles, branch/org access).
4. Secure Platform Owner bootstrap process (never client-reachable in release).
- *Affected contexts: auth, admin, platform. Prerequisite: 9A. Risk: High (identity foundation for
  everything else). Tests: real-vs-fake OTP flow, custom-claim propagation, MFA enforcement for
  admin/platform tiers, revocation-takes-effect-on-refresh. Blocks internal pilot: yes (staff/platform
  auth). Blocks public release: yes (customer auth + MFA).*

### 9C — Tenant Foundation &amp; Server-Side Authorization
1. Migrate `Organization`/`Restaurant`/`Branch`/`StaffMember`/`PlatformMember` to Firestore (§8 wave 1).
2. Wire the existing, zero-call-site `CreateOrganization`/`CreateRestaurant`/`CreateBranch` use cases
   into a real (even minimal/internal-only) onboarding flow.
3. Author Firestore Security Rules enforcing `organizationId`/role checks, mirroring
   `RealPosAuthorizationPolicy`'s exact rule set — server-side re-implementation of an already-correct
   client-side design.
4. Add the missing restaurant-level authorization context key and close the
   `EntitlementScopeType.restaurant` silent-skip gap identified in Phase 8's own security pass.
- *Prerequisite: 9B. Risk: Critical (this is the tenant-isolation boundary). Tests: adversarial
  cross-tenant read/write attempts against rules (not just unit tests — rules-emulator-based).
  Blocks internal pilot: yes. Blocks public release: yes.*

### 9D — Order-Path Unification (closes the P0 architectural fork)
1. 🚧 Depends on the 9A-3 business decision.
2. If unifying: retire `checkout_screen.dart`'s legacy `OrderModel` path, route customer-app checkout
   through `CartToOrderMapper`/the real `Order` aggregate, populating `customerId` from the
   authenticated UID (§7).
3. If explicitly not unifying (business chooses to keep both, scoped differently): document that
   decision as its own ADR, with the accepted consequence that CRM/loyalty/stock-consumption remain
   dead for the customer-app path specifically.
4. Regression coverage proving both remaining path(s) produce a real, queryable `Order`.
- *Affected contexts: orders, pos, crm, cart. Prerequisite: 9C (needs real customerId source). Risk:
  High (touches the most-forked part of the domain model). Blocks internal pilot: only if the pilot
  exercises the customer-app path — recommend pilot scope to POS-only if 9D is not complete first.
  Blocks public release: yes.*

### 9E — Core Event Wiring (kitchen → delivery → CRM → stock, first slice)
1. Move `Order`/`Delivery` status transitions server-side (Cloud Functions), per §9.
2. Wire the real trigger from kitchen-completion to `CreateDelivery` (closes the "never instantiated"
   gap).
3. Wire the real trigger from delivery-completion to the CRM visit/reward engine (already
   production-wired on the client side — this closes its upstream blocker).
4. Explicitly defer stock-consumption wiring (blocked on the separate menu↔recipe linkage gap — name
   as its own follow-up task, not silently bundled here).
- *Prerequisite: 9D. Risk: Medium (logic already exists and is tested; this is relocation + real
  triggering, not new design). Tests: end-to-end emulator-based flow tests. Blocks internal pilot: no
  (manual dispatch remains an acceptable pilot workaround). Blocks public release: yes (this is the
  core "the app actually works end-to-end" claim).*

### 9F — Observability MVP
1. Crashlytics + Performance Monitoring wired for real (closes a named Release Readiness gap directly).
2. `package_info_plus` for real app-version observability (closes another named gap directly).
3. Server-side structured logging (Cloud Logging) + correlation-id threading.
4. Minimal Cloud Monitoring alerting on Cloud Functions error rate.
- *Prerequisite: 9B (needs real backend calls to observe). Risk: Low. Blocks internal pilot: no. Blocks
  public release: yes (crash visibility is a hard gate per §3).*

### 9G — Account Deletion, Data Export &amp; Store Compliance MVP
1. Real account-deletion Cloud Function workflow (§15), in-app trigger.
2. Real data-export Cloud Function workflow (§15).
3. Public, unauthenticated web deletion-request page + URL (Apple 5.1.1(v) requirement).
4. Real published privacy policy/terms of use document 🚧 **BLOCKED — BUSINESS DECISION REQUIRED**
   (content), engineering wiring only once content exists.
- *Prerequisite: 9B (needs real identity to verify deletion requests against). Risk: Medium (legal-
  adjacent, get the anonymization-vs-hard-delete boundary right). Blocks internal pilot: no. Blocks
  public release: yes — hard App Store/Google Play submission blockers.*

### 9H — Internal Pilot Readiness Gate
1. Run the full existing 2136-test suite plus 9A–9G's new tests against real Firebase (staging
   project), not emulator-only, at least once.
2. Adversarial tenant-isolation test pass specifically against the 9C rules (mirrors Phase 6/7/8's own
   dedicated-verification-pass precedent — do not self-attest).
3. Manual bootstrap of the first real Organization/Restaurant/Branch/Platform Owner via the 9C
   onboarding flow, not seed code.
4. Written pilot readiness sign-off against §18's criteria below.
- *Prerequisite: all of 9A–9G. Risk: this is a gate, not new engineering. Blocks internal pilot: this
  IS the internal-pilot gate. Blocks public release: yes (pilot must pass before public work starts).*

**Explicitly deferred to later phases** (named, not silently dropped): full push-notification
integration (§12) beyond MVP token wiring, automatic dispatch scoring, real payment-gateway
integration, real marketplace/webhook receivers actually going live with a named provider, background-
job infrastructure beyond the pilot's minimum, tenant-scoped backup/restore, the enterprise-tier hybrid
isolation model, `PosAuthorizedAction`'s eventual split, CDN/image-transform pipeline, AI retrieval.

---

## 18. Phase 9 Entry Criteria

- This document has been reviewed by the human decision-maker and either approved as-is or revised per
  their feedback (per the request's own "analysis only" framing — Phase 9 implementation does not start
  from this document alone).
- The three 🚧 business decisions in §17 (9A-3) are resolved, at least provisionally, before 9D/9G start
  (9A/9B/9C can proceed in parallel with those decisions still pending).
- New-dependency approvals (9A-2) are granted individually, per `CLAUDE.md` §15.

## 19. Internal-Pilot Readiness Criteria

- 9A through 9C complete and passing their own tests.
- 9D resolved (either unified, or explicitly scoped around for a POS-only pilot).
- Real staff/platform authentication in place for every pilot participant — no Development Login in
  the pilot build.
- Server-side tenant-isolation rules deployed and adversarially tested (9C-4/9H-2).
- At least one real `Organization`/`Restaurant`/`Branch` provisioned through the real onboarding flow,
  not seed code.
- 9H's full sign-off complete.

## 20. Public-Release Readiness Criteria

- Everything in §19, plus:
- 9E, 9F, 9G complete.
- Real payment gateway integration for at least one method (if payment collection is in scope for this
  release — confirm with the business before assuming yes).
- Real webhook signature verification if any real marketplace/payment integration is going live
  simultaneously (if not going live yet, this gate does not apply — but must not be silently skipped
  once one does).
- A security review of the 9C rules by someone other than their author (mirrors this codebase's own
  established "dedicated skeptical verification pass" precedent — 6P/7S/8S).
- Published privacy policy, terms of use, and the public account-deletion URL are live.
- At least one proven backup restore has been performed and timed.

## 21. Risks and Unresolved Business Decisions

- 🚧 Account-deletion cooling-off policy (§15).
- 🚧 Privacy policy/terms of use content and publication (§15) — explicitly not this document's to
  write.
- 🚧 Order-path unification vs. explicit retirement of one path (§17, 9D).
- Whether payment-gateway integration is in scope for the first public release at all, or deferred.
- Whether any real marketplace integration ships alongside the first public release, or is deferred
  entirely to a later phase (affects whether §14's webhook-signature gate is live-relevant yet).
- The Firestore-rules-vs-Postgres-RLS tradeoff named in §4 remains a real, if currently second-order,
  risk to watch during 9C's actual implementation — not resolved by this document, only flagged with a
  concrete fallback.
- No hands-on technical spike exists for either Firebase or Supabase against this app's specific
  workload (ADR-005's own stated limitation, still true) — a real risk this document does not resolve.
- Tenant-scoped restore remains genuinely unsolved past "all-or-nothing" through the pilot and early-
  public stages (§16) — named, not hidden.

## 22. Final Recommendation

**PROCEED WITH PROPOSED PHASE 9 — CONDITIONAL** on the three 🚧-flagged business decisions in §17 (9A-3)
being addressed before the sprints that depend on them (9D, 9G) begin; 9A/9B/9C can start immediately
once this document is reviewed and the dependency approvals in 9A-2 are granted individually.

Justification: the backend-platform decision is not actually open (ADR-005 stands, reaffirmed by this
pass, not overturned); the domain/application layer built across Phases 1–8 is unusually
migration-ready (184 real repository interfaces already behind Riverpod seams, a proven
Development/ProductionUnavailable swap pattern already demonstrated three times, a strong idempotency
culture already established, 2136 tests as a regression safety net); and the one genuinely
architecture-level surprise this analysis surfaced — the forked order-creation path — is real but
narrow enough to fix in one dedicated sprint (9D) rather than requiring a wholesale redesign. Nothing
found in this analysis rises to **REVISE PHASE 9 BEFORE IMPLEMENTATION** or **BLOCKED — BUSINESS
DECISION REQUIRED** at the whole-phase level — only three specific, named, containable decisions do.
