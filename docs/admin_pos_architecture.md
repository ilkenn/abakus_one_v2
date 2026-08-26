# Admin/POS Architecture — Foundation

**Status**: CANONICAL. Established AP-1 (2026-08-26), documentation-only phase. This is the primary
entry point for all Admin/POS architecture — every other AP-1 document cross-references this one for
identity, scope, device, and command/audit primitives rather than restating them.

## 1. Purpose

Defines the foundational architecture every Admin/POS document and future implementation phase builds
on: canonical tenant/branch context resolution, identity/role/permission separation, trusted-device
registration, staff operational sessions, remote-approval orchestration, the command/read-model split,
idempotency/concurrency discipline, error taxonomy, and the shared visual language across customer app,
POS, and Admin. Written directly against the evidence gathered in the AP-0 Current-State Audit
(2026-08-26) — every "current state" claim below is evidence-backed, not assumed.

## 2. Scope / Non-scope

**In scope**: Admin shell architecture, POS shell architecture, organization/restaurant/branch context
resolution, identity/role/permission model, trusted-device model, staff operational session model,
remote-approval orchestration primitive (used by Docs B/C/D/E, not redefined there), audit model,
command/read-model separation, idempotency/concurrency rules, error taxonomy, shared design-token
authority, and the requirements traceability matrix for every AP-1 locked decision.

**Out of scope** (owned by other AP-1 documents, cross-referenced not restated here): table/check/order
operations (Doc B), payment/cash/fiscal (Doc C), KDS/printer/stock (Doc D), staff shift/reservation/
courier/marketplace/CRM/reporting (Doc E), SaaS/entitlement/offline/observability (Doc F). This document
does not describe customer-facing order submission, Campaign/Loyalty/Reward mechanics (already CLOSED
and audited separately — see `docs/decisions.md`'s Campaign/Loyalty entries), or any implementation code.

## 3. Authority / Supersedes / Related Documents

**Canonical authority order** (corrected per AP-1 Stage B approval — this order is now itself locked and
must not be silently re-ordered by any future document, including this one):

1. `ENGINEERING_CONSTITUTION.md` — highest authority, implementation-independent engineering judgment.
2. Approved product/business requirements and `docs/business_rules.md` — locked business rules.
3. Approved ADRs in `docs/decisions.md` — architecture/data-model/security decisions.
4. **The six AP-1 canonical Admin/POS architecture documents** (this document + Docs B–F) — implementation
   architecture for Admin/POS specifically.
5. `docs/module_catalog.md` and `docs/master_roadmap.md` — scope/backlog/prioritization authority, not
   implementation detail.
6. `CLAUDE.md` and `.claude/agents/*.md` — working method/tooling authority for whichever agent picks up
   implementation work; these files direct *how* an agent works, never *what* is architecturally true.

**`CLAUDE.md` or any `.claude/agents/*.md` persona can never override a product rule, an ADR, or a
canonical architecture decision in this document set.** Where a working-method document's own text
appears to conflict with something ranked above it (several were found stale during AP-0 — see §4 and
`docs/decisions.md`'s AP-1 governance-sync ADR), the conflict is resolved by this authority order
explicitly, in writing, in the lower-ranked document itself — never by silent precedence.

**Supersedes**: `docs/table_qr_architecture.md` and `docs/order_lifecycle_architecture.md` for any
Admin/POS-relevant content (both remain HISTORICAL for their own original customer-side scope; see
Doc B §Supersession). Does not supersede `docs/firestore_data_model.md`, which remains canonical for
the customer-side schema this document's Firestore section extends rather than replaces.

**Related documents**: `docs/order_operations_architecture.md` (Doc B), `docs/payment_cash_fiscal_architecture.md`
(Doc C), `docs/kds_printer_stock_architecture.md` (Doc D), `docs/restaurant_operations_architecture.md`
(Doc E), `docs/saas_offline_observability_architecture.md` (Doc F), `docs/firestore_data_model.md`,
`docs/business_rules.md`, `docs/decisions.md`.

## 4. Current-State Evidence (AP-0, 2026-08-26)

Cited directly from the AP-0 audit, not re-derived. Every claim below has a file-level evidence trail in
`docs/decisions.md`'s AP-0 entry.

- A real, reachable `AdminShellScreen` exists (18 sections, 5 groups), reached via `StaffSignInScreen`
  and a Profile "İşletme Moduna Geç" card — but is not registered in `go_router`, and most of its data
  providers are hardcoded (`organizationId: 'org-1'`) in-memory placeholders.
- `lib/features/pos/**` contains a large, well-tested domain/application layer (cash sessions/drawers/
  movements/reconciliation, payment sessions/splits/voids, checks with split-by-item/split-by-quantity/
  merge/transfer, KDS work-item tracking, discount presets, printer-retry scaffolding) — entirely
  in-memory, zero Firestore backing, and its screens (`PosCashierScreen`, `TableSessionScreen`,
  `KitchenDisplayBoardScreen`) are either fully orphaned or reachable only through the Admin shell with
  no real backend underneath.
- `functions/src/{provisionOrganization,provisionRestaurant,provisionBranch}.ts` and
  `functions/src/{staffMembership,staffAuthorization}.ts` are real, tested, and correctly enforce
  tenant/branch chain integrity and role→permission separation — but are **emulator-verified only, never
  deployed to a real Firebase project**, and have **zero Flutter callers**: the Admin UI's own staff
  roster-management screens write to a disconnected `InMemoryStaffMemberRepository` instead.
- `functions/src/{advanceTakeawayOrderStatus,advanceDeliveryOrderStatus,advanceDineInOrderStatus,
  advanceReservationPreorderOrderStatus}.ts` are real, tested, server-authoritative — and have zero
  Flutter callers anywhere. No UI path today moves a canonical `Order.status` into `preparing`/`ready`.
- No trusted-device model exists at all, not even a stub.
- No per-customer table sub-account concept exists; a `Check` only tags `guestSessionIds`.
- No mandatory guest-name-entry exists before a QR order.
- Order approval is real and server-authoritative but whole-order only; no per-product accept/reject, no
  counter-proposal mechanism for a plain order (`respondToProposedChange.ts` is reservation-scoped only).
- Refund Cloud Functions certify that a refund happened externally; they never move money, are
  full-refund-only, and have no mixed-payment-instrument split logic. Every payment provider adapter is
  an honest `NoOp` stub.
- Fiscal device (YN ÖKC/GMP-3/PAX A910SF) integration is a confirmed total absence — no code, stub,
  interface, domain model, or dependency anywhere.
- Printer/ESC-POS integration is a confirmed total absence.
- Stock consumption is explicitly documented in its own source as unwired: no menu product currently
  references a recipe id.
- Courier and staff-facing CRM are both extensive, tested, UI-reachable, and both 100% in-memory.
- Marketplace is domain-model-only, not wired to any UI screen.
- `lib/features/entitlements/**` has a real, reachable Admin screen and a `firestore.rules` stub denying
  client writes — but no Cloud Function ever grants an entitlement.
- No production Firebase deployment has occurred for any environment.

## 5. Target Architecture

The command/authorization/audit shape every AP-1 document assumes, restated once here:

```
Client (Admin/POS Flutter app)
  │  sends an intent/command (never a state mutation)
  ▼
Trusted backend (Cloud Function, onCall)
  │  1. Resolves real identity from the Firebase Auth token (never client-asserted)
  │  2. Resolves tenant/branch/device context server-side (never client-asserted)
  │  3. Checks permission (derived from role) + device capability (where device-restricted)
  │  4. Validates price/discount/state-transition legality against the canonical aggregate
  │  5. Applies the mutation inside a transaction, with idempotency-key deduplication
  │  6. Writes an audit event in the SAME transaction
  ▼
Canonical Firestore aggregate (source of truth)
  │  read-only live stream
  ▼
Client read model (real-time UI, never itself authoritative)
```

No client ever writes a business-critical collection directly. This is not a new principle — it is the
exact shape `submitDineInOrder.ts`/`orderLifecycle.ts` already implement correctly for customer orders;
this document generalizes it to every Admin/POS domain that currently lacks it.

## 6. Domain Terminology

- **Organization**: the tenant root. One Abaküs customer (a restaurant group) = one organization.
- **Restaurant**: a named brand/concept under an organization (an organization may run more than one).
- **Branch**: a physical location under a restaurant. The unit staff/devices/policies are scoped to.
- **Staff member**: a registered person with one or more roles, each carrying `organizationAccess`/
  `branchAccess`.
- **Actor**: whoever is asserting an intent — either a staff member (via a `StaffOperationalSession`) or,
  for customer-facing flows, a customer/guest identity (defined in `docs/firestore_data_model.md`,
  unchanged by this document).
- **Device**: a physical piece of hardware (tablet, terminal, printer controller) that may be
  device-restricted for certain operational modes — see §12.
- **Command**: a client-issued intent, always via a Cloud Function `onCall`, never a direct write.
- **Read model**: whatever the client observes via a live Firestore query — always a projection of the
  canonical aggregate, never itself authoritative.
- **Canonical aggregate**: the one Firestore document/collection a domain's Cloud Functions treat as the
  source of truth (e.g. `orders/{orderId}` for order state).

## 7. Entities / Value Objects (foundation-level; domain-specific entities live in Docs B–F)

- `Organization { organizationId, isActive, createdAt }`
- `Restaurant { restaurantId, organizationId, name, ... }`
- `Branch { branchId, restaurantId, organizationId, name, timezone, ... }` — **`timezone` is required on
  every branch**; every business-day/schedule computation in every AP-1 document resolves against this
  field, never a hardcoded or client-supplied timezone (see §14).
- `Membership { membershipId = "{organizationId}_{uid}", uid, organizationId, roles: Set<Role>,
  branchAccess: Set<branchId>, status }`
- `StaffOperationalSession { actorUid, organizationId, activeBranchId, roles, branchAccess, deviceId,
  deviceSessionId, issuedAt, expiresAt, revoked }` — see §13.
- `TrustedDeviceRegistration { deviceId, organizationId, branchId, capabilities: Set<DeviceCapability>,
  status: DeviceStatus, registeredBy, activatedAt, lastSeenAt, revokedAt, revokedReason }` — see §12.
- `RemoteApprovalRequest { requestId, organizationId, branchId, requestedByActorUid, actionType,
  targetAggregateRef, targetAggregateVersion, payload, status: ApprovalStatus, respondedByActorUid,
  respondedAt, escalatedTo, expiresAt }` — see §16 and Doc E for concrete `actionType` usages.
- `AuditEvent { organizationId, branchId, type, targetRef, previousValue, newValue, actor, actorType,
  actorUid, actorRoles, reasonCode, reasonMessage, timestamp }` — the schema `orderLifecycle.ts`'s real
  `auditEvents` collection already uses; every AP-1 domain's audit trail extends this shape, never
  invents a parallel one (closing the AP-0-found "two disconnected audit systems" gap).

## 8. State Machines (foundation-level)

**`DeviceStatus`**: `pending → active → suspended → active` (reinstated) `| revoked | retired`.
`suspended`/`revoked`/`retired` are entered only by a server-authoritative action (§12); `pending →
active` requires manager/Admin/Platform Owner authorization server-side.

**`ApprovalStatus`**: `pending → approved | rejected | expired | escalated → (new pending, new approver)
| cancelled`. See §16 for the full orchestration.

Domain-specific state machines (order status, check status, cash session status, etc.) are owned by
Docs B–D and cross-referenced, not redefined here.

## 9. Commands / Queries / Events (naming convention)

- **Commands** are named `<Verb><Noun>` (e.g. `RegisterTrustedDevice`, `RequestRemoteApproval`,
  `RespondToRemoteApproval`), always implemented as an `onCall` Cloud Function, always idempotent via a
  caller-supplied idempotency key or a deterministic derived id.
- **Queries** are always a direct client Firestore read against a rules-scoped collection, never a
  callable — matching the existing, correct pattern for customer-facing reads.
- **Events** are `AuditEvent` documents (§7), written inside the same transaction as the command that
  caused them, never a separate best-effort write.

## 10. Trust Boundaries

- The client is never trusted for: identity (beyond "which Firebase Auth session is this"),
  `organizationId`/`branchId`/`restaurantId`, role, permission, device identity/capability, price,
  discount, payment result, refund result, fiscal result, or any state-transition legality check.
- Every one of the above is independently resolved or verified server-side before a command is applied,
  exactly as `submitDineInOrder.ts`/`assignReservationTable.ts`/`staffMembership.ts` already do
  correctly today — those files are the reference implementation this document generalizes, not a
  pattern being invented fresh.
- App Check (where enabled) is defense-in-depth only — it proves "a genuine build of this app called
  this endpoint," never "this specific device is authorized for this specific operational mode." Device
  trust (§12) is a separate, additional layer.

## 11. Tenant/Branch Invariants — Firestore Structure Lock

**The existing flat, top-level Firestore collection structure is preserved as the default.** No
organization/branch subcollection nesting transformation is performed by this document or by any AP-1
document. `docs/firestore_data_model.md`'s existing collection shapes (`orders`, `reservations`,
`memberships`, etc. — flat top-level collections, each carrying a denormalized `organizationId`) remain
the pattern every new Admin/POS collection follows.

Every new business-object collection introduced by any AP-1 document (checks, cash sessions, payment
sessions, KDS work items, trusted device registrations, approval requests, stock movements, etc.) **must
carry and have server-verified**:

- `organizationId` — always.
- `restaurantId` — where the object is restaurant-scoped (e.g. a menu/recipe definition).
- `branchId` — always, where the object is branch-operational (nearly everything POS/KDS/cash touches).

This chain is verified server-side using the exact pattern `provisionBranch.ts`/`requireBranchAccess`
already establish (read the parent, verify the binding, never trust a client-asserted id alone) — no new
verification mechanism is invented.

**A future organization/branch subcollection restructuring is explicitly out of scope for AP-1 through
AP-8** and may only be proposed via its own dedicated analysis, migration plan, and new ADR — never as a
side effect of any Admin/POS feature work.

## 12. Device Requirements — Trusted Device Model

Closes the AP-0-found "no trusted device model at all" gap. Locked target model:

- A `TrustedDeviceRegistration` is **organization- and branch-scoped** — a device is registered against
  one specific branch, not globally.
- A device carries an explicit `capabilities: Set<DeviceCapability>` — at minimum `POS`, `KDS`,
  `PRINTER_CONTROLLER`. A device with only `KDS` cannot act as a POS terminal even if a valid staff
  session is present.
- `DeviceStatus` (§8): `pending`, `active`, `suspended`, `revoked`, `retired` — at minimum these five.
- **Activation is server-authoritative**, gated on manager/Admin/Platform Owner authorization — a device
  never self-activates.
- **Device identity is never accepted as a client assertion.** On platforms where it's available,
  activation and every device-restricted command binds to a hardware-backed, non-exportable key with
  proof-of-possession (the device signs a server-issued challenge; the server never accepts a bare device
  id string as proof). Where the target platform (Android/iOS tablet, or a dedicated POS terminal like
  PAX A910SF) does not expose a hardware-backed key API, this is recorded as a
  `CONTROLLED_EXTERNAL_DEPENDENCY` (§21) rather than inventing an unverified substitute.
- **App Check is not device trust** — it is one defense-in-depth layer among several (§10), never treated
  as sufficient on its own for a device-restricted operational mode.
- **A lost/compromised device is revoked remotely** — `active → revoked`, immediately invalidating that
  device's session-issuing capability; any `StaffOperationalSession` bound to a revoked device is
  invalidated on its next server round-trip (not necessarily instantly, matching the accepted
  "revocation is enforced going forward, not live-pushed into an already-running client" limitation
  already documented elsewhere in this codebase for staff session revocation).
- **A device-restricted command requires BOTH** a valid `StaffOperationalSession` (staff permission) AND
  a valid, `active` `TrustedDeviceRegistration` with the required capability — neither is sufficient
  alone.
- **Platform Owner identity does not bypass device restriction.** A Platform Owner acting in a
  device-restricted operational mode (POS/KDS) still requires an `active` trusted device exactly like
  any other actor — platform-level authority is a separate axis from device trust, never a substitute
  for it.
- **Offline operation is only possible via a signed, backend-issued offline lease** — a
  short-lived, scope-limited credential (specific device, specific capabilities, explicit expiry) issued
  while online, never a standing/unlimited offline capability. See Doc F §Offline for the full lease/
  replay/reconciliation design; this document only locks the principle.
- No specific platform API (Android StrongBox/Keystore, iOS Secure Enclave, a specific PAX SDK call) is
  named here without vendor documentation in hand — see §21 for how these are tracked instead.

## 13. Staff Operational Session

A `StaffOperationalSession` (§7) is minted server-side after a successful `FirebaseStaffAuthRepository`
sign-in (already real, per AP-0 §4), extended to additionally require, for any device-restricted
operational mode, a bound `deviceId`/`deviceSessionId` referencing an `active` `TrustedDeviceRegistration`
(§12). A session with no device binding may still be used for non-device-restricted Admin actions (e.g.
viewing reports), but never for POS/KDS commands.

## 14. Policy/Configuration Resolution & Business Day/Branch Timezone

Every AP-1 document's policy/configuration objects (discount presets, approval-timeout durations, KDS
routing rules, cash-count tolerances, etc.) are resolved **per organization, with an optional branch
override** — organization-level default, branch-level override where one exists, exactly mirroring the
existing `ChannelPricingPolicy`/`ReservationPolicy` pattern already proven in this codebase. No new
resolution mechanism is invented.

**Business day** boundaries (used by cash end-of-day, reporting cutoffs, and shift scheduling in Docs C/E)
are computed against `Branch.timezone` (§7), server-side, always — never the client's local clock, and
never a hardcoded UTC assumption. A branch without a configured timezone fails closed (no business-day
computation proceeds) rather than defaulting silently.

## 15. Audit Model

Every AP-1 command writes an `AuditEvent` (§7) in the same transaction as its mutation — generalizing
`orderLifecycle.ts`'s real, already-correct pattern to every domain. The AP-0-found "two disconnected
audit systems" (real `auditEvents` vs. in-memory `OrderAuditEntry`/`RestaurantOperationsAuditEntry`/
`KitchenAuditEntry`/`AdminAuditEntry`) are consolidated: every in-memory audit model found in AP-0 is
either (a) replaced by a write to the real `auditEvents` collection once its owning domain gets a real
backend (Docs B–F specify this per-domain), or (b) if a genuinely UI-session-local, non-durable notion
remains useful, kept explicitly labeled as such and never presented as an audit trail.

## 16. Remote Approval Orchestration (shared primitive — used by Docs B, C, E; not redefined there)

Closes the AP-0-found "no manual manager adjustment / no escalation" gap. Locked target model:

- Remote approval is **synchronous, blocking, and fail-closed**. The requesting command creates a
  `RemoteApprovalRequest` (§7) and the underlying mutation **does not apply** until a matching `approved`
  response is recorded.
- **Self-approval is structurally forbidden** — the server rejects a response where
  `respondedByActorUid == requestedByActorUid`, mirroring the exact pattern `staffMembership.ts` already
  uses for role self-promotion.
- **Timeout escalation**: if the designated approver does not respond within a configured window, the
  request escalates to another eligible manager/Admin at the same branch/organization; the final
  escalation tier is the Platform Owner. Escalation is itself an `AuditEvent`.
- **Platform Owner escalation does not bypass device restriction** (§12) — if the underlying action is
  device-restricted, the Platform Owner's own approval action is still subject to the same device-trust
  requirement as any other actor.
- **No double-approval**: a `RemoteApprovalRequest` transitions `pending → {approved|rejected|expired}`
  exactly once; a second response to an already-resolved request is rejected, idempotently, not silently
  ignored or double-applied.
- **Stale-target rejection**: if the target aggregate's version (`targetAggregateVersion`, §7) has
  changed since the request was created, the approval is rejected as stale rather than applied against
  outdated state — an optimistic-concurrency check, not a soft warning.
- **Approve/reject/timeout/escalate/cancel are five distinct `AuditEvent` types**, never collapsed into
  one generic "approval changed" event.
- **No connectivity, no remote approval** — an action requiring remote approval cannot proceed at all
  while offline; this is a deliberate fail-closed choice, distinct from the narrower offline-lease
  exception (§12) for connectivity-verified cash/fiscal sales specifically (Doc C owns that exception's
  exact scope).
- **Usages already identified** (owned/detailed by their respective documents, this primitive is shared
  across all of them): comp/discount beyond a bounded preset, post-acceptance cancellation, manual
  Boncuk/campaign-adjacent adjustment (kept structurally separate from automatic campaign/reward
  eligibility per Doc B), stock-count variance acceptance, cash-reconciliation variance acceptance,
  controlled manual cash movements.

## 17. Command/Read-Model Separation & Idempotency/Concurrency

- Every mutating Admin/POS operation is a Cloud Function command; every Admin/POS read is a direct,
  rules-scoped Firestore query — no exceptions, matching §5's target shape.
- Every command carries either a caller-supplied idempotency key or is itself deterministic (a stable
  derived document id), and every command's Cloud Function checks for a prior identical execution before
  applying a mutation — generalizing the exact pattern already proven correct in
  `submitDineInOrder.ts`'s fingerprint-mismatch-fails-closed design.
- Every command that mutates an existing aggregate reads that aggregate's current version/state inside
  the same transaction it writes in (optimistic concurrency), never applies a blind write.

## 18. Error Taxonomy

Every Admin/POS Cloud Function error maps to one of: `unauthenticated`, `permission-denied` (role or
device), `failed-precondition` (state/version mismatch), `not-found`, `already-exists` (idempotent replay
of a completed command), `resource-exhausted` (rate/quota), `unavailable` (transient), or `internal`
(unexpected). No new bespoke error-code vocabulary is invented per feature — every Doc B–F command uses
this same taxonomy, mapped to Turkish user-facing text via the existing `ErrorMapper` pattern client-side.

## 19. Design System & Responsive Platform Rules — Abaküs Visual Language Lock

**Live authority for all Flutter UI, customer app and Admin/POS alike, is exclusively
`lib/core/theme/*`** (`AppColors`, `AppTypography`, `AppSpacing`, `AppRadius`, `AppShadows`, `AppTheme`),
consistent with `CLAUDE.md` §6's existing rule, now corrected there to state this explicitly (see
governance sync). **`brand-production/00_docs/Abakus-One_Design-Bible_v1.0.md` is explicitly excluded
from this authority chain** — it is a physical-hardware industrial-design specification for a literal
abacus object, unrelated to Flutter UI, and must never be cited as a source for app visual decisions.

**Locked Abaküs visual language**, binding on customer app, POS, and Admin equally — the same brand DNA
across all three surfaces, expressed through Material 3 and the central token set only:

- Warm, open cream/off-white backgrounds — never stark white, never dark-mode-by-default.
- Sage/olive/deep "Abaküs green" as the primary brand color family.
- Natural, warm accent tones (never neon, never a cold/clinical SaaS blue-purple palette).
- Soft, restrained shadows — depth communicated through elevation tokens, never harsh drop-shadows.
- Wide, generously rounded cards — no sharp-cornered "dense dashboard" boxes.
- Deliberate whitespace and strong typographic readability over information density for its own sake.
- **Forbidden**: neon accents, gratuitous gradients, and any "generic off-the-shelf admin dashboard"
  visual signature (dense gray sidebars, default Material blue, stock icon-only nav rails with no brand
  warmth).
- **POS layout convention**: dark Abaküs-green left operational-navigation rail, cream/off-white main
  working surface, center product/catalog area, right-hand cart/customer/payment panel.
- **Admin layout convention**: dense-but-calm premium-SaaS information hierarchy — density is
  acceptable in Admin specifically (a manager scanning many rows/metrics), but never at the cost of the
  same warm palette and rounded-card language used everywhere else; Admin must never visually read as a
  generic off-the-shelf dashboard template.
- **No ad hoc one-off design tokens** — every color/spacing/radius/typography/shadow value used anywhere
  in POS or Admin resolves through the central token classes; a screen-local hardcoded value is a
  documented exception only where `CLAUDE.md` §6's existing decorative-artwork exception applies (a
  mascot/hero-graphic color, never a reusable UI surface color), exactly as already governs the customer
  app.
- **Accessibility/responsive requirements, POS and Admin equally**: WCAG AA contrast on every text/icon
  against its background token; every interactive control keyboard-navigable with a visible focus state
  (Admin runs on desktop/tablet browsers and physical keyboards far more than the customer app does);
  minimum touch-target size preserved even in Admin's denser information layout; responsive behavior
  across the phone/tablet/desktop breakpoints the existing customer app already establishes, extended
  (not redefined) for POS's typically-tablet and Admin's typically-desktop primary form factors.

## 20. Existing-Code Reuse/Migration Map (foundation-level; domain-specific maps live in Docs B–F)

| Component | Decision | Notes |
|---|---|---|
| `lib/features/admin/presentation/screens/admin_shell_screen.dart` | EXTEND | Register into `go_router`; keep the 18-section/5-group structure. |
| `lib/features/admin/presentation/providers/admin_dependencies_provider.dart` | REPLACE (data layer only) | Replace hardcoded `'org-1'`/`InMemory*` providers with real context-resolution + Firestore-backed repositories; keep the provider *interface* shapes. |
| `functions/src/{provisionOrganization,provisionRestaurant,provisionBranch}.ts` | REUSE_AS_IS | Correct design; needs a real Flutter caller and real deployment, not a rewrite. |
| `functions/src/{staffMembership,staffAuthorization}.ts` | REUSE_AS_IS (backend) | The Dart client-side roster-management screens must be REPLACED (rewired to call these, not rebuilt against new backend logic). |
| `lib/features/admin/data/staff_auth_repository.dart` (`FirebaseStaffAuthRepository`) | REUSE_AS_IS | Already correctly connected; extend with device-session binding (§13) only. |
| `lib/features/admin/domain/device/{admin_device_registration,device_registry_entry}.dart` | EXTEND | Real device *inventory* today; extend into the real `TrustedDeviceRegistration` (§12), do not discard. |
| `.claude/agents/security_engineer.md`'s NoOp payment-adapter finding | STILL ACCURATE | Not superseded by this document; Doc C owns the payment-adapter reuse decision. |

## 21. Controlled External Dependencies (foundation-level)

| Dependency | Owner | Required document | Blocks | Verification method | Acceptance gate |
|---|---|---|---|---|---|
| Hardware-backed key/proof-of-possession API per target platform (Android Keystore/StrongBox, iOS Secure Enclave, PAX SDK) | Platform vendor (Google/Apple/PAX) | Official platform security documentation | §12 device-identity binding's exact implementation | Read official vendor docs before writing any platform-specific code | A real device successfully activates and is proof-of-possession-verified in a non-production environment |
| PAX A910SF SDK / integration documentation | PAX Technology | Official PAX SDK docs, obtained via vendor relationship | Any concrete `TrustedDeviceRegistration` implementation for that hardware, Doc C's fiscal integration | Vendor doc review + vendor-provided test hardware | Doc C's own acceptance gates (real device tests, not simulated) |

## 22. Non-Goals

This document does not: implement any code; choose a specific payment/fiscal vendor; restructure
Firestore's flat collection model (§11); redesign the customer-facing app (frozen per the Customer Side
Closure Audit); resolve marketplace connector implementation (Doc E owns the ADR-025 supersession and
implementation scope); or declare any Critical/High architectural ambiguity resolved that isn't
genuinely resolved by evidence or an explicit locked decision.

## Appendix — Requirements Traceability Matrix

Every AP-1 locked decision, traced to its Business Rule ID, ADR ID, owning document/section,
implementation phase, and current status. No locked requirement is left without an owner.

| Locked requirement | Business Rule ID | ADR ID | Owner document/section | Implementation phase | Current status |
|---|---|---|---|---|---|
| Per-customer table sub-account, mandatory in first POS release | BR-SUBACCOUNT-001 | ADR-028 | Doc B §Table/Check/SubAccount | AP-3 | NOT_FOUND in source (AP-0) — architecture locked this phase |
| Guest must enter name before ordering | BR-SUBACCOUNT-002 | ADR-028 | Doc B §Guest Identity | AP-3 | NOT_FOUND in source (AP-0) — architecture locked this phase |
| Authenticated customer's submissions link to canonical `customerId` | BR-SUBACCOUNT-003 | ADR-028 | Doc B §Guest Identity | AP-3 | Partially real (canonical `customerId` exists); linkage to sub-account is new |
| Staff-created anonymous/general table lines held in a separate staff-created sub-account | BR-SUBACCOUNT-004 | ADR-028 | Doc B §Table/Check/SubAccount | AP-3 | NOT_FOUND — new |
| Product line shows which sub-account ordered it | BR-SUBACCOUNT-005 | ADR-028 | Doc B §Table/Check/SubAccount | AP-3 | NOT_FOUND — new |
| Boncuk usable only against the owning sub-account's own eligible amount | BR-SUBACCOUNT-006 / BR-LOYALTY-019 (cross-ref) | ADR-028 | Doc B §Benefit Application | AP-3 | Loyalty mechanics real (customer-side, CLOSED); sub-account scoping is new |
| Split by product/quantity, customer, headcount, free amount; merge; table transfer, all audited | BR-TABLE-009 | ADR-028 | Doc B §Split/Merge/Transfer | AP-3 | Product/quantity split + merge + transfer: real in-memory (AP-0); customer/headcount/free-amount split, real backend, and audit: new |
| Every QR submission awaits cashier approval before kitchen prep | BR-ORDER-015 | ADR-029 | Doc B §QR Approval | AP-3 | Real server-side (`submitDineInOrder`/`advanceDineInOrderStatus`), whole-order only |
| Line-level accept/reject | BR-ORDER-016 | ADR-029 | Doc B §QR Approval | AP-3 | NOT_FOUND — new |
| Cashier counter-proposal, customer must accept before it applies | BR-ORDER-017 | ADR-029 | Doc B §QR Approval | AP-3 | NOT_FOUND for orders (reservation-only mechanism exists) — new |
| Partial accept/reject tracked separately per submission | BR-ORDER-018 | ADR-029 | Doc B §QR Approval | AP-3 | NOT_FOUND — new |
| Trusted device required for POS/KDS operational modes, alongside staff permission | BR-DEVICE-001 | ADR-030 | Doc A §12 | AP-2 | NOT_FOUND — new |
| Device registration organization+branch scoped, explicit capabilities, 5-state lifecycle | BR-DEVICE-002 | ADR-030 | Doc A §12 | AP-2 | NOT_FOUND — new; real device *inventory* exists to extend |
| Device identity never client-asserted; hardware-backed proof-of-possession where available | BR-DEVICE-003 | ADR-030 | Doc A §12 | AP-2 | NOT_FOUND — `CONTROLLED_EXTERNAL_DEPENDENCY` |
| App Check is defense-in-depth only, not device trust | BR-DEVICE-004 | ADR-030 | Doc A §10, §12 | AP-2 | App Check exists (not enforced in prod); device trust does not exist |
| Remote device revocation | BR-DEVICE-005 | ADR-030 | Doc A §12 | AP-2 | NOT_FOUND — new |
| Offline operation only via signed, scope-limited backend-issued lease | BR-DEVICE-006 | ADR-030 | Doc A §12; Doc F §Offline | AP-2 / AP-4 | NOT_FOUND — new; nearest precedent is the orphaned courier-location offline queue |
| Remote approval synchronous, blocking, fail-closed | BR-APPROVAL-001 | ADR-031 | Doc A §16 | AP-2 | NOT_FOUND — new |
| Self-approval structurally forbidden | BR-APPROVAL-002 | ADR-031 | Doc A §16 | AP-2 | Pattern proven in `staffMembership.ts` for role self-promotion; not yet generalized |
| Timeout escalation to another manager, then Platform Owner | BR-APPROVAL-003 | ADR-031 | Doc A §16 | AP-2 | NOT_FOUND — new |
| Platform Owner cannot bypass device restriction | BR-APPROVAL-004 | ADR-031 | Doc A §12, §16 | AP-2 | NOT_FOUND — new |
| No double-approval; stale-target rejection | BR-APPROVAL-005 | ADR-031 | Doc A §16 | AP-2 | NOT_FOUND — new |
| Manual manager adjustment kept structurally separate from automatic Campaign/Boncuk/Reward eligibility | BR-APPROVAL-006 / BR-PROMO-008 (cross-ref) | ADR-031 | Doc B §Benefit Application | AP-3 | `adminAdjustment` ledger type reserved, zero writer (AP-0) — architecture locked this phase |
| YN ÖKC/GMP-3/PAX A910SF integration mandatory for first production POS | BR-FISCAL-001 | ADR-032 | Doc C §Fiscal | AP-4 | NOT_FOUND — total absence (AP-0); architecture only this phase, real implementation AP-4 |
| No fiscal/protocol detail invented without vendor documentation | BR-FISCAL-002 | ADR-032 | Doc C §Fiscal; Doc A §21 | AP-4 | Governance rule, effective immediately |
| Payment/fiscal result never client-asserted | BR-FISCAL-003 | ADR-032 | Doc A §10; Doc C §Fiscal | AP-4 | Pattern proven for order pricing; not yet extended to payment/fiscal |
| Timeout does not auto-fail; enters a controlled unknown/reconciliation state | BR-FISCAL-004 | ADR-032 | Doc C §Fiscal | AP-4 | NOT_FOUND — new |
| Full and partial (product/quantity) refund, provider-executed where available | BR-REFUND-009 | ADR-033 | Doc C §Refund | AP-4 | Full refund real (certification-only); partial exists as an unwired domain model (`RefundCalculator`, AP-0) |
| Mixed-payment refund apportioned per instrument, deterministic rounding | BR-REFUND-010 | ADR-033 | Doc C §Refund | AP-4 | NOT_FOUND — new |
| Double refund prevented; partial success/retry/reconciliation modeled | BR-REFUND-011 | ADR-033 | Doc C §Refund | AP-4 | NOT_FOUND — new |
| No second/parallel customer identity for staff-facing CRM | BR-CRM-011 | ADR-034 | Doc E §CRM | AP-7 | Staff-facing CRM currently has its own disconnected in-memory `Customer` entity (AP-0) — must migrate to canonical identity |
| Staff-only CRM extensions (notes/segments/risk flags/restrictions/support/consent) remain tenant-scoped, layered on canonical identity | BR-CRM-012 | ADR-034 | Doc E §CRM | AP-7 | Real, reachable UI exists (AP-0); backend + canonical-identity linkage is new |
| Marketplace deferral (ADR-025) superseded; real connector implementation in scope | BR-MKT-005 | ADR-035 (supersedes ADR-025) | Doc E §Marketplace | AP-6 | Domain-model-only today (AP-0); architecture + supersession this phase, implementation AP-6 |
| Connector distribution: `GLOBAL_CATALOG` / `TENANT_PRIVATE` | BR-MKT-006 | ADR-035 | Doc E §Marketplace | AP-6 | NOT_FOUND — new |
| Connector development/publishing restricted to the Abaküs team | BR-MKT-007 | ADR-035 | Doc E §Marketplace | AP-6 | NOT_FOUND — new |
| Courier fraud detection migrated into canonical `core/fraud` | BR-COURIER-055 | ADR-035 | Doc E §Courier | AP-6 | Currently a separate, unmigrated implementation (AP-0) |
