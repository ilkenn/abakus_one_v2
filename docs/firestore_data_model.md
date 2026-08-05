# Firestore Data Model — Phase 9 (`docs/decisions.md` ADR-026)

**Status: foundation, partially implemented.** This document describes the collection strategy
`firestore.rules` enforces and the pilot repository migration (Sprint 9E) targets. It is written
against the real, provisioned Firebase projects (`abakusone`/`abakus-one-dev`/`abakus-one-staging`)
but has **not been deployed to any of them** — everything here is emulator-verified only until an
explicit deployment step (outside this sprint's scope, per the Phase 9 kickoff's own stop conditions)
runs `firebase deploy --only firestore:rules`.

## Isolation model

**Shared project, shared collections, mandatory `organizationId`.** Per the Phase 9 architecture
analysis (`docs/phase9_architecture_analysis.md` §6), this is the initial model — cheapest, fastest to
ship, matches every existing Dart repository's own `organizationId`-as-field shape. A future enterprise
tier isolating a tenant into its own Firestore database/project is an explicitly deferred upgrade path,
not built here.

**Every tenant-owned document carries `organizationId` directly (denormalized), not only through a
parent-document lookup chain.** This is a deliberate performance/auditability choice: a rule that had
to `get()` branch → restaurant → organization on every single read would be slow and easy to get wrong.
Instead:
- `organizationId` is denormalized onto every tenant-owned document (branches carry it directly, not
  only via `restaurantId`).
- **Enforcement of the real chain happens at write time, not read time**: `firestore.rules`' `create`
  rules verify the denormalized `organizationId` actually matches the resolved parent (branch's
  `restaurantId` → that restaurant's real `organizationId`) via `get()`, and `update` rules make
  `organizationId` **immutable** after creation (no rule permits changing it). This is exactly what the
  kickoff's "branch scope resolves through branch → restaurant → organization" requirement means in
  practice: verified once, trusted (and fast) thereafter — not re-verified on every read.

## Custom claims vs. Firestore lookups

Per-request Firestore `get()` calls inside a security rule are real reads (they count against quota and
add latency) — the standard, recommended pattern for a Firestore-backed multi-tenant app is **Firebase
Auth custom claims** as the fast path, with Firestore as the durable source of truth a Cloud Function
syncs into claims whenever it changes. This document specifies both halves:

- `memberships/{organizationId}_{uid}` is the **source of truth** — created/updated only by a trusted
  Cloud Function (Sprint 9F), never directly by a client.
- `request.auth.token.organizationAccess` (a custom claim, a list of organization ids) and
  `request.auth.token.roles` (a map of `organizationId -> [roleNames]`) are the **fast path** rules
  check first. A Cloud Function trigger on `memberships` writes keeps these in sync — **this sync
  function does not exist as deployed code yet** (Sprint 9F); until it does, custom claims must be set
  by a manual/bootstrap process for emulator testing and any real pilot use, documented honestly as a
  gap, not silently assumed automatic.
- Platform-level authorization uses a **wholly separate claim**, `request.auth.token.platformRole` —
  never the same claim namespace as tenant `roles`/`organizationAccess`, mirroring
  `PlatformActorSession`'s existing client-side "zero shared types with the tenant stack" design
  (`docs/decisions.md` ADR-025).

## Collections

| Collection | Key | Tenant field | Written by | Notes |
|---|---|---|---|---|
| `platformMembers/{platformMemberId}` | sequential id | — (platform-owned) | Cloud Function only | Mirrors `PlatformMember`. Client: read own doc only. |
| `organizations/{organizationId}` | org id | is the boundary | Cloud Function only | Mirrors `Organization`. Client: read if a member. |
| `restaurants/{restaurantId}` | sequential id | `organizationId` | Cloud Function only | Mirrors `Restaurant`. |
| `branches/{branchId}` | sequential id | `organizationId` (denormalized, verified against `restaurantId`'s real owner at create) | Cloud Function only | Mirrors `Branch`. |
| `memberships/{organizationId}_{uid}` | composite | `organizationId` | Cloud Function only | Source of truth for custom claims — `roles: [String]`, `branchAccess/restaurantAccess/organizationAccess: [String]`, `status`. Client: read own membership docs only, never another user's. |
| `staffMembers/{staffMemberId}` | sequential id | `organizationId` | Cloud Function only | Mirrors `StaffMember`. Kept distinct from `memberships` — `memberships` is the claims-sync source of truth (minimal shape); `staffMembers` is the full admin-facing record (display name, session-revocation timestamp, etc.). |
| `customers/{uid}` | **Firebase Auth UID** | — (global identity, Sprint 9C) | Cloud Function + the owning user (profile fields only, never role/status fields) | The canonical global identity `AuthSession`/`ProfileModel`/CRM `Customer` all converge onto (Sprint 9C closes the current three-way fragmentation `docs/phase9_architecture_analysis.md` §4/§7 documents). |
| `tenantCustomers/{organizationId}_{uid}` | composite | `organizationId` | Cloud Function only (loyalty/visit data is server-computed) | Per-tenant CRM profile — visit counts, reward history. References `customers/{uid}`. |
| `entitlements/{entitlementId}` | sequential id | `organizationId` | Cloud Function only | Mirrors `EntitlementGrant`. Client: read only. **Clients cannot write arbitrary entitlement grants** — this is the literal, direct enforcement of that named requirement. |
| `orders/{orderId}` | canonical `OrderId` (Sprint 9D) | `organizationId`, `branchId` | Client create (staff/authenticated customer) with server-validated shape; status transitions Cloud-Function-only after creation | The one canonical `Order` aggregate (Sprint 9D) — no second, competing order collection. |
| `orderEvents/{eventId}` | generated id | `organizationId` | Cloud Function only | The event/outbox records (Sprint 9F) — idempotency key, correlation id, status, attempt count, next retry time, failure reason (redacted, no PII/secrets). |
| `auditEvents/{auditEventId}` | generated id | `organizationId` | Cloud Function only | Append-only — no rule permits `update` or `delete` on this collection at all, only `create` (server-side) and `read` (member). |
| `deletionRequests/{requestId}` | generated id | — (keyed by `uid`, may reference multiple `organizationId`s the account has tenant data in) | Cloud Function only for status transitions; client may `create` a request for their own `uid` | Sprint 9G. |
| `deviceTokens/{tokenId}` | generated id | `organizationId` (branding scope) + `uid` | The owning user (their own tokens only) | FCM tokens (Sprint 9H). |
| `mediaMetadata/{mediaId}` | generated id | `organizationId` | Cloud Function only (validates the actual upload before the ref becomes trusted) | Opaque ref metadata only — mirrors `CustomerPhoto.photoRef`/`BrandAssetSet`'s existing "never raw bytes" domain-layer discipline, extended to the backend. |

**Deliberately not modeled as separate collections**: `staffMembers`/`platformMembers`' role-change
audit trail reuses `auditEvents` (tagged by a `domain`/`type` field) rather than a dedicated collection
— mirrors the existing Dart codebase's own established "one shared audit repository can cover several
sub-concepts within one bounded context" precedent (Phase 8's `MarketplaceAuditEntry`).

## Required guarantees → rule mechanism (cross-reference)

| Requirement | `firestore.rules` mechanism |
|---|---|
| Clients cannot assign themselves an organization | `memberships`/`staffMembers`/`organizations` collections have no client `create`/`update` rule at all — Cloud Functions use the Admin SDK, which bypasses rules entirely; this is not a rule that could be bypassed, there is structurally no client write path. |
| Clients cannot promote roles | Same mechanism — `roles`/`organizationAccess`/`branchAccess`/`restaurantAccess` fields are never client-writable on any document. |
| Clients cannot write arbitrary entitlement grants | `entitlements` collection: read-only for clients. |
| No trust of caller-supplied tenant scope | Every rule's authorization decision reads `request.auth.token`/`memberships`, never `request.resource.data.organizationId` — that field is validated (must match), never trusted as the source of the decision. |
| Every protected read/write validates membership | `isOrgMember(organizationId)` helper, called by every collection's rules. |
| Restaurant scope resolves to organization | `restaurants/{id}.organizationId` is the resolution; `branches` denormalize it, verified at create. |
| Branch scope resolves through branch → restaurant → organization | Verified once at `branches` document creation via `get()` on the parent `restaurants` document; immutable thereafter. |
| Platform Owner and tenant authorization remain separate | Separate custom-claim namespace (`platformRole` vs. `roles`/`organizationAccess`), separate collections, no rule ever grants a platform action via a tenant claim or vice versa. |
| Support access is temporary, justified, audited | `supportGrants/{grantId}` collection (`organizationId`, `platformMemberId`, `reason`, `expiresAt`) — a platform member's elevated read access to `organizationId` is only granted while a matching, non-expired `supportGrants` document exists; every grant is itself an `auditEvents` entry. |
| Cross-tenant queries fail closed | Firestore's own rule semantics: a `list`/query rule requiring `resource.data.organizationId in request.auth.token.organizationAccess` rejects the **entire** query if any possible result could fail it — there is no partial/leaky result set. |
| Backups/restores must not mix tenants | Not a rule concern — named in `docs/phase9_architecture_analysis.md` §16 as real, deferred Sprint 9J-adjacent work (Firestore's native export is collection-level, not tenant-level). |

## What this sprint (9B) does NOT do

- Deploy these rules to any real Firebase project (`abakusone`/`abakus-one-dev`/`abakus-one-staging`) —
  emulator-verified only, per the kickoff's own stop condition on requiring real console/deployment
  access.
- Build the Cloud Function that syncs `memberships` writes into custom claims — that's Sprint 9F. Until
  it exists, custom claims must be set manually for any emulator test or real pilot use.
- Populate `firestore.indexes.json` with real compound indexes — no concrete multi-field query exists
  in the app yet (Sprint 9E introduces the first real Firestore-backed repositories); indexes are added
  when a real query that needs one actually exists, never spéculatively.
- Migrate any real repository off `InMemory*` onto these collections — that's Sprint 9E.
