# Abaküs One — Cloud Functions

Sprint 9F (`docs/decisions.md` ADR-026 Decision 7). Server-authoritative Firestore triggers backing
the tenant model and canonical order lifecycle Sprints 9B–9E built. **Emulator-tested only — not
deployed to any real Firebase project.** Deploying requires real project access (`firebase deploy
--only functions --project <alias>`) this session's stop conditions reserve for explicit approval.

## What exists

- **`onOrderCreated`** (`src/onOrderCreated.ts`) — the server-authoritative `created ->
  pendingConfirmation` transition. Closes a real gap Sprint 9E's `FirestoreCanonicalOrderRepository`
  left open: `firestore.rules`'s `orders` collection allows a client `create` only while `status ==
  'created'`; every later transition is `allow update: if false`. Against a real deployed project,
  this function — not the Dart client — is what actually moves a freshly created order out of
  `created`. Idempotent by construction (re-checks the document's current status inside a transaction
  before acting; a second trigger invocation for the same create event no-ops).
- **`onOrderCompleted`** (`src/onOrderCompleted.ts`) — writes a durable, exactly-once outbox record
  (`orderEvents/{orderId}-completed`) when an order reaches `OrderStatus.completed`. Uses
  `.create()` (fails on an existing document) rather than `.set()`, so a second trigger invocation for
  the same completion is caught and ignored, not silently duplicated or overwritten.
- **`processAccountDeletion`** (`src/processAccountDeletion.ts`) — Sprint 9G, authorization hardened
  **Faz D.3.2.1 (REQUIRED security fix)**. Processes one due `deletionRequests` document, anonymizing
  the linked `customers/{uid}` CRM record idempotently. **Prior to this phase, this callable had no
  `request.auth` check of any kind** — combined with `deletionRequests` ids being sequential/guessable
  (`SequentialAccountDeletionRequestIdGenerator`), any unauthenticated caller who guessed a `requestId`
  could trigger another customer's already-due deletion side-effect. Now requires a real, phone-verified
  caller (`sign_in_provider == 'phone'`, the same identity model `submitTakeawayOrder` uses — an
  anonymous technical identity is denied `permission-denied`) and independently re-verifies
  `deletionRequests/{requestId}.uid === request.auth.uid` before doing anything — a mismatch resolves
  identically to a genuinely unknown `requestId` (`not-found`), so the endpoint is never usable as an
  account/request-existence oracle. The affected account is always the request document's own
  server-written `uid` field (constrained by `firestore.rules`'s `create` rule to
  `== request.auth.uid`) — the accepted payload has never contained a client-supplied uid at all. Also
  now App Check-ready via the same shared `appCheckConfig.ts`. The Firebase Auth account itself is
  **not** deleted by this function, only the Firestore CRM record is anonymized — see
  `docs/business_rules.md` BR-ACCOUNT-001 for the full rule and `docs/decisions.md` ADR-027 Faz D.3.2.1
  for the vulnerability/fix writeup.
- **`resolveTableQrToken`** (`src/resolveTableQrToken.ts`) — Table Guest Session Phase 1/2. Public
  (unauthenticated) callable — a QR scan resolves server-side, before any session exists. Returns only
  a minimized `TableQrPublicPreview` (status + display names) — never `organizationId`/`restaurantId`/
  `branchId`/`tableId` (data-minimization fix, this phase's review). **App Check — closed, Faz D.3.2**:
  wires `appCheckConfig.ts`'s `shouldEnforceAppCheck()`, the exact same shared config the takeaway
  analogue (`resolveTakeawayQrToken`) already used — this was the one REQUIRED finding Faz D.3 reported
  and left open ("`resolveTableQrToken` ... has the exact same gap ... not touched this phase").
- **`openTableGuestSession`** (`src/openTableGuestSession.ts`) — Table Guest Session Phase 1/2.
  Authenticated-only callable (anonymous sign-in satisfies this). The only client input is the opaque
  QR token — organization/restaurant/branch/table scope is always independently re-resolved
  server-side via `qrTokenResolution.ts`'s shared `resolveTableQrTokenInternal`, never accepted as a
  caller-supplied id. Writes a `tableGuestSessions` document bound to `request.auth.uid`
  (`guestAuthUid`), with a server-computed `expiresAt` (`tableGuestSessionConfig.ts`'s
  `TABLE_GUEST_SESSION_TTL_MS`, 6 hours by default, overridable via the `TABLE_GUEST_SESSION_TTL_HOURS`
  environment variable for local testing). `firestore.rules`'s new `tableGuestSessions` match block
  makes this collection Cloud-Function-write-only, owner-read-only. **App Check — closed, Faz D.3.2**:
  same shared `shouldEnforceAppCheck()`, layered on top of (never replacing) the existing
  `unauthenticated` check above — App Check proves a genuine app build is calling, never who the caller
  is; the two mechanisms stay independent.
- **`provisionOrganization`** / **`provisionRestaurant`** / **`provisionBranch`**
  (`src/provisionOrganization.ts` / `src/provisionRestaurant.ts` / `src/provisionBranch.ts`) — Faz D.1
  (Canonical Restaurant/Branch Provisioning) + Faz D.1.1 (Canonical Organization Provisioning). The
  first functions to actually write to `organizations`/`restaurants`/`branches`, closing the "Cloud
  Function only" gap those collections' own `firestore.rules` match blocks have carried since Phase 9.
  Platform Owner/Administrator-only (`src/platformAuthorization.ts`'s `requirePlatformMember`, a
  server-side mirror of `firestore.rules`'s `isPlatformMember()`) — never public/anonymous-callable,
  never satisfiable by a tenant-level `roles`/`organizationAccess` claim regardless of seniority.
  `provisionRestaurant` independently re-verifies its parent `organizations/{organizationId}` document
  exists and `isActive == true`, server-side, inside the same transaction (Faz D.1.1 — previously
  structural-string-only); `provisionBranch` does the same against its parent
  `restaurants/{restaurantId}` document's own `organizationId` (Faz D.1). A caller's claimed
  `organizationId`/`restaurantId` is never trusted on its own at any level of the chain. All three are
  idempotent: caller-supplied deterministic ids (`organizationId`/`restaurantId`/`branchId`),
  `.set()`-based upsert, immutable tenant/parent binding once first set (an organization's own `name`/
  `isActive` may be legitimately re-provisioned — it has no parent to bind against). `scripts/
  seed_dev_tenant.mjs` (`npm run seed:dev-tenant`) provisions this app's real seeded tenant
  (`org-1` -> `restaurant-1` -> `branch-1`) as real Firestore documents, in canonical order, through
  these three callables — never by writing to Firestore directly.
- **`resolveTakeawayQrToken`** / **`openTakeawayGuestSession`** (`src/resolveTakeawayQrToken.ts` /
  `src/openTakeawayGuestSession.ts`) — Faz D.2 (Gel Al QR + Guest Session Backend). The kasadaki
  (register) takeaway analogue of `resolveTableQrToken`/`openTableGuestSession`, backed by a
  deliberately **separate** pair of collections (`takeawayQrCodes`/`takeawayGuestSessions` — no
  `tableId`, unlike the dine-in case) sharing the same security shape. Both share one internal resolver,
  `src/takeawayQrTokenResolution.ts`'s `resolveTakeawayQrTokenInternal` — `openTakeawayGuestSession`
  never trusts a prior `resolveTakeawayQrToken` preview result, re-resolving the raw token itself every
  time. Unlike the table case, resolution validates the QR's claimed organization/restaurant/branch
  identity against the **real** Faz D.1/D.1.1 canonical chain (`organizations`/`restaurants`/`branches`)
  — existence, `isActive`, chain-consistency, `branches.status == 'active'`, not
  `emergencyStopped`, and `'takeaway' in supportedOrderChannelIds` are all independently re-verified
  server-side; a broken/mismatched chain resolves `notFound`, an intact-but-currently-unusable one
  resolves `invalid` (mirrors `resolveTableQrTokenInternal`'s own status-split convention). Session TTL
  is `src/takeawayGuestSessionConfig.ts`'s own, separate config — **30 minutes by default** (RECOMMENDED
  decision, no prior business rule; see that file's own doc comment for the full checkout-length-vs-
  dine-in-visit-length rationale), overridable via `TAKEAWAY_GUEST_SESSION_TTL_MINUTES`.
  `openTakeawayGuestSession` reuses an existing active, unexpired session for the same
  (`guestAuthUid`, `qrTokenId`) pair rather than minting a new one on every retry — scoped per-caller, so
  a different customer scanning the same physical QR always gets an independent session.
  **QR revocation does not retroactively invalidate an already-open session** — a deliberate decision,
  documented in `takeawayGuestSessionConfig.ts`'s own doc comment. No order-create path exists yet —
  that's `submitTakeawayOrder`, Faz D.3. `scripts/seed_dev_takeaway_qr.mjs`
  (`npm run seed:dev-takeaway-qr`) seeds a real, deterministic-token `takeawayQrCodes` document bound to
  the dev tenant chain, via direct Admin SDK write (the only, intended write path for this
  collection — no callable creates `takeawayQrCodes` documents, by design, matching `tableQrCodes`'s own
  precedent).
- **`submitTakeawayOrder`** (`src/submitTakeawayOrder.ts`) — Faz D.3 (Server-Authoritative Pricing +
  Takeaway Order Creation). The one callable both takeaway scenarios (QR guest, authenticated app
  customer) submit through — same pricing/validation pipeline for both, no duplicated business logic.
  **The backend is the sole authority** for organization/restaurant/branch scope, product identity/
  availability/category/price, modifier identity/price, channel-adjusted pricing, computed totals,
  pickup semantics, and initial status; the accepted request shape has no `unitPrice`/`subtotal`/
  `grandTotal`/price field of any kind for either path, so there is nothing for the function to trust in
  the first place, not merely something it chooses to ignore. Writes the exact same document shape
  `OrderFirestoreMapper.toFirestore` (Dart) produces, so an order created here reads back identically
  through the existing `OrderFirestoreMapper.fromFirestore` — a new authoritative writer, not a new
  document shape. Two strictly separate, mutually-exclusive branches (dispatched on
  `request.auth.token.firebase.sign_in_provider === 'phone'`, an explicit allow-list — an anonymous
  caller supplying any authenticated-branch field, or a phone-verified caller supplying a
  `takeawaySessionId`, is rejected outright, `permission-denied`/`invalid-argument` respectively, never
  silently ignored):
  - **QR guest**: requires `takeawaySessionId`; reads `takeawayGuestSessions/{id}` server-side inside
    the write transaction (exists, `guestAuthUid == request.auth.uid`, `status == 'active'`, unexpired)
    and derives `organizationId`/`restaurantId`/`branchId` from it — never client input.
    `customerId = null`, `guestAuthUid = request.auth.uid`, `pickupMode = 'asap'`, `pickupTime = null`
    always (forced server-side, never read from the request for this branch).
  - **Authenticated**: requires `restaurantId`/`branchId`/`pickupMode: 'scheduled'`/`pickupTime`;
    validates the branch via `takeawayScope.ts`'s `resolveActiveTakeawayBranch` (the exact same function
    `resolveTakeawayQrTokenInternal` uses — refactored out in this phase specifically so neither entry
    path can silently drift from the other on what counts as a valid scope). `pickupTime` must be
    `>= serverNow + 20 minutes` (`request.time`-equivalent — the server's own clock, `Date.now()` inside
    the Function, never anything the client claims about "now"). `customerId = request.auth.uid`,
    `guestAuthUid = null` (matches `Order.guestAuthUid`'s own existing "null for takeaway" doc comment).
  - **Canonical catalog** (`src/takeawayCatalog.ts`, closes the Faz D architecture analysis's REQUIRED
    finding): Firestore-backed `menuCategories`/`menuProducts`/`bowlIngredients`/`channelPricingPolicies`,
    a canonical representation of the existing Dart `MenuCategory`/`MenuProduct`/`ModifierGroup`/
    `ModifierOption`/`ChannelPricingPolicy`/`ChannelPriceRule`/`BowlBuilderIngredient` domain model — not
    a new, parallel pricing model. **Faz D.3.1 closed the "representative subset" scope decision**: the
    real, full catalog (7 categories, 79 products, 64 bowl ingredients — detected from the export itself,
    never hardcoded) is now migrated from the real Dart `AbakusMenuCatalog`/
    `LocalBowlBuilderCatalogRepository` — see `src/catalogMigration.ts` below.
  - **Pricing engine** (`src/takeawayPricing.ts`/`takeawayMoney.ts`): hand-mirrors
    `ChannelPriceResolver`/`OrderLine.create`/`PriceCalculator`/`MoneyRounding` exactly, operating on
    integer TRY minor units throughout (never a float) — same precedence as Faz A (explicit price >
    fixed adjustment > category override > channel default > zero), same "+20 TL once per bowl unit,
    never per ingredient" rule, same VAT-extraction formula.
  - **Idempotency**: `submissionKey` (client-supplied) + the caller's own `uid` deterministically derive
    the order's Firestore document id (`sha256(uid|submissionKey)`) — a different actor with the same
    key never collides; the same actor retrying with the identical, already-validated request payload
    (hashed into a stored `takeawaySubmissionFingerprint`) reuses the existing order; the same actor
    reusing the key with a **different** payload is rejected `failed-precondition`, fail-closed, the
    original order left untouched. All inside one Firestore transaction per submission.
  - **App Check-ready** via `appCheckConfig.ts`, same deployment-env-var activation as
    `resolveTakeawayQrToken`/`openTakeawayGuestSession`.
  - **Faz C migration — closed, Faz D.3.1.** The authenticated in-app takeaway flow
    (`TakeawayCheckoutScreen`) now calls this callable through
    `lib/features/takeaway/data/submit_takeaway_order_gateway.dart` instead of writing to Firestore
    client-side; `firestore.rules`'s `isValidAuthenticatedTakeawayOrder` branch has been removed. See
    `docs/decisions.md` ADR-027 Faz D.3.1 for the full migration decision and verification.

- **`submitReservation`** (`src/submitReservation.ts`) — Rezervasyon Faz R.1A (`docs/decisions.md`
  ADR-027 Faz R.0–R.0.7 design, this phase's implementation). Real-phone-auth-only —
  `sign_in_provider === 'phone'`, an explicit, non-negotiable identity requirement; unlike takeaway/
  dine-in QR there is no anonymous-guest path for reservations at all. Validates contact fields, party
  size against the branch's own `ReservationPolicy.maxPartySize`, minute alignment (safe epoch
  arithmetic, `% 60000 == 0`), `slotIntervalMinutes` grid alignment, `NOW + MINIMUM_ADVANCE_MINUTES`
  (30, USER-LOCKED platform constant, never branch-configurable — inclusive `>=`, server clock only),
  and `ReservationPolicy.bookingHorizonDays`. Scope (`organizationId`/`restaurantId`/`branchId`) and
  `areaId` are always independently server-resolved (`src/reservationScope.ts`) against the real
  canonical chain and `reservationAreas` — never trusted from the client, and a cross-tenant `areaId`
  resolves `not-found` rather than confirming its existence. **A full slot never rejects the request**
  (Faz R.0.3's own explicit product rule) — capacity (`src/reservationAvailability.ts`'s deterministic,
  query-less `[start,end)` bucket model, `reservationSlotOccupancy`, transaction-safe via `tx.get()`
  per bucket) only decides whether an `initialRequest`-purpose `reservationHold` also gets created;
  either way a `Reservation` is always written, `status: 'pendingRestaurantApproval'`, no auto-confirm.
  `responseDeadlineAt = min(now + restaurantResponseTimeoutMinutes, requestedTime)`. Idempotent
  (`sha256(uid|submissionKey)`-derived document id, mirrors `submitTakeawayOrder`'s own
  `deriveOrderId` exactly). App Check-ready via the same shared `appCheckConfig.ts`.
  **Explicitly not implemented this phase** (later, separate phases): restaurant approval/change-
  proposal/hold-accept-reject workflow, physical table assignment, QR reservation-time protection, any
  preorder (no `Order` is ever created by this callable), KDS integration, any UI. `scripts/
  seed_dev_reservation.mjs` (`npm run seed:dev-reservation`, chained into `seed:dev-all`) provisions
  `reservationPolicies/branch-1` and two `reservationAreas` ("Bahçe"/"İç Mekân") for the dev tenant
  chain, via direct Admin SDK write (no callable write path exists for either collection, by design,
  matching `tableQrCodes`/`takeawayQrCodes`'s own precedent).

- **`respondToReservation`** (`src/respondToReservation.ts`) — Rezervasyon Faz R.1B (`docs/decisions.md`
  ADR-027 Faz R.1B design). Staff-only callable — `confirm`/`reject`/`proposeChange` — authorized via
  `src/reservationAuthorization.ts`'s `requireReservationManagerPermission` (`organizationAccess`/
  `roles` custom claims, `manager`/`admin`/`tenantOwner` tier, this codebase's first TS-side tenant-
  staff authorization check; the target `organizationId` is always read server-side from the
  Reservation itself, never trusted from the client). Confirm consumes the active initial hold, or —
  if it's missing/expired/wrong-status — re-checks current capacity fresh inside the same transaction
  and claims it directly (`src/reservationHoldOps.ts`'s `claimConfirmedCapacityDirectly`), the path
  that lets a full-at-submission reservation still confirm once capacity opens. Reject releases the
  initial hold. ProposeChange validates the alternative time/area with `submitReservation`'s own
  invariants (reused, not re-derived), releases the old initial hold, and creates a new
  `alternativeProposal` hold plus an immutable `reservationChangeProposals` document — the "only one
  active proposal" invariant is enforced by the `pendingRestaurantApproval`-only status gate itself,
  race-safe under Firestore's own transaction retry.

- **`respondToProposedChange`** (`src/respondToProposedChange.ts`) — Faz R.1B. Customer-only callable —
  `accept`/`reject` — same real-phone-auth gate as `submitReservation`, ownership always
  `reservation.customerId == request.auth.uid`, never a client-supplied id. Accept independently
  re-verifies the hold's own `active`+unexpired state before consuming it (never trusts the proposal's
  own status alone — mirrors Faz R.0.3's race-safety precedent) and re-validates the Faz R.0.7 §2
  minute-alignment invariant. Reject releases the hold and returns the Reservation to
  `pendingRestaurantApproval` — explicitly not terminal.

- **`reservationSweep`** (`src/reservationSweep.ts`) — Faz R.1B, this codebase's first `onSchedule`
  usage (`every 5 minutes`). Resolves two cases, each inside its own idempotent/retry-safe transaction
  that re-validates its own precondition before mutating: a Reservation past `responseDeadlineAt` still
  `pendingRestaurantApproval` is rejected (`reasonCode: 'restaurantResponseTimeout'` — deliberately a
  reasonCode, not a new terminal status, reasoned in `docs/decisions.md` ADR-027 Faz R.1B); a proposal
  past `customerResponseDeadlineAt` still `pendingCustomerResponse` is marked `expired`, returning its
  Reservation to `pendingRestaurantApproval`. Both release their hold. The sweep logic is exported as
  plain, directly-callable functions (`runReservationResponseTimeoutSweep`/
  `runReservationProposalExpirySweep`) so tests call it directly rather than triggering a scheduled
  function through the emulator's HTTP surface.

- **`assignReservationTable`** (`src/assignReservationTable.ts`) — Faz R.1C.1. Staff-only callable
  (`{reservationId, tableId}`, `manageReservations` permission via `staffAuthorization.ts`) serving both
  first assignment and atomic reassignment through the same contract. Validates the Reservation is
  `confirmed`, the table belongs to the same tenant/branch, is `isActive`, and its (new, additive)
  `reservationAreaId` matches the reservation's own `confirmedAreaId` — this codebase's first canonical
  `restaurantTables`<->`reservationAreas` relation, disclosed explicitly (none existed before this
  phase). Creates exclusive physical-table locks (`src/reservationTableOccupancy.ts`,
  `reservationTableOccupancy` collection — a genuinely separate model from `reservationSlotOccupancy`'s
  area capacity) and QR-protection *data only* (`src/reservationTableProtection.ts`,
  `reservationTableProtections` + `tableProtectionMinuteBuckets` — T-20 lead, shared minute-bucket
  membership across overlapping-but-non-conflicting reservations — **Faz R.1C.2 made this the real QR
  enforcement source**, see below). Every read happens before any write (the same ordering fix Faz
  R.1B's `reservationHoldOps.ts` needed, reapplied here), so a conflict on a new table during
  reassignment can never disturb the old assignment. Enforces a structural
  `MAX_RESERVATION_DURATION_MINUTES_FOR_TABLE_ASSIGNMENT` (180 min) *and* a real worst-case-write-count
  guard (`resource-exhausted`) before attempting any Firestore transaction write — reasoned explicitly
  in `docs/decisions.md` ADR-027 Faz R.1C.1. **Faz R.1C.2**: reassignment now also hard-fails while this
  exact Reservation's `activeReservationTableContext` on its current table is live — no silent context
  migration; staff must `closeReservationTable` first.

- **QR T-20 enforcement** (`src/qrTokenResolution.ts`, Faz R.1C.2) — `tableProtectionMinuteBuckets`
  (written since Faz R.1C.1, unread until now) becomes the real, server-authoritative source both
  `resolveTableQrToken` and `openTableGuestSession` check, inside the one shared
  `resolveTableQrTokenInternal` — deterministic get-by-id (`{tableId}__{epochMinute}`,
  `epochMinute = floor(serverNowMillis / 60000)`), never a query, never a scheduler dependency. New
  `reserved` `TableQrValidityStatus` value; the public preview response for it is `{status: 'reserved'}`
  only (`toPublicPreview` needed zero change — the existing non-`'valid'` stripping already covers it).
  `openTableGuestSession` independently re-evaluates on every call (never trusts a cached preview
  result), so calling it directly, bypassing the preview, is blocked identically.

- **`openReservationTable`** (`src/openReservationTable.ts`, Faz R.1C.2) — staff-only
  (`manageReservations`), `tableId` always resolved server-side from `Reservation.assignedTableId`.
  Two-step conflict handshake: an active *walk-in* `tableGuestSessions` session on the table is a soft
  conflict (`acknowledgeActiveSessionConflict: true` on a second call proceeds, returning a structured
  `{code: 'activeSessionExists', conflictingSessionCount}` on the first); a *different Reservation's*
  already-live `activeReservationTableContext` on the same table is a hard conflict that
  acknowledgement can never override. On success: removes only this reservation's own protection
  membership (`removeReservationTableProtection`, Faz R.1C.1, reused verbatim — a later reservation's
  own protection on the same table is untouched), deactivates that protection record, and activates
  `activeReservationTableContext/{tableId}`.

- **`closeReservationTable`** (`src/closeReservationTable.ts`, Faz R.1C.2) — staff-only
  (`manageReservations`). Deliberately narrow: deactivates the matching context only — never touches
  `Reservation.status`, never closes/kills existing `tableGuestSessions`, never restores protection.
  Idempotent.

- **`activeReservationTableContext`** (`src/reservationTableContext.ts`, Faz R.1C.2) — the shared
  "is this table's context currently live" resolver (`readLiveReservationTableContext`): `active ==
  true` **and** `serverNow < contextEndAt`, re-derived on every read, never assumed from the stored
  `active` flag (no scheduler expires a stale context). One implementation, three readers:
  `openReservationTable`'s conflict/idempotency check, `openTableGuestSession`'s
  `reservationContextId` snapshot decision, `assignReservationTable`'s reassignment guard.

- **`reservationContextId` order linkage** (Faz R.1C.2) — `openTableGuestSession` snapshots the live
  context's `reservationId` (or `null`) onto the new `tableGuestSessions` document; immutable
  thereafter. `firestore.rules`' `tableGuestSessionMatchesOrderScope` now also requires exact equality
  (missing-field-safe, `null` included) between `tableGuestSessions.reservationContextId` and
  `Order.reservationContextId` for both dine-in-QR order-create branches — a client can neither omit
  it, coerce it to `null`, nor claim a different reservation's context. Threaded through the Flutter
  client (`OpenedTableGuestSession` -> `ActiveTableContext` -> `SubmitCustomerOrder`/
  `CartToOrderMapper` -> `Order.reservationContextId`, mirroring `guestAuthUid`'s own existing shape at
  every step) — this phase's own first, deliberately minimal Dart change in the Rezervasyon arc; no
  reservation UI was built.

- **Optional reservation preorder** (`src/reservationPreorder.ts`, Faz R.1D.1) — `submitReservation`
  accepts an optional `preorder: { items: [...] }` field; when present, a second aggregate — a
  `reservationPreorder`-channel `orders` document — is created atomically in the same transaction,
  server-priced against the canonical catalog (`takeawayCatalog.ts`/`takeawayPricing.ts`, reused as-is,
  channel hardcoded to the literal `"reservationPreorder"` at one point, never threaded as a parameter)
  at table/base price — no Gel Al packaging surcharge, no delivery surcharge (verified even against a
  policy with real non-zero adjustments configured for those other channels). Linked via
  `Order.reservationContextId == Reservation.id` (the field's second, disambiguated-by-channel meaning —
  see `docs/firestore_data_model.md`) and the new `Reservation.preorderOrderId` (nullable, immutable,
  deterministically derived). New locked constant `PREORDER_KITCHEN_RELEASE_LEAD_MINUTES = 60`
  (`reservationConfig.ts`) drives `computePreorderKitchenTiming` — the one shared boundary computation
  applied, in the same transaction as the reservation's own state change, at direct confirm
  (`respondToReservation.ts`), proposal accept (`respondToProposedChange.ts`), restaurant reject and
  response-timeout (`reservationSweep.ts`): `remaining > 60m` keeps the preorder `pendingConfirmation`
  with `kitchenReleaseAt` recorded; `remaining <= 60m` confirms it immediately; a reject/timeout cancels
  it. Proposal reject/expiry deliberately touch nothing. `takeawayCatalog.ts`'s three loaders
  (`loadCanonicalMenuProduct`/`loadCanonicalBowlIngredient`/`loadCanonicalChannelPricingPolicy`) gained
  an optional `tx?: Transaction` parameter, used throughout this new module so every catalog read
  participates in `submitReservation`'s own transaction — `submitTakeawayOrder.ts`'s own existing call
  sites are deliberately untouched (disclosed technical debt, see `docs/feature_status.md`). No client
  can ever create/mutate a `reservationPreorder` order directly — `firestore.rules`' `orders` `create`
  rule has no branch matching this channel, mirroring the already-closed `takeaway` precedent.
  ~~`cancelReservation` still does not exist anywhere in this codebase (confirmed, reported gap, not
  built this phase).~~ **Closed, Faz R.3B** — see that phase's own section below. No scheduled
  KDS-release poller exists yet — nothing automatically moves a
  `pendingConfirmation` preorder past its `kitchenReleaseAt` without a confirm/accept event; that is Faz
  R.1D.2's job.

- **Scheduled preorder KDS release** (`reservationPreorderKdsRelease` in `src/reservationSweep.ts`, Faz
  R.1D.2) — the poller Faz R.1D.1 left as a gap. A **separate** scheduled function, `onSchedule("every 1
  minutes", ...)`, deliberately not folded into `reservationSweep`'s own `onSchedule("every 5 minutes")`
  — the two concerns need different cadences, and one `onSchedule` call site fixes one cadence.
  `runPreorderKdsReleaseSweep` mirrors `runReservationResponseTimeoutSweep`/
  `runReservationProposalExpirySweep`'s own exact shape: a bounded candidate query (`orders`: `channel ==
  "reservationPreorder"`, `status == "pendingConfirmation"`, `kitchenReleaseAtTimestamp <= now`, ordered
  oldest-due-first, `limit(50)` — never an unbounded scan; requires the new composite index in
  `firestore.indexes.json`), then one independent, retry-safe transaction per candidate, wrapped in its
  own `try`/`catch` so one corrupt/failing document can never abort the rest of the batch. The candidate
  query result is never trusted on its own: `buildPreorderKdsReleasePatch`
  (`src/reservationPreorder.ts`) re-verifies, inside the transaction, every invariant from scratch —
  Order exists/right channel/right status, `reservationContextId` present, linked Reservation exists and
  is `confirmed`, `Reservation.preorderOrderId` points back at this exact Order (the reverse-link
  integrity check), and — the core anti-drift guarantee — the *canonical* expected release instant
  (`expectedPreorderKitchenReleaseAt(Reservation.confirmedTime)`, the same function
  `computePreorderKitchenTiming` itself uses) is recomputed and must **exactly** match the stored
  `kitchenReleaseAtTimestamp`; any mismatch is a data-integrity condition, never silently repaired, never
  released. New companion field **`kitchenReleaseAtTimestamp`** (a real Firestore `Timestamp`, alongside
  the existing `kitchenReleaseAt` ISO string) — mirrors `submitTakeawayOrder.ts`'s own established
  `pickupTime`/`pickupTimeTimestamp` dual-representation precedent (string for display/back-compat, a
  real `Timestamp` for range/orderBy queries); the two are always set/cleared together, everywhere
  `kitchenReleaseAt` is written (`reservationPreorder.ts`'s `buildPreorderOrderDocument`/
  `buildPreorderConfirmationPatch`/`buildPreorderCancellationPatch`, all updated this phase). **Audit
  parity, explicitly requested**: the scheduler's `pendingConfirmation -> confirmed` transition writes an
  `auditEvents` record (`type: "order.statusChanged"`, mirroring `onOrderCreated.ts`'s own established
  shape — the one existing generic order-transition audit mechanism, extended rather than replaced) —
  and, for consistency, `buildPreorderConfirmationPatch`'s own immediate-release branch (direct confirm/
  proposal accept, when `remaining <= 60m` at confirmation time) now writes the identical record, so a
  `pendingConfirmation -> confirmed` preorder transition is audited the same way regardless of which of
  the two paths actually triggered it. `buildPreorderConfirmationPatch` stays a pure function — it
  returns `{ patch, auditEvent }` and never writes; every caller `tx.set()`s both atomically, so the
  order-status write and its audit record commit together or neither does, and a retried transaction
  (blocked by the same `status !== 'pendingConfirmation'` gate that already made every other transition
  in this arc retry-safe) never produces a duplicate event. **Concurrency**: verified with three
  overlapping `runPreorderKdsReleaseSweep` invocations against the same due order — exactly one effective
  transition, `version` incremented exactly once, never a duplicate `statusHistory` entry (Firestore's
  own optimistic-concurrency transaction retry is what makes this safe, not any extra locking). **KDS
  visibility — explicit, confirmed gap, not silently glossed over**: this phase proves the scheduler moves
  a due preorder Order to the correct `confirmed` state, atomically and idempotently, and that
  `KitchenTicketMapper.fromOrder` maps a `confirmed reservationPreorder` Order correctly (Faz R.1D.1's own
  Dart test). ~~It does **not** prove "a confirmed preorder is visible in the KDS pipeline end-to-end" —
  there is no live Firestore-Order-to-KDS ingestion path in this codebase at all yet, for any channel
  (`KitchenDisplayBoardScreen` reads from an in-memory mock `KitchenTicketRepository`, never a real
  `Order` stream; `FireKitchenTicket`/`KitchenTicketMapper.fromOrder` are invoked nowhere in the app
  outside tests — confirmed via research, not assumed). No `isKitchenEligibleOrder` predicate was built —
  there is no live query/filter site for one to attach to yet.~~ **Closed, Faz R.3C** —
  `FirestoreKitchenTicketRepository` now derives KDS tickets live from the canonical `orders`
  collection (`status in {confirmed, preparing, ready}`, branch-scoped), so this exact scheduled release
  is now genuinely end-to-end visible with no reservation-specific KDS code. Still not implemented at
  the time: ~~`cancelReservation`~~ (**closed, Faz R.3B** — the scheduler's own fail-closed-on-non-`confirmed`
  behavior, unchanged since this phase, is exactly what makes it race-safe against the now-real
  cancellation callable, per that phase's own concurrency verification), reservation customer/admin UI
  (closed, Faz R.2/R.3A), physical-table UI (closed, Faz R.3A), ~~push notification delivery (still not
  implemented)~~ (**closed, Faz R.3C** — see that phase's own section below).

- **Full canonical catalog migration** (`src/catalogMigration.ts`, Faz D.3.1) — closes Faz D.3's own
  "representative subset" scope decision. `tool/export_menu_catalog.dart` (pure Dart, `dart run`, no
  Flutter SDK dependency) serializes the real `AbakusMenuCatalog`/`LocalBowlBuilderCatalogRepository` to
  `functions/scripts/data/menu_catalog_export.json`, converting every price to integer TRY minor units.
  `migrateCanonicalCatalog(db, exportData, scope)` is the single, tested write implementation both
  `scripts/migrate_canonical_catalog.mjs` (the real migration script) and the automated test suite
  (`src/test/catalogMigration.test.ts`) exercise — deterministic ids matching the Dart catalog's own ids,
  idempotent `.set()`-based upsert, batched writes (400/batch). Dart is the single hand-authored source;
  Firestore is generated, never hand-edited — re-running `npm run migrate:catalog` after any Dart catalog
  change keeps both in sync. `npm run migrate:catalog`/`seed:dev-all` chain the Dart export step
  automatically. **Faz D.3.1.1 also folded the channel pricing policy into this same export/migration**:
  `tool/export_menu_catalog.dart` now additionally serializes the real
  `InMemoryChannelPricingPolicyRepository` (the same policy object `ChannelPriceResolver` already reads
  app-wide), and `migrateCanonicalCatalog` writes `channelPricingPolicies/{restaurantId}` from it — one
  canonical pricing seed, not two independent ones. **`scripts/seed_dev_catalog.mjs`'s own ~5-product
  representative fixture and its separate, hand-typed policy write are now both fully superseded** and
  no longer part of any canonical chain (`seed:dev-all`/`migrate:catalog` never call it) — kept in place,
  unmodified otherwise, only because deleting a file is a decision for the human, not taken unilaterally.

All are verified against the real (local) Firestore + Functions + Auth emulators — see
`src/test/functions.test.ts`/`tableGuestSession.test.ts`/`tableGuestSessionConfig.test.ts`/
`provisioning.test.ts`/`takeawayGuestSession.test.ts`/`takeawayGuestSessionConfig.test.ts`/
`takeawayPricing.test.ts`/`submitTakeawayOrder.test.ts`/`catalogMigration.test.ts`/
`submitTakeawayOrderRealCatalog.test.ts`/`appCheckConfig.test.ts`/`processAccountDeletion.test.ts`/
`reservationAvailability.test.ts`/`reservationTimezone.test.ts`/`submitReservation.test.ts` (Faz R.1A/
R.1A.1)/`respondToReservation.test.ts`/`respondToProposedChange.test.ts`/`reservationSweep.test.ts`
(Faz R.1B)/`staffAuthorization.test.ts` (Faz R.1B.1)/`assignReservationTable.test.ts` (Faz R.1C.1)/
`qrTableProtectionEnforcement.test.ts`/`openReservationTable.test.ts`/`closeReservationTable.test.ts`
(Faz R.1C.2)/`reservationPreorder.test.ts` (Faz R.1D.1, 38 numbered scenarios — see that file's own
header for which 2 live elsewhere as a Dart test and a full-suite-regression proof instead)/
`reservationPreorderKdsRelease.test.ts` (Faz R.1D.2, 33 numbered scenarios — see that file's own header
for which ones are pure-function-only and which are explicitly not independently testable this phase),
run via `npm run test:emulator` (**353/353 passing — three consecutive fully green full-suite runs** as
of Faz R.1D.2, up from 331 at Faz R.1D.1 — see `package.json`'s `test:emulator` script — requires
`functions/.env.local` to exist, see the App Check section above). `node --test --test-concurrency=1`
(Faz R.1A.1's own reliability fix) remains in place, unchanged.

**Test-isolation namespacing (Faz R.1C.1.1)**: every test file that generates Firestore document ids or
phone numbers via a counter (`nextId`, `nextOrganizationId`/`nextRestaurantId`/`nextBranchId`) now folds
in a per-file random `TEST_RUN_ID`/`PHONE_NAMESPACE` seeded once at module load. Root cause: a bare
per-file counter starting at 0 gave no cross-*file* uniqueness guarantee — two files could
independently generate the identical `branch-87`/`area-88` and silently share the same Firestore
document, a real bug proven via injected diagnostics (`docs/decisions.md` ADR-027 Faz R.1C.1.1), not
theoretical. Any *new* test file that generates its own entity ids must follow this same pattern — a
bare `idCounter += 1` counter is no longer sufficient.

**`staffAuthorization.ts`** (Faz R.1B.1) — generic, permission-based tenant-staff authorization,
replacing the role-name-list check `reservationAuthorization.ts` originally hardcoded. `roleHasPermission
(role, permission, rolePermissions = DEFAULT_STAFF_ROLE_PERMISSIONS)` mirrors `RolePermissionMap`'s own
tiering, as a genuinely data-driven resolver (the mapping is a parameter, not a hardcoded branch) —
`requireStaffPermission(request, organizationId, permission)` is the callable-facing entry point every
future tenant-staff-authorized callable can reuse. `reservationAuthorization.ts`'s
`requireReservationManagerPermission` is now a one-line delegation onto it.
`npm run migrate:catalog` (or `npm run seed:dev-all` for the full tenant+QR+catalog chain in one
emulator session) exports and migrates the real, full canonical catalog **and its pricing policy**
described above.

**Closed, Faz D.3.1.1**: `npm run seed:dev-all` now provisions `channelPricingPolicies/{restaurantId}`
itself (via `migrate_canonical_catalog.mjs`, above) — a fresh emulator bootstrap via `seed:dev-all` alone
(no other seed command) is sufficient for `submitTakeawayOrder` to price a takeaway order, proven by a
fresh-emulator run of `scripts/e2e_takeaway_real_catalog.mjs` immediately after `seed:dev-all`'s own
chain, no `seed_dev_catalog.mjs` step involved. See `docs/decisions.md` ADR-027 Faz D.3.1.1.

**Faz R.3A — Staff Identity Foundation + Admin Reservation Operations.** Two genuinely new backend
surfaces:

1. **Staff identity foundation** (`src/staffMembership.ts`, `src/staffAuthorization.ts` extended) —
   scoped, deliberately not the full Sprint 9E migration. `memberships/{organizationId}_{uid}` (the
   "minimal shape" collection `docs/firestore_data_model.md` already reserved since Sprint 9B) is now
   real, populated data, written by real callables: `bootstrapFirstAdminAccount` (the one
   self-authorizing exception, mirrors `BootstrapFirstAdminAccount.dart`'s "no existing admin to
   authorize the first one" reasoning), `registerStaffMember`, `assignStaffRole`/`revokeStaffRole`
   (role-scoped: `manageStaffAdminRole` for granting `admin` itself, `manageStaffRoles` for anything
   else — mirrors `AssignStaffRole.dart`'s exact split, including "no self-promotion"),
   `grantStaffBranchAccess`/`revokeStaffBranchAccess`, `setStaffMemberStatus` (archived is terminal).
   `syncOwnStaffClaims` derives `organizationAccess`/`roles` custom claims entirely server-side from a
   caller's own *active* `memberships` documents — the caller supplies nothing, so there is nothing for
   a malicious payload to influence. **Deliberately not covered**: `staffMembers` (the fuller
   admin-display record — display name, audit trail), and the Dart-side `StaffMember`/
   `InMemoryStaffMemberRepository`/`ActorSession` derivation, which remains client-side/in-memory as
   before (`ActorSession` is a UI-gating concept only; real backend authorization is 100% derived from
   `memberships`, independently). `functions/scripts/seed_dev_staff.mjs` (`npm run seed:dev-staff`)
   seeds a real dev admin account (`admin@abakus.dev`) via the real callables, never a direct Firestore
   write.
2. **Admin reservation operations** — `manageBranch` (new `StaffPermission`, mirrors the pre-existing
   Dart `PosAuthorizedAction.manageBranch` tiering exactly: manager/admin/tenantOwner, same tier as
   `manageReservations`), `updateBranchOperatingHours`/`getBranchOperatingHours` (the write side Faz
   R.2's own `branchOperatingHours.ts` comment anticipated but deliberately left unbuilt — HH:mm
   client-facing shape, strict overlap/format validation, `manageBranch`-gated), `listReservationsForBranch`
   (bounded date-range query + in-memory status/area filtering, cursor pagination — never an unbounded
   collection scan), `listReservationTablesForArea` (reuses `assignReservationTable`'s own
   `checkTableOccupancyConflict` logic so the preview can never drift from what assignment actually
   does), `getReservationBranchInfoForStaff` (the staff-facing sibling of the customer-only
   `getReservationBranchInfo`). `assignReservationTable`/`openReservationTable`/`closeReservationTable`/
   `respondToReservation` (Faz R.1B/R.1C.1/R.1C.2, unchanged) are reused as-is from the admin UI — no
   new backend surface needed for confirm/reject/propose/table-assignment/table-session actions
   themselves. See `docs/decisions.md` ADR-027 Faz R.3A for the full report, including the two real
   Dart-side production bugs this phase's own required tests found and fixed (a Riverpod build-phase
   provider-mutation crash and a responsive-layout tablet gap/mobile overflow — neither backend).

**Faz R.3B — Cancellation + Completed + No-Show Terminal Lifecycle.** Three new callables closing the
Reservation lifecycle's remaining terminal states:

1. **`cancelReservation`** — one callable for both customer and staff cancellation; the actor is
   resolved entirely server-side (`src/reservationCancellationAuthorization.ts`, never a client-
   supplied `actorType`): a caller whose own uid equals `Reservation.customerId` (real phone auth
   required) resolves as customer, otherwise as staff only if they independently hold
   `manageReservations` for the reservation's own organization. Customer cancellation is bound by
   `ReservationPolicy.customerCancellationCutoffMinutes` (server clock only); staff is exempt. LOCKED
   preorder rule: a preorder already released to the kitchen
   (`isReservationPreorderReleasedToKitchen`, `src/reservationPreorder.ts`, decided from the canonical
   Order status machine, never from `kitchenReleaseAt` presence alone) blocks a customer's own
   self-cancellation but never blocks staff, and is never auto-cancelled by staff either — a
   still-`pendingConfirmation` preorder, by contrast, is always auto-cancelled with the Reservation for
   both actors.
2. **`completeReservation`/`markReservationNoShow`** — both staff-only (`manageReservations`), both
   require the reservation's own `confirmedTime` to have already passed (server clock, no invented
   grace period). `completeReservation` never touches a linked preorder. `markReservationNoShow`
   mirrors `cancelReservation`'s own LOCKED preorder rule exactly.
3. **Shared cleanup** (`src/reservationTerminalCleanup.ts`, new) — every terminal transition away from
   `confirmed` releases area capacity, physical table occupancy, this reservation's own QR protection
   membership (never another reservation's), and deactivates a live table context, identically
   regardless of which of the three callables produced it. `src/reservationHoldOps.ts` gained
   `releaseConfirmedCapacity` — the mirror image of the existing `claimConfirmedCapacityDirectly`,
   recomputing bucket ids deterministically from `confirmedTime`/`confirmedAreaId`/policy (a confirmed
   Reservation's `activeHoldId` is always `null`, so there's no hold document left to read bucket ids
   from).
4. **Firestore Rules — new invariant.** `tableGuestSessions` are deliberately never deleted on a
   terminal transition (a customer's own cart/order history for their visit must survive), so
   `firestore.rules` gained `reservationContextIsOrderable(data)`: whenever an order's
   `reservationContextId` is non-null, the referenced Reservation must both exist and currently be
   `status == 'confirmed'` — closing a real, previously-undetected gap where a terminal reservation's
   own (never-deleted) table-session could otherwise place a new linked order. Ordinary walk-in orders
   (`reservationContextId == null`) are completely unaffected.
5. **Outbox extended** — `reservationCancelled`/`reservationCompleted`/`reservationNoShow` extend
   `ReservationEventType` (`src/reservationEvents.ts`), atomic with their own transition, carrying
   `actorType`/`actorId` (never a role name or other claims content).

See `docs/decisions.md` Faz R.3B for the full report, including the two real bugs this phase's own
required tests found and fixed (a test-infrastructure clock problem — `submitReservation` always
requires a future `requestedTime`, so testing "confirmedTime has passed" needed a dedicated
directly-seeded fixture — and a real admin error-message-mapper ordering bug where a more specific
check was shadowed by an older, more general one).

**Faz R.3C — Real KDS Ingestion + Reservation Notification Delivery (Reservation module's final
operational closure phase).** One new Firestore trigger, no new callables:

1. **`onReservationEventCreated`** (`src/reservationNotificationDelivery.ts`) — an
   `onDocumentCreated("reservationEvents/{eventId}", ...)` trigger that is now the sole *consumer* of
   the `reservationEvents` outbox this codebase has written since Faz R.1B (that outbox's own writer
   side is completely unchanged by this phase). `processReservationEventForDelivery(db, eventId,
   event, sender)` is exported standalone (mirrors `buildPreorderKdsReleasePatch`/
   `runPreorderKdsReleaseSweep`'s pure-function/thin-trigger-wrapper split): classifies the event type
   via `buildReservationNotificationCopy` (six of the ten existing types notify — see the function's
   own doc comment for the full, explicit inclusion/exclusion reasoning), claims
   `reservationNotificationDeliveries/{eventId}` via `.create()` (fails on `ALREADY_EXISTS`/code 6 —
   the exact same exactly-once pattern `onOrderCompleted.ts` already established, claimed *before* any
   send is attempted, never after), resolves the Reservation's `customerId`, looks up active
   `deviceTokens`, sends, and records delivery state. A duplicate trigger invocation for the same event
   (Firestore's platform-guaranteed "at least once," never "exactly once") always hits the existing
   claim and skips re-sending.
2. **`PushSender` seam** — production wires `defaultSender()`, which detects the local emulator/test
   context via `process.env.FIRESTORE_EMULATOR_HOST`/`FUNCTIONS_EMULATOR` (the same detection
   `appCheckConfig.ts`'s `shouldEnforceAppCheck` already established) and substitutes a safe no-op that
   never calls Google's real FCM API — every other part of the pipeline (idempotency claim, recipient
   resolution, delivery-record bookkeeping) still runs for real against the Firestore emulator. Tests
   call `processReservationEventForDelivery` directly with an explicit fake `PushSender` for full
   control — no test in this suite depends on real external FCM.
3. **No Firestore Rules change was needed.** `reservationEvents` was already fully client-write-denied
   (unchanged since it was introduced); the new `reservationNotificationDeliveries` collection has no
   rule of its own at all, covered by the pre-existing default-deny match — both confirmed by new
   tests, not merely assumed.
4. **KDS is Dart-side, not a new backend surface** — `FirestoreKitchenTicketRepository`
   (`lib/features/pos/data/`) reads directly from the existing `orders` collection with no new Cloud
   Function; the only backend-adjacent change is the new `orders(branchId ASC, status ASC)` composite
   index in `firestore.indexes.json`.

See `docs/decisions.md` Faz R.3C for the full report, including the real cross-customer device-token-
reassociation bug this phase's own required research found and fixed in the Dart
`RegisterDeviceToken` use case (backend-adjacent, not a Functions-source change — ~~superseded by Faz
R.3C.1~~, see immediately below).

**Faz R.3C.1 — Final Production Safety Audit + Hardening.** Two new Functions-source pieces, both
closing REQUIRED findings from an audit of R.3C's own report before accepting its closure verdict:

1. **`reservationNotificationRetrySweep`** (`src/reservationNotificationDelivery.ts`,
   `onSchedule("every 5 minutes")`) — R.3C's `onReservationEventCreated` claimed a delivery record via
   `.create()` and never revisited it; a send failure between the claim and the actual FCM call
   permanently lost the notification (any retry hit `ALREADY_EXISTS` and gave up). Replaced with a
   `pending`/`delivered`/`skipped`/`permanentlyFailed` lease/retry state machine
   (`attemptCount`/`nextAttemptAt` doubling as both retry backoff and a stale-claim visibility timeout,
   capped at 5 attempts) — this scheduled function is the actual retry driver, mirroring
   `reservationPreorderKdsRelease`'s own bounded-query/per-candidate-transaction/failure-isolation
   shape. Requires the new composite index
   `reservationNotificationDeliveries(status ASC, nextAttemptAtTimestamp ASC)`.
2. **`registerDeviceToken`** (`src/registerDeviceToken.ts`, new `onCall`) — R.3C's client-side
   cross-customer-reassociation fix could not actually run against real Firestore:
   `firestore.rules`'s `deviceTokens` read rule only ever lets a caller see their own documents, so a
   different customer re-registering the same physical token could not detect the conflict at all,
   silently creating a second document instead. This callable does the find-and-reassociate logic with
   the Admin SDK (which can see across owners) inside one transaction; `uid` is always
   `request.auth.uid`, never client-supplied. `firestore.rules`'s `deviceTokens` `create` is now
   `if false` (Cloud-Function-only) — direct client creation is retired, since per-document rules
   cannot dedupe a `token` field value across different document IDs the way this transaction can.

See `docs/decisions.md` Faz R.3C.1 for the full audit report, including the KDS branch-authorization
finding (documented/proven, not a code change — `firestore.rules`'s `orders` read rule and this
codebase's existing `listReservationsForBranch.ts` precedent were already organization-scoped, not
branch-scoped, before this phase).

## What does NOT exist yet — stated plainly

This sprint delivers the **outbox writer**, not the **outbox consumer**. `orderEvents/{orderId}-completed`
records `visitRecorded: false`, `rewardsEvaluated: false`, `stockConsumed: false` — honest markers for
what a future sprint still needs to do, not implied as already handled. Specifically, **not
implemented**:

- Kitchen-eligibility triggers (order confirmed → kitchen ticket becomes actionable).
- Delivery-creation on `ready` + `channel == delivery` (the Dart `CreateDelivery` use case already
  does this, but only when invoked from Dart — no Cloud Function invokes it, and nothing about it has
  been ported to TypeScript).
- Visit-recording → reward-evaluation → stock-consumption on order completion. These are real, tested
  Dart use cases today (`RecordCustomerVisitAndEvaluateRewards`, `ConsumeStockForOrder`, and related
  CRM/inventory logic) — reimplementing that business logic a second time, in TypeScript, so a Cloud
  Function could execute it server-side, is a substantial undertaking of its own. It is deliberately
  **not attempted partially** here (a half-ported reward/stock rule would be worse than none — silently
  wrong business behavior, not an honest gap). `onOrderCompleted`'s outbox record is the real, durable,
  idempotent trigger point that work would consume from.
- Cancellation/refund reversal events.
- ~~A `memberships` → custom-claims sync function~~ — **closed, Faz R.3A, scoped.** `syncOwnStaffClaims`
  (`src/staffMembership.ts`) now exists and is real — but only for the narrow purpose Faz R.3A actually
  needed (deriving `manageReservations`/`manageBranch` custom claims from `memberships` documents). It
  is **not** the full Sprint 9E `memberships`/`staffMembers` write-side migration referenced below —
  see "Faz R.3A — Staff Identity Foundation" for exactly what is/isn't covered.
- ~~An `organizations` provisioning function~~ — **closed, Faz D.1.1.** `provisionOrganization`
  (`src/provisionOrganization.ts`) now exists; `provisionRestaurant` verifies its parent organization's
  existence and `isActive` status server-side rather than validating `organizationId` structurally
  only. Faz D.1's own REQUIRED finding is resolved.
- ~~`submitTakeawayOrder`~~ — **closed, Faz D.3.** Server-authoritative order creation now exists for
  both takeaway scenarios; see above.
- ~~Full menu catalog content migration~~ — **closed, Faz D.3.1.** The real, full catalog (not a
  representative subset) is now migrated from the real Dart source; see "Full canonical catalog
  migration" above.
- ~~Faz C authenticated-takeaway Flutter migration~~ — **closed, Faz D.3.1.** `TakeawayCheckoutScreen`
  now calls `submitTakeawayOrder`; the old direct-Firestore-create rules branch is removed. Takeaway now
  has exactly one live, server-authoritative order-creation mechanism for both scenarios.
- App Check **enforcement is App-Check-ready, not yet activated in production** on all six public/
  callable Functions this app exposes to an end-user client:
  `resolveTakeawayQrToken`/`openTakeawayGuestSession`/`submitTakeawayOrder` (Faz D.3),
  `resolveTableQrToken`/`openTableGuestSession` (Faz D.3.2, closing Faz D.3's own REQUIRED finding), and
  `processAccountDeletion` (**Faz D.3.2.1**) — all six wire the exact same `appCheckConfig.ts`'s
  `shouldEnforceAppCheck()`, never a per-function or per-domain copy, verified by
  `src/test/appCheckConfig.test.ts`'s real module-wiring inspection.

  **`ENFORCE_APP_CHECK` is a real Cloud Functions v2 Parameter (Faz D.3.2.1)** —
  `firebase-functions/params`'s `defineBoolean("ENFORCE_APP_CHECK", { default: false, ... })`, not a raw
  `process.env` read. This is the actual, documented Firebase mechanism for deployment configuration:
  declared parameters are discoverable via the Firebase CLI/Console instead of living as an invisible,
  undocumented environment variable. Runtime resolution is unchanged in behavior from before (`=== "true"`
  exact-string-match, fails closed against a typo like `"TRUE"`/`"1"` silently *enabling* enforcement it
  shouldn't) — this migration changes *visibility*, not *parsing*.

  **Terminology correction (Faz D.3.2.1)**: an earlier version of this doc, and a test title, described
  the *absence* of `ENFORCE_APP_CHECK` outside the emulator as a "safe default"/"fails closed." That was
  backwards — `false` outside the emulator means enforcement is **OFF** (fail-*open*), and a deployment
  that forgets to set this parameter was, until this phase, silently unprotected with no signal
  whatsoever. Only two things are genuinely fail-closed here: (1) the emulator short-circuit — nothing
  can turn enforcement *on* against a local emulator, regardless of `ENFORCE_APP_CHECK`'s value; (2) the
  strict `"true"`-only string match — a typo can't accidentally enable enforcement. The *default absence*
  case outside the emulator is not, and is now handled by a loud runtime warning instead of silence: if
  enforcement resolves `false` outside the emulator, `shouldEnforceAppCheck()` logs one structured
  `logger.warn` (Firebase's own `firebase-functions/logger`, surfaced in Cloud Logging/the Console) per
  cold start, naming the exact condition. A deploy-time hard failure (a required Parameter with no
  default, so the CLI refuses to deploy without an explicit value) was considered and deliberately not
  implemented this phase — it would make every App-Check-ready Function undeployable until a real App
  Check provider exists for every platform, a materially larger decision than this task's scope; recorded
  as a RECOMMENDED follow-up for once a real production rollout is imminent.

  **Local dev/emulator note (Faz D.3.2.1)**: declaring `ENFORCE_APP_CHECK` as a Parameter means the
  Firebase CLI's Functions-discovery step now knows about it — and, empirically verified via a controlled
  A/B test (see `docs/decisions.md` ADR-027 Faz D.3.2.1), `firebase emulators:start`/`emulators:exec`
  opens an **interactive CLI prompt** ("Enter a boolean value for ENFORCE_APP_CHECK") during that
  discovery step even though the Parameter has a `default`. Since `emulators:exec` runs non-interactively
  (no attached TTY), that prompt blocks forever with no way to answer it — this broke every emulator-
  backed test run after the Parameter was introduced, confirmed by the discovery log ending exactly at
  the prompt line with Functions discovery/manifest generation otherwise complete and successful.
  `functions/.env.local` (git-ignored — see `.gitignore`) supplies `ENFORCE_APP_CHECK=false` so the CLI
  finds a value up front and never prompts; this is Firebase's own supported `.env.local` mechanism for
  local/CLI-only Parameter overrides, changes no runtime behavior (the value matches the code's own
  `default`), and is required for `npm run test:emulator` to work at all now that this Parameter exists.

### Production deployment prerequisites (App Check)

Activating `ENFORCE_APP_CHECK=true` without a real App Check provider actually provisioned for the
target Firebase project would lock every legitimate client out too — both steps are required together,
not just the environment variable:

1. **`ENFORCE_APP_CHECK=true`** set on the deployed Cloud Functions runtime — since this is now a
   declared Parameter (Faz D.3.2.1), set it via the target project's `.env.<project-id>` file (Cloud
   Functions v2's own Parameters mechanism) or the interactive prompt `firebase deploy` shows for any
   unconfigured Parameter; never via `functions/.env.local` (local/emulator-only, git-ignored).
2. **A real App Check provider actually provisioned** for the target Firebase project, per platform —
   the Flutter client side (`lib/core/services/app_check/firebase_app_check_service.dart`) is already
   fully provider-aware and requires no further Dart code change once these exist:
   - **Web** — a reCAPTCHA Enterprise site key, supplied to `FirebaseAppCheckService` via
     `webRecaptchaEnterpriseSiteKey`; currently unset, so Web App Check stays unactivated (logged, not
     thrown) regardless of the server-side toggle. **This is the one platform-specific prerequisite most
     likely to be missed** — the takeaway QR flow is deliberately web-reachable (a customer scans a
     kasadaki QR in a browser), so a production `ENFORCE_APP_CHECK=true` rollout without a real web site
     key configured would lock out exactly that flow's real users, not just abusers.
   - **Android** — Play Integrity (already the non-debug default; no further provisioning beyond normal
     Play Console app registration).
   - **iOS/macOS** — App Attest with DeviceCheck fallback (already the non-debug default; no further
     provisioning beyond normal App Store Connect registration).
   - **Windows** — no non-debug provider exists in the current `firebase_app_check` version; Windows
     stays without App Check outside development, by design (not a gap to close before deploying —
     `FirebaseAppCheckService`'s own documented limitation).

## Why the order-status table is duplicated in TypeScript

`src/orderStatus.ts` mirrors `lib/features/orders/domain/models/order_status.dart`'s 11-state
transition table by hand — this repository has no Dart↔TypeScript code-sharing mechanism, and the
Flutter app and these Cloud Functions are two different runtimes. Keeping the two tables in sync by
hand is an accepted, documented risk for this sprint's scope: the Dart file remains the source of truth
for the *design* of the state machine; this is its server-side enforcement mirror. A drift-detection
test (comparing the two tables programmatically) is a reasonable future addition, not built this
sprint.

## Running the tests

```
cd functions
npm install
npm run test:emulator
```

Requires JDK 21+ for the Firestore Emulator (see `docs/firebase_emulator.md`) and Node 18+ locally
(the `engines.node: "20"` in `package.json` targets the Cloud Functions *deployment* runtime — local
emulation works under a newer local Node with an advisory warning, not an error).

## Local project id

`.firebaserc` sets a `demo-` prefixed default project id (`demo-abakus-one-emulator`) — the
Firebase-recommended pattern for an emulator-only project, which can never resolve against a real GCP
project even if real credentials were somehow present locally. `src/test/functions.test.ts` uses the
same id explicitly so the test process's Firestore writes land in the same emulated project namespace
the Functions emulator is watching.

## Platform Owner bootstrap and break-glass recovery (AP-2)

The very first Platform Owner account(s) are created by `scripts/bootstrap_platform_owner.mjs`, run
manually against a real project by an operator holding real GCP credentials — never a Cloud Function,
never reachable from the deployed app:

```
cd functions
GCLOUD_PROJECT=<real-project-id> node scripts/bootstrap_platform_owner.mjs <uid1> [uid2] [...]
```

It refuses to run a second time once any `platformMembers` document already holds an active
`platformOwner`/`platformAdministrator` role — every subsequent grant goes through the real
`grantPlatformRole` callable instead (itself Platform-Owner-authorized, self-grant forbidden).

**Break-glass recovery — if every Platform Owner account is ever lost** (all accounts deleted/
compromised/inaccessible): this script's own refusal check means it will NOT run again while any
`platformMembers` document still claims an active owner/administrator role, even one nobody can sign
into anymore. Recovery is a GCP-IAM operation, not an application feature:

1. A trusted operator is granted temporary `roles/datastore.user` (or an equivalent scoped Firestore
   read/write role) on the real GCP project via GCP IAM — outside this application entirely.
2. Using that access, the operator sets every existing `platformMembers` document's `status` to
   `"archived"` (or deletes the stuck documents) via the Firebase Console or `gcloud`/Admin SDK — a
   manual, audited, one-time action, not a code path this repository ships.
3. `bootstrap_platform_owner.mjs`'s refusal check now passes (no active owner/administrator remains),
   and it is run again for the new trusted uid(s).
4. The operator's elevated IAM role is revoked immediately after.

This is deliberately NOT implemented as an in-app "recovery mode" or a second bootstrap mechanism —
doing so would recreate exactly the reusable backdoor risk the real bootstrap script's own refusal
check exists to prevent (`BR-PLATFORM-003`). The GCP IAM layer is the actual break-glass boundary.

## AP-2 final wiring (2026-08-27) — new callables, Platform Owner sign-in gap closed

Three new/extended callables, all exported from `src/index.ts`:

- `suspendTrustedDevice`/`retireTrustedDevice` (`src/trustedDevice.ts`) — `manageDevices`-permission-
  gated, alongside the pre-existing `revokeTrustedDevice`. Neither has a matching "un-suspend"/
  "un-retire" callable this phase, mirroring `revokeTrustedDevice`'s own long-standing lack of an
  "un-revoke."
- `respondToApprovalRequest` (`src/remoteApproval.ts`) — gained an optional `reasonMessage` string,
  sanitized (`sanitizeReasonMessage`) and stored on the `approvalEvents` entry. Kept optional at this
  layer specifically so every pre-existing, already-tested call site (`trustedDeviceAndApproval.test.ts`)
  keeps working unchanged — the Flutter Approval Inbox enforces "mandatory reason" at its own client
  boundary instead.
- `firestore.rules`'s `remoteApprovalRequests` collection gained its first-ever client read path: the
  requester's own request, or a branch-scoped eligible responder whose role matches
  `RESPONSE_PERMISSION_BY_ACTION[actionType]` (today: `deviceActivation` -> `approveDeviceRegistration`
  -> manager/admin/tenantOwner). This mirrors the backend's own closed-allowlist map in the rules
  language — a second `ApprovalActionType` in AP-3+ needs a matching rules update, not a wider "any org
  member" fallback.

**A real, pre-existing gap closed, not new scope**: `FirebasePlatformAuthRepository.signIn`
(`lib/features/platform/data/platform_auth_repository.dart`, built well before this pass) already called
`platformMemberRepository.findByAuthUid(result.uid)` against a real Firebase Auth sign-in result — but
no Firestore-backed `PlatformMemberRepository` implementation existed anywhere in `lib/`, so a real
Platform Owner sign-in could never actually succeed against a deployed backend. `lib/features/platform/
data/firebase_platform_member_repository.dart` closes this: it reads `platformMembers/{uid}` directly
(that collection's own rule already required `isPlatformMember()`, itself requiring a synced
`platformRole` custom claim — `syncOwnPlatformClaims` is called first on every lookup to resolve that
ordering, mirroring `StaffClaimsSyncClient`'s identical role for the tenant-staff stack one tier down).

No new Cloud Function was needed for the Platform Owner console's tenant picker or the entitlement
console's pre-mutation read — both use direct Firestore reads (`firestore.rules`'s `organizations` and
`entitlements` collections each gained a narrow, read-only `isPlatformMember()` exception, additive to
their existing rules, never replacing the existing `isOrgMember`/`hasActiveSupportGrant` paths for
tenant-side/support-grant readers).
