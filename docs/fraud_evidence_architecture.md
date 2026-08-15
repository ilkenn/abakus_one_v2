# Delivery Fraud Location Evidence — Architecture Foundation

> Status: shared foundation (FRAUD-F.0) plus its first real producer, address-save capture
> (FRAUD-F.1). Order-submit capture (FRAUD-F.2) remains not started, hard-blocked on a real
> `submitDeliveryOrder` callable that does not exist anywhere in this codebase (re-confirmed absent as
> of FRAUD-F.1). This document describes the domain model, storage boundary, access-control
> guarantees, and — as of FRAUD-F.1 — the real address-save capture/evidence-creation flow. See
> `docs/decisions.md` FRAUD-F.0/FRAUD-F.1 for the full architecture-review record this implementation
> follows exactly.

## 1. Purpose

A future delivery order needs evidence of where a customer's device actually was at two moments —
saving a delivery address, and submitting a delivery order — so a Platform Owner can investigate
address/location fraud after the fact. This phase builds only the shared domain vocabulary, storage
boundary, and audited-access mechanism everything else stands on. It does not build any capture flow,
any admin UI, or any risk policy.

## 2. Domain entities

| Entity | File | Role |
|---|---|---|
| `FraudEvidence` | `lib/core/fraud/domain/fraud_evidence.dart` | Immutable, server-authoritative security evidence. Enforces the tenant-anchor invariant (§4) in its own constructor. |
| `ClientLocationEvidence` | same file | The client-originated, untrusted location *input* embedded in a `FraudEvidence` — never itself a trusted fact. |
| `ServerFraudInterpretation` | same file | Server-derived fields (distance, geocode, risk, App Check state, ...) — all nullable, never fabricated when unavailable. |
| `FraudSignal` | `lib/core/fraud/domain/fraud_signal.dart` | One descriptive observation about a `FraudEvidence`. Carries no enforcement field of any kind. |
| `FraudRiskContext` | `lib/core/fraud/domain/fraud_risk_context.dart` | Immutable, versioned, order-scoped risk interpretation. Reserved for FRAUD-F.2. |
| `FraudEvidenceRetentionPolicy` | `lib/core/fraud/domain/fraud_evidence_retention_policy.dart` | Server-side retention config; `computeExpiresAt` is the sole source of a `FraudEvidence.expiresAt` value. |
| `FraudEvidenceKind` | `lib/core/fraud/domain/fraud_evidence_kind.dart` | `addressSave` \| `orderSubmit`. |
| `MockLocationStatus` | `lib/core/fraud/domain/mock_location_status.dart` | `detected` \| `notDetected` \| `unsupported` \| `unavailable`. `notDetected` is never proof of a genuine location. |

The backend (`functions/src/fraud/fraudEvidenceTypes.ts`) mirrors these types field-for-field by hand
— this repository has no shared IDL/codegen step (`CLAUDE.md` §2).

## 3. Why this lives under `lib/core/fraud/`, not a feature

Fraud evidence is a cross-cutting security concern consumed by more than one domain (delivery address
evidence today; courier fraud detection already exists as a separate, unmigrated implementation under
`lib/features/courier/domain/fraud/`). `core/device_tokens/{domain,data,application}` is the closest
existing precedent for exactly this shape — a cross-cutting, security-sensitive concern with a real
Cloud-Function-mediated write boundary, living under `core/` rather than duplicated per feature. This
was inspected directly (not copied blindly) before choosing the same three-layer shape.

**Deviation from that precedent, disclosed**: FRAUD-F.0 implements `domain/` only. No `data/` or
`application/` Dart layer exists yet, because nothing in FRAUD-F.0 has a real Dart-side consumer —
there is no capture call site (FRAUD-F.1) and no admin UI (explicitly out of scope). Building an
unused gateway/use-case layer now would be exactly the "fill a layer just to satisfy the folder shape"
anti-pattern `docs/architecture_bible.md` §2 warns against. The real F.0 substance — the
`getPreciseFraudEvidence` read path and the (non-existent-yet) evidence-write path — lives entirely on
the backend, where it has a genuine caller.

## 4. Tenant/resource invariant

`FraudEvidence` enforces, in its own Dart constructor (throwing
`PartialFraudEvidenceTenantAnchorViolation` otherwise — `lib/core/errors/business_rule_violation.dart`):

- **Pre-order evidence** (`FraudEvidenceKind.addressSave`): `organizationId`, `branchId`, `orderId` all
  `null`. No tenant owns it; no tenant actor may ever read it.
- **Order evidence** (`FraudEvidenceKind.orderSubmit`): all three non-null, sourced server-side from
  the real order, never from client input.
- **Partial anchoring is always invalid** — there is no way to construct a `FraudEvidence` with, say,
  only `organizationId` populated.

`FraudRiskContext` may reference a prior `addressSave` evidence id via `priorEvidenceId` without ever
mutating that historical record.

## 5. Firestore storage and the direct-read prohibition

Four collections, declared in `firestore.rules`, every one `allow read, write: if false` unconditionally:

- `fraudEvidence/{evidenceId}`
- `fraudRiskContexts/{contextId}`
- `fraudEvidenceAccessLog/{logId}`
- `fraudEvidenceRetentionPolicies/{policyId}`

**No human client — customer, courier, staff, manager, admin, unrelated tenant,
`platformAdministrator`, or even `platformOwner` — may read or write any of these directly.** This is
absolute, not a default to relax later. The reason is structural, not merely a stricter policy choice:
a Firestore Security Rule can only allow or deny a read; it cannot itself produce the mandatory
access-audit side effect FRAUD-F.0 requires on every precise-evidence access. Granting `platformOwner`
a rules-based read branch would silently create a bypass of that audit guarantee. `firestore-tests/rules.test.js`
proves this denial for all 9 roles this app's authorization model recognizes, across create/read/update/delete,
for all 4 collections (144 assertions).

## 6. Authorization: `fraudEvidence.readPrecise`

No new `PlatformRole` was added. `functions/src/fraud/fraudAuthorization.ts`'s
`requireFraudEvidenceReadPrecise` checks only `request.auth.token.platformRole === 'platformOwner'` —
narrower than the existing `requirePlatformMember` (which also accepts `platformAdministrator`).
Tenant membership, `StaffRole`, branch access, and `platformAdministrator` are never sufficient.

This is deliberately not wired into `firestore.rules` at all (see §5) — the capability check lives
entirely inside `getPreciseFraudEvidence`, in one function. A future dedicated fraud-investigator
permission (a separate custom claim) only ever requires changing that one function's body; no storage
or rules migration is needed, because neither ever encoded a role check of its own.

## 7. `getPreciseFraudEvidence` — the sole precise-access path

`functions/src/getPreciseFraudEvidence.ts`. A single Firestore transaction (`{ maxAttempts: 1 }`, so
no silent retry of application logic):

1. Authenticate the caller.
2. Require `fraudEvidence.readPrecise`.
3. Read the requested evidence inside the transaction.
4. If it doesn't exist, throw `not-found` — no audit entry is written for an access attempt against a
   nonexistent id (the resource/context boundary check in step 5 has nothing real to bound).
5. Otherwise, write one immutable `fraudEvidenceAccessLog` entry (actor uid, capability, evidence id,
   timestamp, non-sensitive scope metadata only).
6. Only if the transaction commits — i.e. the audit write succeeded — return the evidence.

There is no code path that returns evidence without a committed audit entry, because both happen
inside one atomic transaction and the HTTP response is only constructed after `runTransaction`
resolves.

## 8. App Check provenance

Any App Check/attestation state this system ever records comes only from a Cloud Function's own
trusted request context (`request.app`), never from `request.data`. `getPreciseFraudEvidence` never
reads an App-Check-shaped field from `request.data` at all — proven by
`functions/src/test/getPreciseFraudEvidence.test.ts`'s forged-field test. Enforcement itself follows
the existing `shouldEnforceAppCheck()` (`functions/src/appCheckConfig.ts`) — **still `false` by
default outside the emulator today**, pending the already-disclosed, unrelated Web reCAPTCHA
Enterprise provisioning blocker (`docs/feature_status.md`, Faz D.5). FRAUD-F.0 does not change or
resolve that blocker; it inherits it, honestly.

## 9. Risk/signal model

`FraudSignal` (§2) has no enforcement field of any kind. FRAUD-F.0 defines no real detector and no
permanent risk threshold — `FraudSignal.type` is a free-text string, not a fabricated closed enum,
mirroring `CourierFraudSignalType`'s own documented discipline against inventing taxonomy with no real
detector behind it. Distance mismatch alone must never become automatic order rejection, in any future
policy version.

## 10. Retention

`FraudEvidenceRetentionPolicy.computeExpiresAt` (Dart and TS, kept in sync by hand) is the sole source
of a `FraudEvidence.expiresAt` value. **No production retention duration is defined anywhere in
FRAUD-F.0** — the exact duration is a legal/KVKK release-gate decision (`docs/business_rules.md`
BR-ACCOUNT-002 already documents this project's legal content as DRAFT, unapproved). A
`TEST_ONLY_RETENTION_POLICY`/test-only Dart policy exists solely for deterministic tests, explicitly
labeled as such. **No scheduled delete sweep was built** — Firestore's own TTL policy mechanism
(configured on the `expiresAt` field via console/`gcloud`, not application code) is the intended
primary deletion mechanism, per explicit instruction not to build a sweep unless proven required. The
actual TTL policy has **not** been configured in Firestore infrastructure by this phase — that is a
deployment step, not a code change, and is called out as residual work in `docs/decisions.md`.

## 11. FRAUD-F.1 — Address-Save Evidence Capture

Implemented: an optional, non-blocking foreground location candidate folded directly into the
existing `saveDeliveryAddress` callable (`functions/src/deliveryPlaces.ts`) — no standalone
client-callable capture endpoint exists.

**Client**: `AddressLocationGateway.captureLocationEvidence()` (`lib/features/address_search/data/
address_location_gateway.dart`) — a single, foreground, one-shot geolocator read, deliberately
separate from the pre-existing `currentPosition()` (which only ever centers the map camera and is
never sent to the server). Never background, never continuous, never repeated, never a route/history
collection. Every failure mode (permission denied, permanently denied, service disabled, GPS timeout,
any platform error) resolves to an `unavailable` result with a reason — never throws, never fabricates
coordinates. `MapFirstAddressScreen._save()` calls it once, immediately before the existing
`SavedAddressRepository.save()` call, and forwards whatever it got — available or not — without ever
using the result to move the selected pin (`_cameraTarget`/`_resolved` are untouched by this call).

**Server**: `saveDeliveryAddress` parses the raw, fully client-controlled `deviceLocationCandidate`
via `parseDeviceLocationCandidate` (`functions/src/fraud/deviceLocationCandidate.ts`) — a pure
function that never throws and degrades any malformed input to `incomplete` rather than rejecting the
address save. When a usable candidate exists, the callable independently reverse-geocodes the
*device* point (never the selected address's own already-resolved fields) via the same
`defaultReverseGeocodeFn`/`defaultPlaceDetailsFn` pipeline `reverseGeocodeAddressPoint` already uses,
and computes `distanceMeters` (`functions/src/fraud/geoDistance.ts`, haversine) against the selected
address's own server-resolved coordinates — never a client-supplied value for either. `phoneVerified`
comes from `request.auth.token.phone_number`; `appCheckState` from `request.app` only. A new
`fraudEvidence` document (`kind: "addressSave"`, tenant anchor fully null) is created **inside the
same Firestore transaction** as the address write itself — see "Failure/atomicity" below for why that
is safe and deliberate, not the after-commit best-effort sketch this document's FRAUD-F.0 revision
originally described.

**Availability is a first-class, three-state concept** (`FraudEvidenceAvailability`, added this
phase to both `lib/core/fraud/domain/fraud_evidence.dart` and
`functions/src/fraud/fraudEvidenceTypes.ts`): `available` (a usable candidate was captured — evidence
carries real coordinates), `unavailable` (nothing was ever offered — permission denied, service
disabled, timeout, or simply omitted), `incomplete` (something was offered but didn't hold up
validation). `FraudEvidence.clientLocation` is non-null if and only if `availability == available` —
enforced in the Dart constructor via a new `InconsistentFraudEvidenceAvailabilityViolation`
(`lib/core/errors/business_rule_violation.dart`), mirroring the tenant-anchor invariant's own
fail-fast discipline.

### Failure/atomicity — the decision, and why

The FraudEvidence write happens **inside the same transaction** as the `customerAddresses` write —
not the best-effort/after-commit approach this document originally sketched at FRAUD-F.0 time. This
is safe specifically because every fallible step (device reverse-geocode, distance computation) runs
**before** the transaction starts and is fully reduced to a plain, already-validated data object by
the time the transaction opens; the `tx.set()` call for the evidence document itself is therefore no
more likely to fail than the address's own `tx.set()` immediately above it, which this app already
accepts as `saveDeliveryAddress`'s availability bar. The result: a `SavedAddress` and its `FraudEvidence`
record always exist together, or neither does — no address can ever be saved with zero evidence trace
(even an `unavailable` one) due to an unlucky ordering. Reverse-geocode failures specifically are
caught and logged (`logger.warn`) without affecting availability at all — a failed device-geocode
still yields `available` evidence with valid coordinates/accuracy, just null derived-address fields.

### Server authority

Client may only ever submit the raw candidate shape (`status`, `latitude`, `longitude`,
`accuracyMeters`, `clientCapturedAt`, `mockLocationStatus`, `permissionState`, `precisionState`).
`distanceMeters`, every geocoded field, `phoneVerified`, `appCheckState`, and `policyVersion`
(currently the constant `FRAUD_F1_POLICY_VERSION = "fraud-f1-signals-only-no-risk-policy"` — FRAUD-F.1
still defines no real risk policy) are computed exclusively server-side and are never read from
`request.data`, proven by dedicated forged-field tests.

## 12. Deferred: FRAUD-F.2

Fold order-submit evidence into a future real `submitDeliveryOrder` callable, which does not exist in
this codebase (confirmed absent again this phase). Not started; hard-blocked on that callable's own,
separate implementation. `CourierFraudSignal` was not migrated. No fraud admin/review UI was built.
No permanent risk thresholds or production KVKK retention duration were introduced this phase either.
