import { createHash } from "crypto";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { resolveActiveReservationBranch, resolveReservationArea } from "./reservationScope";
import { MINIMUM_ADVANCE_MINUTES } from "./reservationConfig";
import {
  isMinuteAligned,
  checkAreaCapacity,
  type ReservationSlotBucket,
} from "./reservationAvailability";
import { isWithinBookingHorizon } from "./reservationTimezone";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { loadBranchOperatingHours, isWithinOperatingHours } from "./branchOperatingHours";
import { loadCanonicalChannelPricingPolicy } from "./takeawayCatalog";
import {
  parsePreorderRequest,
  normalizePreorderItems,
  buildPreorderLines,
  computePreorderPriceBreakdown,
  buildPreorderOrderDocument,
  derivePreorderOrderId,
  resolvePreorderOrderRef,
} from "./reservationPreorder";
import {
  LOYALTY_ACCOUNTS_COLLECTION,
  LOYALTY_LEDGER_ENTRIES_COLLECTION,
  deriveLoyaltyLedgerEntryId,
  type LoyaltyLedgerEntry,
} from "./loyaltyLedger";
import {
  loyaltyPolicyDocRef,
  loyaltyPolicyBootstrapRef,
  readLoyaltyPolicyInTransaction,
  writeDefaultLoyaltyPolicyInTransaction,
  type LoyaltyPolicy,
} from "./loyaltyPolicy";
import { calculateBoncukRedemption, resolveAccountForRedemption } from "./loyaltyRedemption";
import type { LoyaltyAccountData } from "./getCustomerLoyaltySnapshot";
import { boncukError, type SelectedBenefitType } from "./boncukRedemptionErrors";
import { findFirstEligibleCartProductId, type CatalogRewardOrderSnapshot } from "./submitTakeawayOrder";
import {
  loadLoyaltyRewardForRedemption,
  resolveCatalogRewardRedemption,
} from "./resolveCatalogRewardRedemption";
import {
  isRewardCurrentlyValid,
  loyaltyRewardCatalogVersionDocId,
  type LoyaltyRewardCatalogEntry,
  type CanonicalCommercialChannel,
} from "./loyaltyRewardCatalog";
import {
  CAMPAIGNS_COLLECTION,
  parseCampaignDefinition,
  type CampaignDefinition,
  type CampaignOrderSnapshot,
} from "./campaignEngine";
import { isCampaignScheduleCurrentlyOpen } from "./campaignScheduling";
import { resolveCampaignDiscount } from "./campaignPricing";
import { reserveCampaignUsage } from "./campaignUsage";

/**
 * Server-Authoritative Campaign Engine P8-C.2 (2026-08-25) — the real,
 * server-derived commercial channel of every preorder Order this callable
 * ever creates. Mirrors `submitDeliveryOrder.ts`'s own
 * `DELIVERY_COMMERCIAL_CHANNEL` exactly.
 */
const RESERVATION_PREORDER_COMMERCIAL_CHANNEL: CanonicalCommercialChannel = "reservationPreorder";

/**
 * Server-authoritative reservation creation — Faz R.1A implementation of
 * the `docs/decisions.md` ADR-027 Faz R.0–R.0.7 design. Mirrors
 * `submitTakeawayOrder.ts`'s own shape closely (validation helpers,
 * transaction, idempotency-by-derived-id) — the same "backend is the sole
 * authority" principle, applied to a new aggregate rather than a new
 * pattern.
 *
 * **Real, phone-verified customer identity only (Faz R.0.6 §8)** — an
 * anonymous technical identity is rejected outright, `permission-denied`.
 * This is a deliberate departure from the takeaway/dine-in QR guest model:
 * reservations require a real, contactable customer, never a guest.
 *
 * **Full slot never rejects the request (Faz R.0.3 §1, R.1A's own explicit
 * product rule)** — a Reservation is always created, `status:
 * 'pendingRestaurantApproval'`; only whether an `initialRequest` hold also
 * gets created depends on capacity at submission time. The restaurant's own
 * alternative-proposal workflow (Faz R.0.3 §6) is a later phase's job — not
 * built here.
 *
 * **No physical table concepts** — `assignedTableId`,
 * `reservationTableProtections`, `activeReservationTableContext`,
 * `tableProtectionMinuteBuckets` all belong to a later phase (Faz R.0.4–
 * R.0.6's own design). This function never reads or writes any of them.
 *
 * **Optional preorder — Faz R.1D.1.** The request may carry an optional
 * `preorder: { items: [...] }` field (`reservationPreorder.ts`). When
 * present, a second aggregate — a `reservationPreorder`-channel `orders`
 * document, server-priced against the canonical catalog at table/base
 * price (no Gel Al/delivery surcharge) — is created atomically in this
 * same transaction, linked via `Order.reservationContextId ==
 * reservationId` and `Reservation.preorderOrderId`. When absent (the
 * default), this callable's behavior is byte-for-byte what Faz R.1A/R.1B
 * already established: no `orders` document is ever touched. Faz R.1A's
 * own original instruction ("Do not create a fake partial Order") is still
 * honored — a real preorder Order is only ever created together with, and
 * atomically consistent with, its Reservation, never a fake placeholder.
 *

 * **Faz R.1A.1 REQUIRED fix #2 — verified phone source.** `contactPhone`
 * is no longer a client-supplied field at all. Since phone-auth is already
 * required (above), the caller's own Firebase Auth ID token already
 * carries a verified `phone_number` claim (the standard Firebase phone-auth
 * claim — mirrors this codebase's own client-side convention,
 * `AuthSession.phoneNumber`/`FirebaseAuthResult.phoneNumber`, which is
 * likewise always the *verified* post-OTP phone, never a free-typed field).
 * `Reservation.contactPhone` is derived from that claim, never from
 * anything in `request.data` — a client sending a different phone number
 * in its payload has no effect on the stored value, because the field
 * isn't read from the payload at all. `contactFirstName`/`contactLastName`
 * remain client-supplied snapshots (no verified-identity source exists for
 * a display name) — sanitized/validated exactly as before.
 *
 * **Faz R.1A.1 REQUIRED fix #3 — timezone-aware booking horizon.**
 * `ReservationPolicy.bookingHorizonDays` is resolved against the branch's
 * own `timezone` via `reservationTimezone.ts`'s `isWithinBookingHorizon`
 * (Node's built-in `Intl`/ICU timezone database — no new dependency) —
 * "60 days" means 60 *calendar days* in branch-local terms, DST-correct,
 * never a bare `serverNow + 60*24h` epoch approximation.
 */

const MAX_CONTACT_FIELD_LENGTH = 100;
const MAX_SUBMISSION_KEY_LENGTH = 200;
const MAX_PARTY_SIZE_HARD_CAP = 100; // a structural safety net independent of ReservationPolicy.maxPartySize — mirrors submitTakeawayOrder.ts's own MAX_ITEM_QUANTITY precedent (a backend-only bound, never business-rule-derived).

/** Mirrors submitTakeawayOrder.ts's own DISALLOWED_CONTACT_CHARACTERS exactly — the same structural (not full-sanitizer) safety net. */
const DISALLOWED_CONTACT_CHARACTERS = /[<>]/;

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

/** Mirrors submitTakeawayOrder.ts's sanitizeContactField verbatim — no shared module exists between the two callables yet (that file's own precedent: local duplication, not a premature shared abstraction). */
function sanitizeContactField(raw: unknown, fieldName: string): string {
  if (typeof raw !== "string") invalid(`${fieldName} is required.`);
  const trimmed = (raw as string).trim();
  if (trimmed.length === 0) invalid(`${fieldName} must not be empty.`);
  if (trimmed.length > MAX_CONTACT_FIELD_LENGTH) invalid(`${fieldName} is too long.`);
  if (DISALLOWED_CONTACT_CHARACTERS.test(trimmed)) {
    invalid(`${fieldName} contains disallowed characters.`);
  }
  return trimmed;
}

/**
 * Sanity-checks the *verified* phone claim from the caller's own ID token
 * — defense-in-depth, not the authorization boundary (that's phone-auth
 * being required at all, checked before this is ever called). Firebase's
 * own `phone_number` claim is already E.164-shaped by construction; this
 * only guards against an unexpectedly empty/malformed claim reaching the
 * stored record.
 */
function sanitizeVerifiedPhone(raw: unknown): string {
  if (typeof raw !== "string" || raw.trim().length === 0) {
    throw new HttpsError(
      "failed-precondition",
      "The authenticated identity has no verified phone number on its auth token.",
    );
  }
  const trimmed = raw.trim();
  const digitsOnly = trimmed.replace(/[\s\-().]/g, "");
  if (!/^\+?[0-9]{7,15}$/.test(digitsOnly)) {
    throw new HttpsError(
      "failed-precondition",
      "The authenticated identity's verified phone number is malformed.",
    );
  }
  return trimmed;
}

function sanitizeSubmissionKey(raw: unknown): string {
  if (typeof raw !== "string" || raw.length === 0) invalid("submissionKey is required.");
  if (raw.length > MAX_SUBMISSION_KEY_LENGTH) invalid("submissionKey is too long.");
  return raw;
}

function sha256Hex(input: string): string {
  return createHash("sha256").update(input).digest("hex");
}

/** Mirrors submitTakeawayOrder.ts's deriveOrderId exactly — a different actor using the same key never collides; the same actor retrying with the same key always maps to the same document. */
function deriveReservationId(uid: string, submissionKey: string): string {
  return `reservation-${sha256Hex(`${uid}|${submissionKey}`)}`;
}

function computeRequestFingerprint(normalized: unknown): string {
  return sha256Hex(JSON.stringify(normalized));
}

/**
 * Boncuk Loyalty P6-B (2026-08-24) — the fully-resolved, not-yet-written
 * redemption effects, computed during this transaction's read phase and
 * applied only during its write phase (Firestore requires every `tx.get()`
 * to happen before any `tx.set()`/`tx.create()`). Mirrors
 * `submitDeliveryOrder.ts`'s own `PendingBoncukRedemption` exactly — same
 * shape, same fields, channel-neutral.
 */
interface PendingBoncukRedemption {
  accountRef: FirebaseFirestore.DocumentReference;
  account: LoyaltyAccountData;
  boncukUsed: number;
  ledgerEntryRef: FirebaseFirestore.DocumentReference;
  ledgerEntry: LoyaltyLedgerEntry;
  policy: LoyaltyPolicy;
  policyNeedsProvisioning: boolean;
  orderSnapshot: {
    boncukUsed: number;
    valueMinorUnits: number;
    remainingPayableMinorUnits: number;
    redemptionValueMinorUnitsPerBoncuk: number;
    maxRedemptionBasisPoints: number;
    loyaltyPolicyVersion: number;
  };
}

/** The catalog-reward sibling of [PendingBoncukRedemption] — mirrors `submitTakeawayOrder.ts`'s own `PendingCatalogRewardRedemption` exactly. */
interface PendingCatalogRewardRedemption {
  accountRef: FirebaseFirestore.DocumentReference;
  account: LoyaltyAccountData;
  boncukCost: number;
  ledgerEntryRef: FirebaseFirestore.DocumentReference;
  ledgerEntry: LoyaltyLedgerEntry;
  orderSnapshot: CatalogRewardOrderSnapshot;
}

export const submitReservation = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    // Faz R.0.6 §8 — canonical real-customer check, identical to
    // submitTakeawayOrder.ts's own isRealCustomer condition. request.auth
    // != null alone is never treated as customer authentication.
    const isRealCustomer = request.auth.token?.firebase?.sign_in_provider === "phone";
    if (!isRealCustomer) {
      throw new HttpsError(
        "permission-denied",
        "Reservation creation requires a phone-verified identity. Anonymous technical identities are not permitted.",
      );
    }
    const uid = request.auth.uid;
    // Faz R.1A.1 fix #2 — the sole source of contactPhone. Never read from
    // request.data; a client cannot influence this value at all.
    const contactPhone = sanitizeVerifiedPhone(request.auth.token?.phone_number);

    const data = (request.data ?? {}) as Record<string, unknown>;
    const submissionKey = sanitizeSubmissionKey(data.submissionKey);
    const contactFirstName = sanitizeContactField(data.contactFirstName, "contactFirstName");
    const contactLastName = sanitizeContactField(data.contactLastName, "contactLastName");

    if (typeof data.restaurantId !== "string" || data.restaurantId.length === 0) {
      invalid("restaurantId is required.");
    }
    if (typeof data.branchId !== "string" || data.branchId.length === 0) {
      invalid("branchId is required.");
    }
    if (typeof data.areaId !== "string" || data.areaId.length === 0) {
      invalid("areaId is required.");
    }
    const restaurantId = data.restaurantId as string;
    const branchId = data.branchId as string;
    const areaId = data.areaId as string;

    if (
      typeof data.partySize !== "number" ||
      !Number.isInteger(data.partySize) ||
      data.partySize <= 0
    ) {
      invalid("partySize must be a positive integer.");
    }
    const partySize = data.partySize as number;
    if (partySize > MAX_PARTY_SIZE_HARD_CAP) {
      invalid("partySize exceeds the maximum allowed.");
    }

    if (typeof data.requestedTime !== "string") {
      invalid("requestedTime is required.");
    }
    const requestedTime = new Date(data.requestedTime as string);
    if (Number.isNaN(requestedTime.getTime())) {
      invalid("requestedTime is not a valid date.");
    }
    // Faz R.0.7 §2 — checked here (cheap, no DB access needed) independently
    // of the slotIntervalMinutes alignment check below (which needs the
    // branch's own policy) — a non-minute-aligned timestamp is rejected
    // outright regardless of which branch/policy it targets.
    if (!isMinuteAligned(requestedTime)) {
      invalid("requestedTime must be minute-aligned (zero seconds and milliseconds).");
    }

    // Faz R.1D.1 §3 — cheap, DB-free request-shape validation only, done
    // here alongside every other request-shape check above. Catalog-backed
    // pricing/line-building happens later, inside the transaction.
    const parsedPreorder = parsePreorderRequest(data.preorder);

    const db = getFirestore();
    const reservationId = deriveReservationId(uid, submissionKey);
    const reservationRef = db.collection("reservations").doc(reservationId);

    return db.runTransaction(async (tx) => {
      // ---------------------------------------------------------------
      // Idempotency short-circuit — checked first, before any capacity
      // work, so a genuine retry never re-touches occupancy buckets at
      // all. Mirrors submitTakeawayOrder.ts's own existing-document
      // fingerprint-match-or-fail-closed pattern exactly.
      // ---------------------------------------------------------------
      const normalizedForFingerprint = {
        restaurantId,
        branchId,
        areaId,
        partySize,
        requestedTime: requestedTime.toISOString(),
        contactFirstName,
        contactLastName,
        contactPhone,
        // Faz R.1D.1 §5 — folded into the fingerprint so reusing
        // submissionKey with a *different* preorder (or adding/removing one
        // on retry) is caught by the same fail-closed "different payload"
        // check as every other field, not silently accepted. Boncuk Loyalty
        // P6-B (2026-08-24) — `requestedBoncukAmount` is included the same
        // way, mirroring `submitDeliveryOrder.ts`'s own §10 rule: a retry
        // that changes only the requested Boncuk amount is "a different
        // order payload," never silently accepted.
        preorder: parsedPreorder
          ? {
              items: normalizePreorderItems(parsedPreorder.items),
              requestedBoncukAmount: parsedPreorder.requestedBoncukAmount,
              // Boncuk Loyalty P7-D — same reasoning, for the mutually
              // exclusive catalog-reward selection.
              selectedRewardId: parsedPreorder.selectedRewardId,
              // Server-Authoritative Campaign Engine P8-C.2 — same
              // reasoning, for the mutually exclusive campaign selection.
              selectedCampaignId: parsedPreorder.selectedCampaignId,
            }
          : null,
      };
      const fingerprint = computeRequestFingerprint(normalizedForFingerprint);

      const existing = await tx.get(reservationRef);
      if (existing.exists) {
        const existingData = existing.data()!;
        if (existingData.submissionFingerprint !== fingerprint) {
          throw new HttpsError(
            "failed-precondition",
            "submissionKey was already used with a different reservation request.",
          );
        }
        return {
          reservationId,
          status: existingData.status as string,
          requestedAvailabilityAtSubmission: existingData.requestedAvailabilityAtSubmission as string,
          responseDeadlineAt: (existingData.responseDeadlineAt.toDate() as Date).toISOString(),
          preorderOrderId: (existingData.preorderOrderId as string | null | undefined) ?? null,
          duplicate: true,
        };
      }

      // ---------------------------------------------------------------
      // Scope + policy + area resolution — server-authoritative, never
      // trusting the client's own restaurantId/branchId/areaId claims
      // beyond "resolve and validate them against the real chain."
      // ---------------------------------------------------------------
      const scope = await resolveActiveReservationBranch(tx, db, { restaurantId, branchId });
      if (scope.status === "notFound") {
        throw new HttpsError("not-found", "Branch not found.");
      }
      if (scope.status === "invalid") {
        throw new HttpsError(
          "failed-precondition",
          "This branch is not currently accepting reservations.",
        );
      }
      const policy = scope.policy!;

      if (partySize > policy.maxPartySize) {
        invalid(`partySize exceeds the maximum allowed (${policy.maxPartySize}).`);
      }

      const area = await resolveReservationArea(tx, db, { branchId, areaId });
      if (area.status === "notFound") {
        throw new HttpsError("not-found", "Reservation area not found.");
      }
      if (area.status === "invalid") {
        throw new HttpsError(
          "failed-precondition",
          "This reservation area is not currently accepting reservations.",
        );
      }

      // ---------------------------------------------------------------
      // Time invariants — server clock only, never the client's. Faz
      // R.0.2's golden rule: 29:59 remaining -> REJECT, exactly 30:00 ->
      // ACCEPT (inclusive >=).
      // ---------------------------------------------------------------
      const now = new Date();
      const minimumTime = new Date(now.getTime() + MINIMUM_ADVANCE_MINUTES * 60_000);
      if (requestedTime.getTime() < minimumTime.getTime()) {
        throw new HttpsError(
          "failed-precondition",
          `requestedTime must be at least ${MINIMUM_ADVANCE_MINUTES} minutes from now.`,
        );
      }

      // Faz R.1A.1 fix #3 — branch-local *calendar-day* horizon, DST-correct
      // (reservationTimezone.ts), never a bare serverNow + N*24h epoch
      // approximation.
      if (!isWithinBookingHorizon(now, requestedTime, policy.bookingHorizonDays, policy.timezone)) {
        throw new HttpsError(
          "failed-precondition",
          `requestedTime is beyond the ${policy.bookingHorizonDays}-day booking horizon.`,
        );
      }

      // Slot-boundary alignment (Faz R.0.3's bucket architecture requires
      // this) — checked against absolute epoch time. This coincides with
      // branch-local wall-clock slot alignment for every real-world UTC
      // offset (all of which are themselves whole-minute, in practice
      // 15/30/45-minute, increments from UTC) — ReservationPolicy.timezone
      // is consulted for the calendar-day horizon check above, but slot
      // alignment itself stays pure epoch arithmetic (sub-day granularity,
      // where whole-minute UTC offsets already guarantee correctness).
      const slotMs = policy.slotIntervalMinutes * 60_000;
      if (requestedTime.getTime() % slotMs !== 0) {
        invalid(`requestedTime must align to a ${policy.slotIntervalMinutes}-minute slot boundary.`);
      }

      // Faz R.2 — branch operating hours are the authoritative source for
      // "is this branch even open at this requested instant," independent
      // of capacity. `getReservationAvailability` applies the identical
      // resolution client-side-facing, but this is the check that actually
      // enforces it — never trust the client's own calendar/slot-picker UI.
      const operatingHours = await loadBranchOperatingHours(db, branchId, tx);
      if (!isWithinOperatingHours(operatingHours, requestedTime, policy.timezone)) {
        throw new HttpsError(
          "failed-precondition",
          "requestedTime is outside this branch's operating hours.",
        );
      }

      const endTime = new Date(requestedTime.getTime() + policy.reservationDurationMinutes * 60_000);

      // ---------------------------------------------------------------
      // Capacity check + initial hold — Faz R.0.3's transaction-safe
      // bucket model. IMPORTANT PRODUCT RULE (R.1A's own explicit
      // instruction): a full slot never rejects the request — it only
      // means no hold is created.
      // ---------------------------------------------------------------
      const capacity = await checkAreaCapacity(db, tx, {
        branchId,
        areaId,
        areaCapacity: area.capacity!,
        start: requestedTime,
        end: endTime,
        slotIntervalMinutes: policy.slotIntervalMinutes,
        partySize,
      });

      const responseDeadlineAt = new Date(
        Math.min(
          now.getTime() + policy.restaurantResponseTimeoutMinutes * 60_000,
          requestedTime.getTime(),
        ),
      );

      // ---------------------------------------------------------------
      // Optional preorder — Faz R.1D.1 §4/§5/§16. Every catalog read here
      // (`tx.get()`-backed) still happens before any write below, so the
      // whole transaction's "all reads before all writes" invariant holds
      // — a full-slot-at-submission reservation (capacity.available ===
      // false, no hold) can still carry a preorder (§6's own explicit
      // rule); nothing about preorder creation depends on hold/capacity
      // outcome.
      // ---------------------------------------------------------------
      let preorderOrderId: string | null = null;
      let preorderOrderDocument: Record<string, unknown> | null = null;
      let pendingRedemption: PendingBoncukRedemption | null = null;
      let pendingCatalogReward: PendingCatalogRewardRedemption | null = null;
      // Server-Authoritative Campaign Engine P8-C.2 (2026-08-25) — declared
      // at this outer scope (mirroring the three declarations above) so the
      // write-phase `reserveCampaignUsage` call below can still read it
      // after the `if (parsedPreorder)` block that resolves it has closed.
      let campaignPreCheck: CampaignDefinition | null = null;
      if (parsedPreorder) {
        const organizationId = scope.organizationId!;

        // -----------------------------------------------------------
        // Boncuk Loyalty P7-D (2026-08-24) — catalog-reward PRE-resolution.
        // Deliberately BEFORE `buildPreorderLines`, mirroring
        // `submitTakeawayOrder.ts`'s own placement exactly.
        // -----------------------------------------------------------
        let catalogRewardPreCheck: { reward: LoyaltyRewardCatalogEntry; redeemedProductId: string } | null =
          null;
        if (parsedPreorder.selectedRewardId !== null) {
          const reward = await loadLoyaltyRewardForRedemption(db, parsedPreorder.selectedRewardId, tx);
          if (!reward || reward.organizationId !== organizationId) {
            boncukError("invalid-argument", "The selected reward does not exist.", "catalogReward/reward-not-found");
          }
          if (!isRewardCurrentlyValid(reward, Timestamp.now())) {
            boncukError(
              "failed-precondition",
              "The selected reward is not currently active/valid.",
              "catalogReward/reward-not-currently-valid",
            );
          }
          if (!reward.eligibleChannels.includes("reservationPreorder")) {
            boncukError(
              "failed-precondition",
              "The selected reward is not available for the Rezervasyon Ön Sipariş channel.",
              "catalogReward/channel-not-eligible",
            );
          }
          const redeemedProductId = findFirstEligibleCartProductId(
            parsedPreorder.items,
            reward.eligibleProductIds,
          );
          if (!redeemedProductId) {
            boncukError(
              "invalid-argument",
              "None of the items in this preorder are eligible for the selected reward.",
              "catalogReward/product-not-in-cart",
            );
          }
          catalogRewardPreCheck = { reward, redeemedProductId };
        }

        // -----------------------------------------------------------
        // Server-Authoritative Campaign Engine P8-C.2 (2026-08-25) —
        // campaign PRE-check. Mirrors `submitDeliveryOrder.ts`'s own
        // placement/shape exactly, reusing the shared engine
        // (`campaignEngine.ts`/`campaignScheduling.ts`) verbatim — no
        // reservation-specific duplicate eligibility logic. Trusted server
        // state only: existence, tenant match, active/non-archived,
        // `eligibleChannels` includes `"reservationPreorder"`, and
        // currently within the campaign's own schedule (trusted server
        // time + `policy.timezone` — already resolved above by
        // `resolveActiveReservationBranch`, so unlike takeaway/delivery no
        // extra `branches/{branchId}` read is needed here). This is the
        // ONE canonical instant campaign schedule eligibility is ever
        // evaluated for a reservation preorder — never re-evaluated at
        // confirm/accept/KDS-release time (see §18/§19 of the P8-C.2 spec).
        // -----------------------------------------------------------
        if (parsedPreorder.selectedCampaignId !== null) {
          const campaignSnap = await tx.get(
            db.collection(CAMPAIGNS_COLLECTION).doc(parsedPreorder.selectedCampaignId),
          );
          const campaign = parseCampaignDefinition(campaignSnap.exists ? campaignSnap.data() : undefined);
          if (!campaign || campaign.organizationId !== organizationId) {
            boncukError("invalid-argument", "The selected campaign does not exist.", "campaign/not-found");
          }
          if (!campaign.active) {
            boncukError("failed-precondition", "The selected campaign is no longer active.", "campaign/inactive");
          }
          if (campaign.archived) {
            boncukError("failed-precondition", "The selected campaign is no longer available.", "campaign/archived");
          }
          if (!campaign.eligibleChannels.includes(RESERVATION_PREORDER_COMMERCIAL_CHANNEL)) {
            boncukError(
              "failed-precondition",
              "The selected campaign is not available for the Rezervasyon Ön Sipariş channel.",
              "campaign/channel-not-eligible",
            );
          }
          if (!isCampaignScheduleCurrentlyOpen(campaign.schedule, Timestamp.now(), policy.timezone)) {
            boncukError(
              "failed-precondition",
              "The selected campaign is not currently within its scheduled window.",
              "campaign/schedule-not-open",
            );
          }
          campaignPreCheck = campaign;
        }

        const pricingPolicy = await loadCanonicalChannelPricingPolicy(db, restaurantId, tx);
        const pass1 = await buildPreorderLines(
          tx,
          db,
          parsedPreorder.items,
          { restaurantId },
          pricingPolicy,
          catalogRewardPreCheck?.redeemedProductId ?? null,
        );
        let lines = pass1.lines;
        const rewardAppliedLineIndex = pass1.rewardAppliedLineIndex;
        let pricing = computePreorderPriceBreakdown(lines);
        preorderOrderId = derivePreorderOrderId(reservationId);

        // -----------------------------------------------------------
        // Server-Authoritative Campaign Engine P8-C.2 — discount
        // resolution + PASS 2 rebuild. `resolveCampaignDiscount`
        // (campaignPricing.ts) is the exact same pure, shared resolver
        // every other channel uses — never a reservation-specific
        // reimplementation. Minimum-basket is evaluated by that resolver
        // itself against PASS 1's own (pre-discount) line subtotals —
        // reservation preorder has no separate restaurant-operational
        // minimum-order check to preserve (unlike delivery's
        // `area.minimumOrderMinorUnits`), so PASS 1's own pricing is the
        // canonical pre-discount basket, satisfying requirement §5 as-is.
        // -----------------------------------------------------------
        let selectedBenefitType: SelectedBenefitType = "none";
        let campaignDiscountMinorUnits = 0;
        let campaignOrderSnapshot: CampaignOrderSnapshot | null = null;
        if (campaignPreCheck !== null) {
          const campaign = campaignPreCheck;
          const discountResult = resolveCampaignDiscount(campaign, pass1.campaignLines);
          if (discountResult.status === "minimum-basket-not-met") {
            boncukError(
              "failed-precondition",
              "This preorder does not meet the selected campaign's minimum basket requirement.",
              "campaign/minimum-basket-not-met",
            );
          }
          if (discountResult.status === "trigger-quantity-not-met") {
            boncukError(
              "invalid-argument",
              "This preorder does not meet the selected campaign's trigger quantity requirement.",
              "campaign/trigger-quantity-not-met",
            );
          }
          if (discountResult.status === "no-eligible-line") {
            boncukError(
              "invalid-argument",
              "None of the items in this preorder are eligible for the selected campaign.",
              "campaign/no-eligible-line",
            );
          }
          const lineDiscounts = new Map(
            discountResult.lineDiscounts.map((d) => [d.lineIndex, d.discountMinorUnits]),
          );
          const pass2 = await buildPreorderLines(
            tx,
            db,
            parsedPreorder.items,
            { restaurantId },
            pricingPolicy,
            null,
            lineDiscounts,
          );
          lines = pass2.lines;
          pricing = computePreorderPriceBreakdown(lines);
          selectedBenefitType = "campaign";
          campaignDiscountMinorUnits = discountResult.totalDiscountMinorUnits;
          campaignOrderSnapshot = {
            campaignId: campaign.campaignId,
            campaignVersion: campaign.version,
            title: campaign.title,
            campaignType: campaign.campaignType,
            appliedRule: campaign.rule,
            appliedValue: discountResult.appliedValue,
            discountMinorUnits: discountResult.totalDiscountMinorUnits,
            orderChannel: RESERVATION_PREORDER_COMMERCIAL_CHANNEL,
          };
        }

        // -----------------------------------------------------------
        // Boncuk Loyalty P6-B (2026-08-24) — redemption resolution (reads
        // only; this whole block runs strictly before this transaction's
        // first write, so every tx.get() here is safely ordered ahead of
        // every tx.set()/tx.create() below). Reuses
        // `calculateBoncukRedemption`/`resolveAccountForRedemption`
        // (loyaltyRedemption.ts) and the deterministic-ledger-id/account-
        // transaction/idempotency discipline verbatim — mirrors
        // submitDeliveryOrder.ts's own §7 block exactly, adapted only for
        // the reservation preorder's own eligible basis (no separate
        // delivery fee/tip to subtract — the whole grandTotal is the
        // basis, same simplicity as delivery). Real-phone-customer identity
        // is already unconditionally required above (submitReservation
        // never has a guest path), so no additional check is needed here.
        // `selectedBenefitType` was already declared above (Server-
        // Authoritative Campaign Engine P8-C.2's own two-pass block) —
        // reused here, never redeclared; a campaign selection guarantees
        // `requestedBoncukAmount === 0` and `catalogRewardPreCheck ===
        // null` (`enforceBenefitExclusivity`, enforced inside
        // `parsePreorderRequest`), so neither branch below ever overwrites
        // an already-`"campaign"` value.
        // -----------------------------------------------------------
        if (parsedPreorder.requestedBoncukAmount > 0) {
          const boncukEligibleOrderAmountMinorUnits = pricing.grandTotalMinorUnits;
          if (boncukEligibleOrderAmountMinorUnits < 0) {
            boncukError(
              "internal",
              "Computed a negative Boncuk-eligible order amount.",
              "boncuk/redemption-not-allowed",
            );
          }

          const accountRef = db
            .collection(LOYALTY_ACCOUNTS_COLLECTION)
            .doc(`${organizationId}_${uid}`);
          const loyaltyPolicyRef = loyaltyPolicyDocRef(db, organizationId);
          const loyaltyPolicyBootstrapDocRef = loyaltyPolicyBootstrapRef(db, organizationId);

          const accountSnap = await tx.get(accountRef);
          const loyaltyPolicySnap = await tx.get(loyaltyPolicyRef);
          const loyaltyPolicyBootstrapSnap = await tx.get(loyaltyPolicyBootstrapDocRef);

          const nowForPolicy = Timestamp.now();
          const policyResult = readLoyaltyPolicyInTransaction(
            loyaltyPolicySnap,
            loyaltyPolicyBootstrapSnap,
            organizationId,
            nowForPolicy,
          );
          if (
            policyResult.status === "corrupt-policy-state" ||
            policyResult.status === "missing-live-policy"
          ) {
            boncukError(
              "failed-precondition",
              "Loyalty economics are temporarily unavailable for this organization.",
              "boncuk/policy-unavailable",
            );
          }
          const loyaltyPolicy = policyResult.policy;

          const accountResult = resolveAccountForRedemption(accountSnap);
          if (accountResult.status === "missing-loyalty-account") {
            boncukError(
              "failed-precondition",
              "No loyalty account exists for this customer — cannot redeem Boncuk.",
              "boncuk/account-unavailable",
            );
          }
          if (accountResult.status === "inconsistent-loyalty-account-state") {
            boncukError(
              "failed-precondition",
              "This customer's loyalty account is in an inconsistent state.",
              "boncuk/account-unavailable",
            );
          }
          const account = accountResult.account;

          const calc = calculateBoncukRedemption({
            requestedBoncukAmount: parsedPreorder.requestedBoncukAmount,
            spendableBalance: account.spendableBalance,
            grandTotalMinorUnits: pricing.grandTotalMinorUnits,
            boncukEligibleOrderAmountMinorUnits,
            redemptionValueMinorUnitsPerBoncuk: loyaltyPolicy.redemptionValueMinorUnitsPerBoncuk,
            maxRedemptionBasisPoints: loyaltyPolicy.maxRedemptionBasisPoints,
          });
          if (calc.status === "exceeds-max-usable") {
            boncukError(
              "invalid-argument",
              `requestedBoncukAmount exceeds the maximum usable Boncuk for this order (max ${calc.maxUsableBoncuk}).`,
              "boncuk/exceeds-max-usable",
            );
          }

          const ledgerEntryId = deriveLoyaltyLedgerEntryId({
            organizationId,
            customerId: uid,
            entryType: "boncukRedemption",
            sourceId: preorderOrderId,
          });
          const ledgerEntryRef = db.collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(ledgerEntryId);
          const ledgerSnap = await tx.get(ledgerEntryRef);
          if (ledgerSnap.exists) {
            // Defense-in-depth only — the reservation-level dedupe check
            // above already guarantees this transaction only reaches here
            // for a genuinely new reservation/preorder, so this should
            // never happen. Fail closed rather than silently proceeding.
            boncukError(
              "failed-precondition",
              "A Boncuk redemption ledger entry already exists for this order.",
              "boncuk/redemption-not-allowed",
            );
          }

          selectedBenefitType = "boncukRedemption";
          pendingRedemption = {
            accountRef,
            account,
            boncukUsed: calc.boncukUsed,
            ledgerEntryRef,
            ledgerEntry: {
              organizationId,
              customerId: uid,
              entryType: "boncukRedemption",
              entitlementDeltaBoncuk: 0,
              spendableDeltaBoncuk: 0 - calc.boncukUsed,
              debtDeltaBoncuk: 0,
              sourceId: preorderOrderId,
              orderId: preorderOrderId,
              amountBasisMinorUnits: calc.valueMinorUnits,
              earningCarryNumeratorBefore: null,
              earningCarryDenominatorBefore: null,
              earningCarryNumeratorAfter: null,
              earningCarryDenominatorAfter: null,
              earningSpendMinorUnits: null,
              earningBoncukAmount: null,
              loyaltyPolicyVersion: loyaltyPolicy.version,
              debtBeforeBoncuk: account.boncukDebt,
              debtAfterBoncuk: account.boncukDebt,
              redemptionValueMinorUnitsPerBoncuk: loyaltyPolicy.redemptionValueMinorUnitsPerBoncuk,
              maxRedemptionBasisPoints: loyaltyPolicy.maxRedemptionBasisPoints,
              idempotencyKey: preorderOrderId,
              reversalOf: null,
              expiresAt: null,
              metadata: null,
            } as LoyaltyLedgerEntry,
            policy: loyaltyPolicy,
            policyNeedsProvisioning: policyResult.needsProvisioning,
            orderSnapshot: {
              boncukUsed: calc.boncukUsed,
              valueMinorUnits: calc.valueMinorUnits,
              remainingPayableMinorUnits: calc.remainingPayableMinorUnits,
              redemptionValueMinorUnitsPerBoncuk: loyaltyPolicy.redemptionValueMinorUnitsPerBoncuk,
              maxRedemptionBasisPoints: loyaltyPolicy.maxRedemptionBasisPoints,
              loyaltyPolicyVersion: loyaltyPolicy.version,
            },
          };
        } else if (catalogRewardPreCheck !== null) {
          // -------------------------------------------------------------
          // Boncuk Loyalty P7-D — catalog-reward FINAL resolution. Reads
          // only, still strictly before this transaction's first write.
          // Mirrors `submitTakeawayOrder.ts`'s own POST-buildLines block
          // exactly — deliberately does NOT touch `loyaltyPolicies` (a
          // reward's cost is fixed, independent of the org's cash rate).
          // -------------------------------------------------------------
          const { reward, redeemedProductId } = catalogRewardPreCheck;
          if (rewardAppliedLineIndex === null) {
            // Structurally unreachable — buildPreorderLines was given the
            // exact same redeemedProductId findFirstEligibleCartProductId
            // just found, so it always applies the free unit to a real
            // line. Defensive only.
            boncukError(
              "internal",
              "Failed to apply the catalog reward to a preorder line.",
              "catalogReward/product-not-in-cart",
            );
          }
          const rewardedLine = lines[rewardAppliedLineIndex];
          const coveredValueMinorUnits = rewardedLine.lineDiscountMinorUnits;

          const accountRef = db.collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${uid}`);
          const accountSnap = await tx.get(accountRef);
          const accountResult = resolveAccountForRedemption(accountSnap);
          if (accountResult.status === "missing-loyalty-account") {
            boncukError(
              "failed-precondition",
              "No loyalty account exists for this customer — cannot redeem a catalog reward.",
              "catalogReward/account-unavailable",
            );
          }
          if (accountResult.status === "inconsistent-loyalty-account-state") {
            boncukError(
              "failed-precondition",
              "This customer's loyalty account is in an inconsistent state.",
              "catalogReward/account-unavailable",
            );
          }
          const account = accountResult.account;

          const resolution = resolveCatalogRewardRedemption({
            reward,
            now: new Date(),
            organizationId,
            orderChannel: "reservationPreorder",
            requestedProductId: redeemedProductId,
            spendableBalance: account.spendableBalance,
          });
          if (resolution.status === "insufficient-balance") {
            boncukError(
              "failed-precondition",
              `Insufficient Boncuk balance for this reward (requires ${resolution.requiredBoncuk}, has ${resolution.availableBoncuk}).`,
              "catalogReward/insufficient-balance",
            );
          }
          if (resolution.status !== "ok") {
            boncukError(
              "failed-precondition",
              "The selected reward can no longer be redeemed.",
              "catalogReward/reward-not-currently-valid",
            );
          }
          const { snapshot } = resolution;

          const ledgerEntryId = deriveLoyaltyLedgerEntryId({
            organizationId,
            customerId: uid,
            entryType: "catalogRedemption",
            sourceId: preorderOrderId,
          });
          const ledgerEntryRef = db.collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(ledgerEntryId);
          const ledgerSnap = await tx.get(ledgerEntryRef);
          if (ledgerSnap.exists) {
            boncukError(
              "failed-precondition",
              "A catalog reward redemption ledger entry already exists for this order.",
              "catalogReward/reward-not-currently-valid",
            );
          }

          selectedBenefitType = "catalogReward";
          pendingCatalogReward = {
            accountRef,
            account,
            boncukCost: snapshot.boncukCost,
            ledgerEntryRef,
            ledgerEntry: {
              organizationId,
              customerId: uid,
              entryType: "catalogRedemption",
              entitlementDeltaBoncuk: 0,
              spendableDeltaBoncuk: 0 - snapshot.boncukCost,
              debtDeltaBoncuk: 0,
              sourceId: preorderOrderId,
              orderId: preorderOrderId,
              amountBasisMinorUnits: coveredValueMinorUnits,
              earningCarryNumeratorBefore: null,
              earningCarryDenominatorBefore: null,
              earningCarryNumeratorAfter: null,
              earningCarryDenominatorAfter: null,
              earningSpendMinorUnits: null,
              earningBoncukAmount: null,
              loyaltyPolicyVersion: null,
              debtBeforeBoncuk: account.boncukDebt,
              debtAfterBoncuk: account.boncukDebt,
              redemptionValueMinorUnitsPerBoncuk: null,
              maxRedemptionBasisPoints: null,
              idempotencyKey: preorderOrderId,
              reversalOf: null,
              expiresAt: null,
              metadata: { entryType: "catalogRedemption", rewardId: snapshot.rewardId },
            } as LoyaltyLedgerEntry,
            orderSnapshot: {
              rewardId: snapshot.rewardId,
              rewardVersion: snapshot.rewardVersion,
              title: snapshot.title,
              boncukCost: snapshot.boncukCost,
              redeemedProductId: snapshot.redeemedProductId,
              redeemedQuantity: 1,
              coveredValueMinorUnits,
              rewardCatalogVersionId: loyaltyRewardCatalogVersionDocId(
                snapshot.rewardId,
                snapshot.rewardVersion,
              ),
              orderChannel: "reservationPreorder",
            },
          };
        }

        preorderOrderDocument = buildPreorderOrderDocument({
          organizationId,
          orderId: preorderOrderId,
          restaurantId,
          branchId,
          customerId: uid,
          reservationContextId: reservationId,
          lines,
          pricing,
          now,
          selectedBenefitType,
          boncukRedemption: pendingRedemption ? pendingRedemption.orderSnapshot : null,
          catalogReward: pendingCatalogReward ? pendingCatalogReward.orderSnapshot : null,
          campaign: campaignOrderSnapshot,
          discountMinorUnits: campaignDiscountMinorUnits,
        });
      }

      // ---------------------------------------------------------------
      // Write phase begins here — every tx.get() this transaction will
      // ever perform (scope/policy/area, catalog, and — when a Boncuk
      // redemption was requested — loyaltyAccounts/loyaltyPolicies/ledger)
      // has already happened above.
      // ---------------------------------------------------------------
      // Server-Authoritative Campaign Engine P8-C.2 (2026-08-25) — usage
      // reservation is the FIRST write-phase statement, mirroring
      // `submitDeliveryOrder.ts`'s own placement exactly.
      // `reserveCampaignUsage` (the shared `campaignUsage.ts` primitive,
      // reused verbatim) performs its OWN internal reads (counter/
      // reservation existence) THEN writes atomically — calling it here
      // guarantees ALL of its reads happen before ANY write in this ENTIRE
      // transaction, satisfying "no reads after writes" without a manual
      // read/write split. `customerId` is always the real, authenticated
      // `uid` — submitReservation has no guest/anonymous path at all (a
      // real, phone-verified customer is required unconditionally above),
      // so there is no "campaign-on-guest" case to separately reject here.
      if (campaignPreCheck !== null) {
        const reserveResult = await reserveCampaignUsage(db, tx, {
          organizationId: scope.organizationId!,
          campaignId: campaignPreCheck.campaignId,
          customerId: uid,
          orderId: preorderOrderId!,
          usageLimit: campaignPreCheck.usageLimit,
          perCustomerUsageLimit: campaignPreCheck.perCustomerUsageLimit,
        });
        if (reserveResult.status === "global-limit-reached") {
          boncukError(
            "failed-precondition",
            "The selected campaign has reached its usage limit.",
            "campaign/usage-limit-reached",
          );
        }
        if (reserveResult.status === "customer-limit-reached") {
          boncukError(
            "failed-precondition",
            "You have already reached your usage limit for the selected campaign.",
            "campaign/customer-usage-limit-reached",
          );
        }
        if (reserveResult.status === "already-reserved") {
          boncukError(
            "failed-precondition",
            "This campaign usage was already reserved for this order.",
            "campaign/reservation-conflict",
          );
        }
      }

      if (pendingRedemption) {
        if (pendingRedemption.policyNeedsProvisioning) {
          writeDefaultLoyaltyPolicyInTransaction(tx, db, pendingRedemption.policy);
        }
        tx.set(pendingRedemption.accountRef, {
          ...pendingRedemption.account,
          spendableBalance: pendingRedemption.account.spendableBalance - pendingRedemption.boncukUsed,
          lifetimeRedeemed: pendingRedemption.account.lifetimeRedeemed + pendingRedemption.boncukUsed,
          revision: pendingRedemption.account.revision + 1,
          updatedAt: Timestamp.fromDate(now),
        });
        tx.create(pendingRedemption.ledgerEntryRef, {
          ...pendingRedemption.ledgerEntry,
          createdAt: Timestamp.fromDate(now),
        });
      }

      if (pendingCatalogReward) {
        tx.set(pendingCatalogReward.accountRef, {
          ...pendingCatalogReward.account,
          spendableBalance:
            pendingCatalogReward.account.spendableBalance - pendingCatalogReward.boncukCost,
          lifetimeRedeemed:
            pendingCatalogReward.account.lifetimeRedeemed + pendingCatalogReward.boncukCost,
          revision: pendingCatalogReward.account.revision + 1,
          updatedAt: Timestamp.fromDate(now),
        });
        tx.create(pendingCatalogReward.ledgerEntryRef, {
          ...pendingCatalogReward.ledgerEntry,
          createdAt: Timestamp.fromDate(now),
        });
      }

      let holdId: string | null = null;
      if (capacity.available) {
        const holdRef = db.collection("reservationHolds").doc();
        holdId = holdRef.id;
        tx.set(holdRef, {
          reservationId,
          organizationId: scope.organizationId,
          branchId,
          areaId,
          bucketIds: capacity.buckets.map((b: ReservationSlotBucket) => b.id),
          partySize,
          purpose: "initialRequest",
          status: "active",
          expiresAt: responseDeadlineAt,
          createdAt: now,
        });
        for (const bucket of capacity.buckets) {
          const bucketRef = db.collection("reservationSlotOccupancy").doc(bucket.id);
          tx.set(
            bucketRef,
            {
              branchId,
              areaId,
              slotStart: bucket.slotStart,
              capacity: area.capacity,
              confirmedPartySize: FieldValue.increment(0),
              heldPartySize: FieldValue.increment(partySize),
            },
            { merge: true },
          );
        }
      }

      const requestedAvailabilityAtSubmission = capacity.available ? "available" : "unavailable";

      if (preorderOrderDocument && preorderOrderId) {
        tx.set(resolvePreorderOrderRef(db, reservationId), preorderOrderDocument);
      }

      tx.set(reservationRef, {
        organizationId: scope.organizationId,
        restaurantId,
        branchId,
        areaId,
        customerId: uid,
        contactFirstName,
        contactLastName,
        contactPhone,
        partySize,
        requestedTime,
        requestedAreaId: areaId,
        requestedAvailabilityAtSubmission,
        status: "pendingRestaurantApproval",
        activeHoldId: holdId,
        responseDeadlineAt,
        submissionFingerprint: fingerprint,
        // Faz R.1D.1 D3 — nullable, immutable once set: the deterministic
        // link to this reservation's optional preorder Order, resolved by
        // every confirm/reject/sweep path — never a client-supplied order
        // id anywhere in that resolution.
        preorderOrderId,
        createdAt: now,
        updatedAt: now,
      });

      return {
        reservationId,
        status: "pendingRestaurantApproval",
        requestedAvailabilityAtSubmission,
        responseDeadlineAt: responseDeadlineAt.toISOString(),
        preorderOrderId,
        duplicate: false,
      };
    });
  },
);
