# SaaS, Offline & Observability Architecture

**Status**: CANONICAL. Established AP-1 (2026-08-26).

## 1. Purpose

Defines module entitlement granting, contract/grace-period/white-label scope, Platform Owner controls,
connector licensing (cross-referencing Doc E §9), the POS offline queue/signed-lease/replay design,
integration/device/printer health observability, incident management, backup/DR, and the closing scope
notes for Web Ordering, Community, and AI Manager. Also defines the canary → second-tenant → GA rollout
gate sequence.

## 2. Scope / Non-scope

**In scope**: the domains above. **Out of scope**: identity/device (Doc A), order/payment/KDS domain
entitlement *checks* (owned by their respective documents; this document owns the *granting* backend
those checks read from).

## 3. Authority / Supersedes / Related Documents

Per Doc A §3. Related: Doc A (device offline lease, §12), Doc E §9 (connector distribution model, this
document's entitlement layer gates `TENANT_PRIVATE` connector activation), `docs/business_rules.md`
(BR-PLATFORM entries).

## 4. Current-State Evidence

- `lib/features/entitlements/**` is real and reachable (`EntitlementAdminScreen`, wired into the Admin
  shell), with a real `firestore.rules` stub (`allow write: if false`) for the `entitlements`
  collection — but **no Cloud Function anywhere ever writes to it**; the rule is currently a dead end
  with no legitimate writer (AP-0).
- `EntitlementGrant.status` today models only `trial/active/expired/revoked` — **no grace-period status
  exists** (AP-0).
- **No `whiteLabel` field or concept exists anywhere in the entitlements module** (AP-0).
- No general POS-wide offline queue exists; the only offline-queue pattern in the codebase is
  courier-location-specific (`sync_queued_courier_locations.dart`), and even that has zero wired trigger
  — the provider is defined but consumed by nothing (AP-0).
- Crash reporting is genuinely, conditionally live (`FirebaseCrashlyticsService`, gated on
  `firebaseReadyProvider`) — contradicting a stale claim in `docs/observability_and_operations.md` that
  it's always `NoOp` (AP-0).
- Correlation IDs, a diagnostics dashboard, incident records, device health, and integration health are
  all confirmed `NOT_FOUND` (AP-0).
- Web Ordering: confirmed `NOT_FOUND` beyond an unconfigured default Flutter web build target (AP-0).
- Community: confirmed to be a static, non-interactive "Yakında" (Coming Soon) Home-screen card with zero
  backing feature/data; a LOCKED privacy rule for a future Community feature already exists in `docs/
  decisions.md` with nothing to attach to yet (AP-0).
- AI Manager: confirmed `NOT_FOUND` — only a dormant, uncalled translation-provider interface stub and a
  placeholder entitlement enum value exist (AP-0).
- No production Firebase deployment has occurred for any environment (AP-0).

**AP-2 update (2026-08-27, append-only — corrects the two entitlement bullets above, which were an
accurate AP-0 snapshot at the time but are now stale)**: `functions/src/entitlementAdmin.ts` now exists
— `grantEntitlement`/`renewEntitlement`/`suspendEntitlement`/`revokeEntitlement`, all
`requirePlatformMember`-gated, matching this section's own §9/§10 target design closely (a real writer
now stands behind the `entitlements` rule this document itself once called "a dead end"). `EntitlementStatus`
now carries the full `trial/active/grace/suspended/expired/revoked` set this section's own §7 target
design specified — `grace` is a real, fixed 72-hour window (`suspendEntitlement`'s
`GRACE_PERIOD_DAYS = 3`), automatically swept to `suspended` by `sweepExpiredEntitlementGracePeriods`.
`whiteLabel`/`ConfigureWhiteLabel` remain genuinely `NOT_FOUND`, unchanged by this pass — not silently
implied to exist by the entitlement-backend update above. `EntitlementAdminScreen` is now real-time-
read-only once Firebase is ready (no mutation control); the actual mutation console is new,
`lib/features/platform/presentation/screens/platform_entitlement_console_screen.dart`, matching §11's
"Platform-Owner-authority-gated, tenant Admin can never self-grant" rule exactly, server-side and
client-side both. Offline queue, observability, incident/backup/DR, and Web Ordering/Community/AI
Manager sections remain exactly as evidenced above — untouched by this pass.

## 5. Target Architecture

Per Doc A §5.

## 6. Domain Terminology

- **EntitlementGrant**: unchanged real concept, extended with a grace-period status.
- **OfflineLease**: the signed, scope-limited, backend-issued credential Doc A §12 references —
  fully specified here.
- **IncidentRecord**: a first-class, real record of an operational failure event, distinct from a raw
  crash/log entry.

## 7. Entities / Value Objects

- `EntitlementGrant { grantId, organizationId, moduleId, status: EntitlementStatus, startsAt, expiresAt,
  gracePeriodEndsAt?, contractTerm: {monthly|yearly|custom}, grantedBy }` — **`gracePeriodEndsAt`
  is new**, closing the AP-0-found gap.
- `WhiteLabelConfig { organizationId, brandName, logoRef, primaryColorOverride?, enabled: bool }` — **new
  entity**; **`primaryColorOverride` is deliberately the only visual override permitted, and only for the
  Admin/reporting surfaces a white-labeled tenant's own staff see** — it never overrides
  `lib/core/theme/*`'s token values for the shared Abaküs visual language (Doc A §19) in the customer app
  or in the base POS/Admin chrome; white-labeling is a narrow, explicitly bounded exception, not a
  general theming escape hatch.
- `OfflineLease { leaseId, deviceId, organizationId, branchId, capabilities: Set<DeviceCapability>,
  issuedAt, expiresAt, maxOfflineDurationMinutes }` — signed server-side at issuance; a device holds at
  most one active lease at a time.
- `IncidentRecord { incidentId, organizationId?, branchId?, severity: {critical|high|medium|low},
  category: {device|integration|printer|payment|fiscal|other}, detectedAt, resolvedAt?,
  relatedAuditEventRefs: [eventId] }`
- `DeviceHealthSnapshot { deviceId, lastSeenAt, connectivityStatus, printerStatus? }`
- `IntegrationHealthSnapshot { integrationId (payment provider / marketplace connector / fiscal), status,
  lastSuccessfulCallAt, lastFailureAt? }`

## 8. State Machines

**`EntitlementStatus`**: `trial → active → grace → suspended | expired → active(renewed) | revoked` —
extends the existing real four-state model with the missing `grace` state (between `active`/`expired`,
entered when a contract lapses but a configured grace window hasn't yet elapsed) and `suspended`
(administrative hold, distinct from `expired`).

**`OfflineLease` lifecycle**: `issued → active → expired | revoked(remote)`. A lease is never renewed
silently — a new lease requires a fresh online issuance, matching Doc A §12's "short-lived, scope-limited,
never a standing capability" principle exactly.

**`IncidentRecord.status`**: `open → investigating → resolved | wontFix`.

## 9. Commands / Queries / Events

- `GrantEntitlement`, `RenewEntitlement`, `SuspendEntitlement`, `RevokeEntitlement` — **new, real Cloud
  Functions closing the AP-0-found "rule with no writer" gap directly**; Platform-Owner/Admin-authorized
  per Doc A's platform-vs-tenant authority separation.
- `ConfigureWhiteLabel` (Platform Owner only).
- `IssueOfflineLease` (requires an online, authenticated, device-trusted request; Doc A §12),
  `RevokeOfflineLease`, `ReplayOfflineQueue` (client-triggered on reconnect, server processes queued
  commands through the exact same idempotency path every online command already uses — no parallel
  "offline sync" correctness model).
- `RecordIncident`, `ResolveIncident`, `RecordDeviceHealthPing`, `RecordIntegrationHealthCheck`.
- Every command writes an `AuditEvent` (Doc A §7/§15).

## 10. Trust Boundaries

Per Doc A §10. `EntitlementGrant`/`WhiteLabelConfig` mutations are Platform-Owner-authority-gated
specifically — a tenant Admin can never self-grant or self-extend their own organization's entitlement,
mirroring the self-approval-forbidden pattern used throughout Doc A §16.

## 11. Offline Queue / Signed Lease / Replay / Conflict Resolution

Generalizes Doc A §12's principle into a concrete design, and generalizes the existing real (but
orphaned-trigger) courier-location offline pattern (AP-0) rather than inventing a wholly new one:

- A device operating under a valid `OfflineLease` queues its outgoing commands locally.
- Each queued command already carries (per Doc A §17) its own idempotency key, generated at
  *capture* time (when the action was taken), never regenerated on replay — mirroring
  `sync_queued_courier_locations.dart`'s own correct "id assigned once at capture" pattern exactly.
- On reconnect, `ReplayOfflineQueue` submits every queued command **in capture order**; the server applies
  its normal idempotency/optimistic-concurrency checks (Doc A §17) — a command whose target aggregate has
  since changed incompatibly is rejected as a conflict, surfaced to staff for manual resolution, never
  silently dropped or silently forced.
- A lease's `maxOfflineDurationMinutes` is enforced server-side at replay time — commands captured after
  the lease's effective expiry are rejected, not replayed, even if the device's own clock disagreed.
- This mechanism is the same one Doc C §18 references for offline cash/fiscal sales — not a separate
  design for that specific case.

## 12. Integration / Device / Printer Health, Correlation IDs, Incident Records

- Every Cloud Function call is tagged with a correlation id (propagated from the client's own generated
  request id through to every resulting `AuditEvent`) — closing the AP-0-confirmed-absent gap directly.
- `DeviceHealthSnapshot`/`IntegrationHealthSnapshot` are populated by lightweight periodic pings/health
  checks from each device/adapter — surfaced on a real Admin diagnostics view (closing the
  AP-0-confirmed-absent "diagnostics dashboard" gap).
- An `IncidentRecord` is created automatically when a health check fails repeatedly past a configured
  threshold, or manually by staff — both paths converge on the same entity, never two parallel incident
  concepts.

## 13. Metrics / Logging / Error Tracking

Extends the existing real `LoggingService`/`LogRedactor`/`FirebaseCrashlyticsService` (all confirmed
genuinely live per AP-0) rather than replacing them — every new Admin/POS Cloud Function and Flutter
screen uses the same logging/redaction/crash-reporting seam already correctly established, never a
parallel logging mechanism.

## 14. Backup / Restore / Disaster Recovery

Extends `docs/deployment_and_operations.md`'s existing documented-but-unexecuted Firestore backup/PITR
intent — this document does not redesign that plan, it locks that real backup/PITR enablement as a
production-hardening (AP-8) prerequisite, cross-referenced not duplicated.

## 15. Web Ordering, Community, AI Manager — Scope Notes

- **Web Ordering**: confirmed non-existent (AP-0); this document does not design it — `docs/
  module_catalog.md`'s own `WEB-001` open architecture-fork decision (Flutter Web reusing the app
  codebase vs. a separate web admin stack) remains open, explicitly out of AP-1's scope to resolve.
- **Community**: remains the static "Yakında" placeholder (frozen per the Customer Side Closure Audit,
  unchanged by this document); the LOCKED privacy rule already recorded in `docs/decisions.md` for a
  future Community feature remains locked, with nothing further added here.
- **AI Manager**: scoped, this phase, as **read-only analysis/recommendation only** — e.g. a future
  AI-generated profitability insight or stock-reorder suggestion surfaced to a manager for their own
  decision, never an autonomous mutation. Any future AI capability that would *act* (not just recommend)
  requires its own explicit architecture decision and is out of scope here.

## 16. Production Quality / SLA Gates & Rollout Sequence

**"Hazır olduğunda tüm restoranlara açılsın" does not mean untested big-bang rollout.** The locked
rollout sequence:

1. **Abaküs canary** — the Abaküs team's own operating branch(es) run the real production system first,
   under real operational load, for a meaningful observation period.
2. **Second-tenant acceptance** — a second, independent tenant onboards and runs successfully, proving
   tenant isolation holds under genuine multi-tenant load (not just emulator rules tests).
3. **GA rollout** — only after both gates above pass, with SLA/incident-rate thresholds met and zero open
   Critical/High incidents, does general availability rollout to all restaurants proceed.

Each gate is a real, evidence-based checkpoint (real hardware acceptance per Doc C §21, real cross-device
courier/marketplace tests per Doc E §19, real backup/DR drill per §14) — not a calendar date.

## 17. Reuse/Migration Map

| Component | Decision | Notes |
|---|---|---|
| `lib/features/entitlements/**` | EXTEND | Real, reachable, correct gating logic; needs the granting Cloud Functions (§9) + grace-period status. |
| `firestore.rules`' `entitlements` collection rule | REUSE_AS_IS | Correct deny-all-writes rule; just needs a real writer behind it. |
| `lib/features/courier/application/use_cases/sync_queued_courier_locations.dart` | REUSE_AS_IS (pattern), EXTEND (wiring) | Correct idempotent-replay pattern; needs a real reconnect-triggered caller, generalized per §11. |
| `lib/core/services/crash_reporting/**`, `lib/core/services/logging/**` | REUSE_AS_IS | Already real and correctly wired; extend usage, don't replace. |

## 18. Test Strategy

Entitlement lifecycle tests cover every `EntitlementStatus` transition including `grace`/`suspended`.
Offline-lease tests cover: valid replay, expired-lease rejection, conflicting-target rejection, and a
lease that outlives its `maxOfflineDurationMinutes` boundary exactly.

## 19. Acceptance Gates

Per §16 — the three-stage rollout sequence itself is the acceptance gate for GA; no individual document
in this set claims GA-readiness on its own.

## 20. Controlled External Dependencies

None specific to this document beyond those already recorded in Docs A/C/D/E.

## 21. Non-Goals

Does not implement a payment/billing engine for entitlement contracts (a real subscription-billing
integration is its own future decision, out of scope here — `EntitlementGrant` records the *result* of a
contract decision, exactly as the existing real domain model's own doc comment already states). Does not
design AI capabilities beyond read-only recommendation. Does not resolve `WEB-001`.
