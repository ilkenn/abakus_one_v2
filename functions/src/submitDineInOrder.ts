import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Firestore, Timestamp } from "firebase-admin/firestore";
import {
  loadCanonicalChannelPricingPolicy,
} from "./takeawayCatalog";
import {
  computeOrderPriceBreakdown,
  type ComputedOrderLine,
} from "./takeawayPricing";
import {
  parseItems,
  buildProductLine,
  buildBowlLine,
  findFirstEligibleCartProductId,
  sha256Hex,
  computeRequestFingerprint,
  type RawItem,
  type CatalogRewardOrderSnapshot,
} from "./submitTakeawayOrder";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { ORDER_PRICING_AUTHORITY_SERVER_V1 } from "./orderPricingAuthority";
import {
  LOYALTY_ACCOUNTS_COLLECTION,
  LOYALTY_LEDGER_ENTRIES_COLLECTION,
  deriveLoyaltyLedgerEntryId,
  type LoyaltyLedgerEntry,
} from "./loyaltyLedger";
import { resolveAccountForRedemption } from "./loyaltyRedemption";
import type { LoyaltyAccountData } from "./getCustomerLoyaltySnapshot";
import {
  boncukError,
  sanitizeSelectedRewardId,
  type SelectedBenefitType,
} from "./boncukRedemptionErrors";
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
import { isTableGuestSessionActive } from "./tableGuestSessionConfig";

/**
 * `submitDineInOrder` — Boncuk Loyalty Program P7-D.1 (2026-08-24).
 *
 * The first server-authoritative order-creation pipeline for the dine-in
 * table-QR channel — previously a direct client-side Firestore write with
 * no transaction, no server pricing, and no Loyalty integration at all
 * (see `docs/business_rules.md` BR-LOYALTY-029's own audit finding, the
 * direct precursor to this file). Mirrors `submitTakeawayOrder.ts`'s
 * `submitGuestOrder` session-scoped shape closely, but — unlike takeaway,
 * where guest and authenticated customer are two structurally SEPARATE
 * request shapes/dispatch paths — dine-in always goes through the SAME
 * `tableGuestSessions` record for both identity types (an anonymous guest
 * and a phone-verified customer scanning the same table's QR both open the
 * identical kind of session; only the caller's own Firebase Auth
 * `sign_in_provider` differs). Identity is therefore classified INSIDE
 * this one transaction, never by dispatching to two different functions.
 *
 * **The client sends only intent — `tableSessionId`, cart items, and an
 * optional benefit selection.** `organizationId`/`restaurantId`/`branchId`/
 * `tableId`/`reservationContextId` are all derived from the trusted,
 * server-written `tableGuestSessions/{tableSessionId}` document inside the
 * transaction — never from client-supplied scope fields (there are none in
 * the accepted request shape). `customerId` vs `guestAuthUid` is decided
 * from the caller's own verified Firebase Auth token, never a client claim.
 *
 * **Dine-in cash Boncuk redemption is deliberately NOT wired here.**
 * `docs/business_rules.md` BR-LOYALTY-019 explicitly excludes
 * `dineInQr`/POS/staff-created orders from cash Boncuk redemption — that
 * exclusion predates this pipeline and was never an approved product rule
 * this callable is authorized to silently switch on just because the
 * underlying technical blocker (no server pricing) is now resolved. A
 * `requestedBoncukAmount > 0` is therefore always rejected, fail-closed,
 * for both identity types — catalog-reward redemption (a SEPARATE,
 * already-approved-for-extension mechanism per BR-LOYALTY-029) is the only
 * Loyalty benefit this callable supports, and only for a real, phone-
 * verified customer.
 */

const DINE_IN_COMMERCIAL_CHANNEL: CanonicalCommercialChannel = "dineIn";
const MAX_ITEMS_PER_ORDER = 50;
const MAX_NOTE_LENGTH = 500;
const MAX_SUBMISSION_KEY_LENGTH = 200;

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

function sanitizeSubmissionKey(raw: unknown): string {
  if (typeof raw !== "string" || raw.length === 0) invalid("submissionKey is required.");
  if (raw.length > MAX_SUBMISSION_KEY_LENGTH) invalid("submissionKey is too long.");
  return raw;
}

function sanitizeTableSessionId(raw: unknown): string {
  if (typeof raw !== "string" || raw.length === 0) invalid("tableSessionId is required.");
  return raw;
}

function sanitizeCustomerNote(raw: unknown): string {
  if (raw === undefined || raw === null) return "";
  if (typeof raw !== "string") invalid("customerNote must be a string.");
  const trimmed = raw.trim();
  if (trimmed.length > MAX_NOTE_LENGTH) invalid("customerNote is too long.");
  return trimmed;
}

/** Mirrors `sanitizeRequestedBoncukAmount` shape-only validation — the semantic "always rejected on this channel" decision happens later, once, in one place. */
function sanitizeRequestedBoncukAmountShapeOnly(raw: unknown): number {
  if (raw === undefined || raw === null) return 0;
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw < 0) {
    invalid("requestedBoncukAmount must be a non-negative integer.");
  }
  return raw as number;
}

function deriveDineInOrderId(uid: string, submissionKey: string): string {
  return `dineIn-${sha256Hex(`${uid}|${submissionKey}`)}`;
}

function deriveOrderNumber(orderId: string): string {
  return `DI-${orderId.slice(orderId.length - 8).toUpperCase()}`;
}

interface PendingCatalogRewardRedemption {
  accountRef: FirebaseFirestore.DocumentReference;
  account: LoyaltyAccountData;
  boncukCost: number;
  ledgerEntryRef: FirebaseFirestore.DocumentReference;
  ledgerEntry: LoyaltyLedgerEntry;
  orderSnapshot: CatalogRewardOrderSnapshot;
}

async function buildLines(
  db: Firestore,
  rawItems: RawItem[],
  scope: { restaurantId: string },
  policy: import("./takeawayCatalog").CanonicalChannelPricingPolicy,
  rewardedProductId: string | null,
): Promise<{
  lines: ComputedOrderLine[];
  normalizedItems: unknown[];
  rewardAppliedLineIndex: number | null;
}> {
  const lines: ComputedOrderLine[] = [];
  const normalizedItems: unknown[] = [];
  let rewardAppliedLineIndex: number | null = null;
  for (const item of rawItems) {
    if (item.kind === "product") {
      const isRewardedLine =
        rewardAppliedLineIndex === null &&
        rewardedProductId !== null &&
        item.productId === rewardedProductId;
      const line = await buildProductLine(
        db,
        item,
        scope,
        DINE_IN_COMMERCIAL_CHANNEL,
        policy,
        undefined,
        isRewardedLine ? 1 : 0,
      );
      if (isRewardedLine) rewardAppliedLineIndex = lines.length;
      lines.push(line);
      normalizedItems.push({
        kind: "product",
        productId: item.productId,
        quantity: item.quantity,
        selectedModifiers: item.selectedModifiers ?? [],
        note: item.note ?? "",
      });
    } else {
      const line = await buildBowlLine(db, item, scope, DINE_IN_COMMERCIAL_CHANNEL, policy);
      lines.push(line);
      normalizedItems.push({
        kind: "bowl",
        quantity: item.quantity,
        ingredientIds: item.ingredientIds,
        note: item.note ?? "",
      });
    }
  }
  return { lines, normalizedItems, rewardAppliedLineIndex };
}

function buildDineInOrderDocument(params: {
  organizationId: string;
  orderId: string;
  orderNumber: string;
  branchId: string;
  restaurantId: string;
  customerId: string | null;
  guestAuthUid: string;
  tableId: string;
  tableSessionId: string;
  reservationContextId: string | null;
  customerNote: string;
  lines: ComputedOrderLine[];
  pricing: import("./takeawayPricing").ComputedPriceBreakdown;
  now: Date;
  fingerprint: string;
  selectedBenefitType: SelectedBenefitType;
  catalogReward: CatalogRewardOrderSnapshot | null;
}) {
  const currencyCode = "TRY";
  const moneyField = (minorUnits: number) => ({ minorUnits, currencyCode });

  return {
    organizationId: params.organizationId,
    orderId: params.orderId,
    orderNumber: params.orderNumber,
    status: "pendingConfirmation",
    channel: "dineInQr",
    pricingAuthority: ORDER_PRICING_AUTHORITY_SERVER_V1,
    branchId: params.branchId,
    restaurantId: params.restaurantId,
    customerId: params.customerId,
    tableId: params.tableId,
    tableSessionId: params.tableSessionId,
    guestSessionId: null,
    guestAuthUid: params.guestAuthUid,
    reservationContextId: params.reservationContextId,
    takeawayEntrySessionId: null,
    pickupMode: null,
    pickupTime: null,
    pickupTimeTimestamp: null,
    contactFirstName: null,
    contactLastName: null,
    contactPhone: null,
    courierVisibility: "hidden",
    lines: params.lines.map((line) => ({
      productId: line.productId,
      productName: line.productName,
      modifiers: line.modifiers.map((m) => ({
        groupId: m.groupId,
        groupName: m.groupName,
        optionId: m.optionId,
        optionName: m.optionName,
        unitExtraPrice: moneyField(m.unitExtraPriceMinorUnits),
        quantity: m.quantity,
      })),
      quantity: line.quantity,
      unitPrice: moneyField(line.unitPriceMinorUnits),
      lineDiscount: moneyField(line.lineDiscountMinorUnits),
      taxRateBasisPoints: line.taxBasisPoints,
      kitchenNote: line.kitchenNote,
      customerNote: line.customerNote,
    })),
    pricing: {
      grossSubtotal: moneyField(params.pricing.grossSubtotalMinorUnits),
      discount: moneyField(0),
      taxableBase: moneyField(params.pricing.taxableBaseMinorUnits),
      vatAmount: moneyField(params.pricing.vatAmountMinorUnits),
      serviceFee: moneyField(0),
      deliveryFee: moneyField(0),
      packagingFee: moneyField(0),
      tip: moneyField(0),
      grandTotal: moneyField(params.pricing.grandTotalMinorUnits),
    },
    selectedBenefitType: params.selectedBenefitType,
    boncukRedemption: null,
    catalogReward: params.catalogReward,
    statusHistory: [
      {
        id: `${params.orderId}-transition-1`,
        type: "statusChange",
        description: "Status changed from created to pendingConfirmation",
        actor: "customer",
        timestamp: params.now.toISOString(),
        previousValue: "created",
        newValue: "pendingConfirmation",
      },
    ],
    version: 1,
    timestamps: {
      created: params.now.toISOString(),
      confirmed: null,
      preparing: null,
      ready: null,
      served: null,
      completed: null,
      cancelled: null,
    },
    customerNote: params.customerNote,
    kitchenNote: "",
    takeawaySubmissionFingerprint: params.fingerprint,
  };
}

export const submitDineInOrder = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const uid = request.auth.uid;
    const isRealCustomer = request.auth.token?.firebase?.sign_in_provider === "phone";

    const data = (request.data ?? {}) as Record<string, unknown>;
    const submissionKey = sanitizeSubmissionKey(data.submissionKey);
    const tableSessionId = sanitizeTableSessionId(data.tableSessionId);
    const rawItems = parseItems(data.items);
    if (rawItems.length > MAX_ITEMS_PER_ORDER) invalid("too many items in one order.");
    const customerNote = sanitizeCustomerNote(data.customerNote);
    const requestedBoncukAmount = sanitizeRequestedBoncukAmountShapeOnly(data.requestedBoncukAmount);
    const selectedRewardId = sanitizeSelectedRewardId(data.selectedRewardId);

    // Locked rule (BR-LOYALTY-019, unchanged by this phase) — dine-in cash
    // Boncuk redemption was never an approved product rule; this pipeline
    // resolves the TECHNICAL blocker that rule cited, it does not silently
    // reverse the product decision itself. Rejected fail-closed, before the
    // transaction even opens, for both identity types.
    if (requestedBoncukAmount > 0) {
      boncukError(
        "failed-precondition",
        "Boncuk cash redemption is not available for dine-in orders.",
        "boncuk/redemption-not-allowed",
      );
    }
    // Same static stacking guard every other channel applies — kept even
    // though the boncuk branch above already always rejects on its own,
    // so a request sending BOTH gets the more specific stacking reason.
    if (requestedBoncukAmount > 0 && selectedRewardId !== null) {
      boncukError(
        "invalid-argument",
        "requestedBoncukAmount and selectedRewardId cannot both be set — exactly one benefit per order.",
        "catalogReward/benefit-stacking-not-allowed",
      );
    }
    // Anonymous table guests can never redeem a catalog reward — rejected
    // fail-closed BEFORE the transaction opens, so no Loyalty account read
    // of any kind ever happens for a guest request.
    if (selectedRewardId !== null && !isRealCustomer) {
      throw new HttpsError(
        "permission-denied",
        "Catalog reward redemption requires a real, phone-verified customer identity.",
        { reason: "catalogReward/reward-not-currently-valid" },
      );
    }

    const db = getFirestore();
    const orderId = deriveDineInOrderId(uid, submissionKey);
    const orderNumber = deriveOrderNumber(orderId);

    return db.runTransaction(async (tx) => {
      // ---------------------------------------------------------------
      // Read phase — table guest session, its linked reservation (if any),
      // the catalog reward (if any), then cart-dependent pricing/dedupe
      // reads. Every tx.get() in this function happens before its first
      // write, per Firestore's own transaction discipline.
      // ---------------------------------------------------------------
      const sessionRef = db.collection("tableGuestSessions").doc(tableSessionId);
      const sessionDoc = await tx.get(sessionRef);
      if (!sessionDoc.exists) {
        throw new HttpsError("not-found", "Table guest session not found.");
      }
      const session = sessionDoc.data()!;
      if (session.guestAuthUid !== uid) {
        throw new HttpsError("failed-precondition", "This table session does not belong to the caller.");
      }
      if (
        !isTableGuestSessionActive({
          status: String(session.status),
          expiresAt: session.expiresAt,
        })
      ) {
        throw new HttpsError("failed-precondition", "This table session is not active.");
      }

      const organizationId = String(session.organizationId);
      const restaurantId = String(session.restaurantId);
      const branchId = String(session.branchId);
      const tableId = String(session.tableId);
      const reservationContextId: string | null = session.reservationContextId ?? null;

      // Mirrors `firestore.rules`' own `reservationContextIsOrderable` —
      // reimplemented server-side since the direct-client-create rule
      // branches that used to enforce this are removed by this same phase.
      if (reservationContextId !== null) {
        const reservationRef = db.collection("reservations").doc(reservationContextId);
        const reservationDoc = await tx.get(reservationRef);
        if (!reservationDoc.exists || reservationDoc.data()!.status !== "confirmed") {
          throw new HttpsError(
            "failed-precondition",
            "This table's linked reservation is no longer orderable.",
          );
        }
      }

      const customerId = isRealCustomer ? uid : null;

      // -------------------------------------------------------------
      // Catalog-reward PRE-resolution (real customer only — the guest
      // rejection above already guarantees selectedRewardId is null for
      // any anonymous caller reaching this point). Mirrors
      // `submitTakeawayOrder.ts`'s own PRE-block exactly.
      // -------------------------------------------------------------
      let catalogRewardPreCheck: { reward: LoyaltyRewardCatalogEntry; redeemedProductId: string } | null =
        null;
      if (selectedRewardId !== null) {
        const reward = await loadLoyaltyRewardForRedemption(db, selectedRewardId, tx);
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
        if (!reward.eligibleChannels.includes(DINE_IN_COMMERCIAL_CHANNEL)) {
          boncukError(
            "failed-precondition",
            "The selected reward is not available for dine-in (Masa) orders.",
            "catalogReward/channel-not-eligible",
          );
        }
        const redeemedProductId = findFirstEligibleCartProductId(rawItems, reward.eligibleProductIds);
        if (!redeemedProductId) {
          boncukError(
            "invalid-argument",
            "None of the items in this order are eligible for the selected reward.",
            "catalogReward/product-not-in-cart",
          );
        }
        catalogRewardPreCheck = { reward, redeemedProductId };
      }

      const pricingPolicy = await loadCanonicalChannelPricingPolicy(db, restaurantId);
      const { lines, normalizedItems, rewardAppliedLineIndex } = await buildLines(
        db,
        rawItems,
        { restaurantId },
        pricingPolicy,
        catalogRewardPreCheck?.redeemedProductId ?? null,
      );
      const pricing = computeOrderPriceBreakdown(lines);

      const normalizedForFingerprint = {
        tableSessionId,
        items: normalizedItems,
        customerNote,
        selectedRewardId,
      };
      const fingerprint = computeRequestFingerprint(normalizedForFingerprint);

      const orderRef = db.collection("orders").doc(orderId);
      const existing = await tx.get(orderRef);
      if (existing.exists) {
        const existingData = existing.data()!;
        if (existingData.takeawaySubmissionFingerprint !== fingerprint) {
          throw new HttpsError(
            "failed-precondition",
            "submissionKey was already used with a different order payload.",
          );
        }
        return { orderId, orderNumber: existingData.orderNumber, duplicate: true };
      }

      let selectedBenefitType: SelectedBenefitType = "none";
      let pendingCatalogReward: PendingCatalogRewardRedemption | null = null;

      if (catalogRewardPreCheck !== null) {
        const { reward, redeemedProductId } = catalogRewardPreCheck;
        if (rewardAppliedLineIndex === null) {
          // Structurally unreachable — buildLines was given the exact same
          // redeemedProductId findFirstEligibleCartProductId just found.
          boncukError(
            "internal",
            "Failed to apply the catalog reward to a cart line.",
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
          orderChannel: DINE_IN_COMMERCIAL_CHANNEL,
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
          sourceId: orderId,
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
            sourceId: orderId,
            orderId,
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
            idempotencyKey: orderId,
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
            orderChannel: DINE_IN_COMMERCIAL_CHANNEL,
          },
        };
      }

      // ---------------------------------------------------------------
      // Write phase — every tx.get() this transaction will ever perform
      // has already happened above.
      // ---------------------------------------------------------------
      const now = new Date();

      if (pendingCatalogReward) {
        tx.set(pendingCatalogReward.accountRef, {
          ...pendingCatalogReward.account,
          spendableBalance: pendingCatalogReward.account.spendableBalance - pendingCatalogReward.boncukCost,
          lifetimeRedeemed: pendingCatalogReward.account.lifetimeRedeemed + pendingCatalogReward.boncukCost,
          revision: pendingCatalogReward.account.revision + 1,
          updatedAt: Timestamp.fromDate(now),
        });
        tx.create(pendingCatalogReward.ledgerEntryRef, {
          ...pendingCatalogReward.ledgerEntry,
          createdAt: Timestamp.fromDate(now),
        });
      }

      tx.set(
        orderRef,
        buildDineInOrderDocument({
          organizationId,
          orderId,
          orderNumber,
          branchId,
          restaurantId,
          customerId,
          guestAuthUid: uid,
          tableId,
          tableSessionId,
          reservationContextId,
          customerNote,
          lines,
          pricing,
          now,
          fingerprint,
          selectedBenefitType,
          catalogReward: pendingCatalogReward ? pendingCatalogReward.orderSnapshot : null,
        }),
      );

      return { orderId, orderNumber, duplicate: false };
    });
  },
);
