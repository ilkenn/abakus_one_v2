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
  sanitizeSelectedCampaignId,
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
import { enforceBenefitExclusivity } from "./benefitExclusivity";
import {
  CAMPAIGNS_COLLECTION,
  parseCampaignDefinition,
  type CampaignDefinition,
  type CampaignOrderSnapshot,
} from "./campaignEngine";
import { isCampaignScheduleCurrentlyOpen, DEFAULT_ORGANIZATION_TIMEZONE } from "./campaignScheduling";
import { resolveCampaignDiscount, type CampaignPriceableLine } from "./campaignPricing";
import { reserveCampaignUsage } from "./campaignUsage";

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

/**
 * Server-Authoritative Campaign Engine P8-C.3 (2026-08-25) —
 * `campaignLineDiscounts` (line index -> resolved minor-unit discount) is
 * threaded through to each line's own `buildProductLine`/`buildBowlLine`
 * call (both already accept a trailing `campaignDiscountMinorUnits`
 * parameter, added in P8-C and reused verbatim by every channel since —
 * zero changes needed to either function for dine-in), and every built
 * line's real, channel-priced info is ALSO captured into `campaignLines`
 * (`campaignPricing.ts`'s own input shape), piggybacking on data already
 * fetched for the line — no extra Firestore reads. Mirrors
 * `submitTakeawayOrder.ts`'s own `buildLines`/`submitDeliveryOrder.ts`'s own
 * `buildDeliveryLines` two-pass pattern exactly (the shared campaign engine
 * reused verbatim, never re-implemented for this channel).
 * `campaignLineDiscounts: null` (the default) means "no campaign discount
 * to apply this call," so every pre-P8-C.3 caller behaves identically to
 * before.
 */
async function buildLines(
  db: Firestore,
  rawItems: RawItem[],
  scope: { restaurantId: string },
  policy: import("./takeawayCatalog").CanonicalChannelPricingPolicy,
  rewardedProductId: string | null,
  campaignLineDiscounts: Map<number, number> | null = null,
): Promise<{
  lines: ComputedOrderLine[];
  normalizedItems: unknown[];
  rewardAppliedLineIndex: number | null;
  campaignLines: CampaignPriceableLine[];
}> {
  const lines: ComputedOrderLine[] = [];
  const normalizedItems: unknown[] = [];
  const campaignLines: CampaignPriceableLine[] = [];
  let rewardAppliedLineIndex: number | null = null;
  for (const item of rawItems) {
    const lineIndex = lines.length;
    const campaignDiscountForLine = campaignLineDiscounts?.get(lineIndex) ?? 0;
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
        campaignDiscountForLine,
      );
      if (isRewardedLine) rewardAppliedLineIndex = lineIndex;
      lines.push(line);
      normalizedItems.push({
        kind: "product",
        productId: item.productId,
        quantity: item.quantity,
        selectedModifiers: item.selectedModifiers ?? [],
        note: item.note ?? "",
      });
      campaignLines.push({
        lineIndex,
        productId: line.productId,
        categoryId: line.categoryId,
        quantity: line.quantity,
        unitBaseMinorUnits: line.unitPriceMinorUnits + line.modifierTotalMinorUnits,
      });
    } else {
      const line = await buildBowlLine(
        db,
        item,
        scope,
        DINE_IN_COMMERCIAL_CHANNEL,
        policy,
        undefined,
        0,
        campaignDiscountForLine,
      );
      lines.push(line);
      normalizedItems.push({
        kind: "bowl",
        quantity: item.quantity,
        ingredientIds: item.ingredientIds,
        note: item.note ?? "",
      });
      // A Bowl Builder line has no real canonical product/category id —
      // structurally ineligible for any product/category-scoped campaign,
      // never a fake id standing in for one.
      campaignLines.push({
        lineIndex,
        productId: null,
        categoryId: null,
        quantity: line.quantity,
        unitBaseMinorUnits: line.unitPriceMinorUnits + line.modifierTotalMinorUnits,
      });
    }
  }
  return { lines, normalizedItems, rewardAppliedLineIndex, campaignLines };
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
  /**
   * Server-Authoritative Campaign Engine P8-C.3 (2026-08-25) — the
   * immutable per-order campaign snapshot when `selectedBenefitType ===
   * "campaign"`; `null` otherwise, including every pre-P8-C.3 order. Never
   * re-read from the live `campaigns` document by any future consumer —
   * mirrors `submitDeliveryOrder.ts`'s own `buildDeliveryOrderDocument`
   * extension exactly.
   */
  campaign: CampaignOrderSnapshot | null;
  /**
   * The EXACT total campaign discount already baked into `pricing`'s own
   * `grandTotal`/line `lineDiscount`s above — `0` for every order without a
   * campaign (preserves the pre-P8-C.3 hardcoded-zero behavior).
   */
  discountMinorUnits: number;
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
      discount: moneyField(params.discountMinorUnits),
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
    // Server-Authoritative Campaign Engine P8-C.3 (2026-08-25) — same
    // discipline: `pricing` above already reflects the campaign discount
    // baked in; `campaign` is the read-only immutable audit snapshot.
    campaign: params.campaign,
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
    // Server-Authoritative Campaign Engine P8-C.3 (2026-08-25) — the ONLY
    // campaign-related value this callable ever accepts; the server
    // resolves and re-validates everything else itself.
    const selectedCampaignId = sanitizeSelectedCampaignId(data.selectedCampaignId);

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
    // Server-Authoritative Campaign Engine P8-C.3 — the shared, three-way
    // "at most one benefit per order" check (`benefitExclusivity.ts`, P8-B),
    // replacing this file's own previous hand-rolled two-way
    // (`requestedBoncukAmount`/`selectedRewardId`) stacking check — the same
    // upgrade P8-C/P8-C.1/P8-C.2 already made on takeaway/delivery/
    // reservation preorder. The `requestedBoncukAmount > 0` branch above
    // already unconditionally rejects on its own for dine-in, so this can
    // only ever additionally catch `selectedRewardId !== null &&
    // selectedCampaignId !== null` here — but reuses the ONE shared check
    // rather than a dine-in-specific duplicate.
    enforceBenefitExclusivity({ requestedBoncukAmount, selectedRewardId, selectedCampaignId });
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
    // Server-Authoritative Campaign Engine P8-C.3 (2026-08-25) — LOCKED
    // Abaküs One policy: anonymous/table-QR guests cannot use Campaigns,
    // mirroring the identical, already-shipped guest exclusion above for
    // catalog-reward redemption (and the existing dine-in-wide cash-Boncuk
    // exclusion) exactly — never a new/parallel guest policy. Rejected
    // fail-closed BEFORE the transaction opens, so no campaign document is
    // ever read for a guest request. See `docs/business_rules.md`
    // BR-LOYALTY-019/BR-PROMO-008 for the locked rule.
    if (selectedCampaignId !== null && !isRealCustomer) {
      throw new HttpsError(
        "permission-denied",
        "Campaign redemption requires a real, phone-verified customer identity.",
        { reason: "campaign/requires-customer-identity" },
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

      // -------------------------------------------------------------
      // Server-Authoritative Campaign Engine P8-C.3 (2026-08-25) — campaign
      // PRE-resolution (existence/tenant/active/archived/channel/schedule).
      // Real customer only — the guest rejection above already guarantees
      // `selectedCampaignId` is null for any anonymous caller reaching this
      // point. Deliberately BEFORE `buildLines`: these checks need no
      // pricing at all. Minimum-basket/targeting/rule-satisfaction checks DO
      // need priced lines — resolved just below, after `buildLines`'s first
      // pass. Mutually exclusive with catalogReward (enforced pre-
      // transaction by `enforceBenefitExclusivity`), so at most one of
      // `catalogRewardPreCheck`/`campaignPreCheck` is ever non-null. Mirrors
      // `submitTakeawayOrder.ts`'s own placement/shape exactly, reusing the
      // shared engine verbatim — no dine-in-specific duplicate eligibility
      // logic.
      // -------------------------------------------------------------
      let campaignPreCheck: CampaignDefinition | null = null;
      if (selectedCampaignId !== null) {
        const campaignSnap = await tx.get(db.collection(CAMPAIGNS_COLLECTION).doc(selectedCampaignId));
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
        if (!campaign.eligibleChannels.includes(DINE_IN_COMMERCIAL_CHANNEL)) {
          boncukError(
            "failed-precondition",
            "The selected campaign is not available for dine-in (Masa) orders.",
            "campaign/channel-not-eligible",
          );
        }

        // Trusted branch timezone — never the client's clock, never a
        // hardcoded default when the branch has its own real value. Mirrors
        // `submitTakeawayOrder.ts`'s own branch-timezone lookup exactly —
        // dine-in has no already-loaded policy/timezone value to reuse the
        // way reservation preorder does, so this is one extra read, exactly
        // like takeaway/delivery each also needed.
        const branchSnap = await tx.get(db.collection("branches").doc(branchId));
        const branchTimeZone =
          branchSnap.exists && typeof branchSnap.data()!.timezone === "string"
            ? (branchSnap.data()!.timezone as string)
            : DEFAULT_ORGANIZATION_TIMEZONE;

        if (!isCampaignScheduleCurrentlyOpen(campaign.schedule, Timestamp.now(), branchTimeZone)) {
          boncukError(
            "failed-precondition",
            "The selected campaign is not currently within its scheduled window.",
            "campaign/schedule-not-open",
          );
        }

        campaignPreCheck = campaign;
      }

      const pricingPolicy = await loadCanonicalChannelPricingPolicy(db, restaurantId);
      const pass1 = await buildLines(
        db,
        rawItems,
        { restaurantId },
        pricingPolicy,
        catalogRewardPreCheck?.redeemedProductId ?? null,
      );
      let lines = pass1.lines;
      const normalizedItems = pass1.normalizedItems;
      const rewardAppliedLineIndex = pass1.rewardAppliedLineIndex;

      // -------------------------------------------------------------
      // Server-Authoritative Campaign Engine P8-C.3 — discount resolution +
      // PASS 2 rebuild. `resolveCampaignDiscount` (campaignPricing.ts) is
      // the exact same pure, shared resolver every other channel uses —
      // never a dine-in-specific reimplementation. Minimum-basket is
      // evaluated by that resolver itself against PASS 1's own (pre-
      // discount) line subtotals — dine-in has no separate restaurant-
      // operational minimum-order check to preserve (unlike delivery's
      // `area.minimumOrderMinorUnits`), so PASS 1's own pricing is the
      // canonical pre-discount basket.
      // -------------------------------------------------------------
      let selectedBenefitType: SelectedBenefitType = "none";
      let campaignDiscountMinorUnits = 0;
      let campaignOrderSnapshot: CampaignOrderSnapshot | null = null;
      if (campaignPreCheck !== null) {
        const campaign = campaignPreCheck;
        const discountResult = resolveCampaignDiscount(campaign, pass1.campaignLines);
        if (discountResult.status === "minimum-basket-not-met") {
          boncukError(
            "failed-precondition",
            "This order does not meet the selected campaign's minimum basket requirement.",
            "campaign/minimum-basket-not-met",
          );
        }
        if (discountResult.status === "trigger-quantity-not-met") {
          boncukError(
            "failed-precondition",
            "This order does not meet the selected campaign's required purchase quantity.",
            "campaign/trigger-quantity-not-met",
          );
        }
        if (discountResult.status === "no-eligible-line") {
          boncukError(
            "invalid-argument",
            "None of the items in this order are eligible for the selected campaign.",
            "campaign/no-eligible-line",
          );
        }
        const lineDiscounts = new Map(
          discountResult.lineDiscounts.map((d) => [d.lineIndex, d.discountMinorUnits]),
        );
        // PASS 2 — rebuild lines with the resolved per-line campaign
        // discount applied. `rewardedProductId: null` — campaign and
        // catalogReward are mutually exclusive, so this pass never needs
        // `freeUnitCount` too.
        const pass2 = await buildLines(db, rawItems, { restaurantId }, pricingPolicy, null, lineDiscounts);
        lines = pass2.lines;

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
          orderChannel: DINE_IN_COMMERCIAL_CHANNEL,
        };
      }

      // Never patch grandTotal afterward — `pricing` is derived exactly
      // once, from whichever `lines` (pass1, or pass2 if a campaign
      // discount was applied) are final at this point.
      const pricing = computeOrderPriceBreakdown(lines);

      const normalizedForFingerprint = {
        tableSessionId,
        items: normalizedItems,
        customerNote,
        selectedRewardId,
        // Server-Authoritative Campaign Engine P8-C.3 — same reasoning, for
        // the mutually exclusive campaign selection: a retry that reuses
        // the same submissionKey but changes selectedCampaignId is "a
        // different order payload," never silently accepted.
        selectedCampaignId,
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

      // `selectedBenefitType` was already declared above (Server-
      // Authoritative Campaign Engine P8-C.3's own two-pass block) — reused
      // here, never redeclared; a campaign selection guarantees
      // `selectedRewardId === null` (`enforceBenefitExclusivity`), so the
      // catalogReward block below never overwrites an already-`"campaign"`
      // value.
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
      // Server-Authoritative Campaign Engine P8-C.3 (2026-08-25) — usage
      // reservation is the FIRST write-phase statement, mirroring
      // `submitTakeawayOrder.ts`'s own placement exactly.
      // `reserveCampaignUsage` (the shared `campaignUsage.ts` primitive,
      // reused verbatim) performs its OWN internal reads (counter/
      // reservation existence) THEN writes atomically — calling it here
      // guarantees ALL of its reads happen before ANY write in this ENTIRE
      // transaction. `customerId: uid` here is always a real, phone-
      // verified customer — campaign selection is rejected for guest
      // dine-in orders before this transaction is ever opened (see the
      // guest rejection above), so there is no "campaign-on-guest" case to
      // separately handle here.
      // ---------------------------------------------------------------
      const now = new Date();

      if (campaignPreCheck !== null) {
        const reserveResult = await reserveCampaignUsage(db, tx, {
          organizationId,
          campaignId: campaignPreCheck.campaignId,
          customerId: uid,
          orderId,
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
            "You have already used the selected campaign the maximum number of times.",
            "campaign/customer-usage-limit-reached",
          );
        }
        if (reserveResult.status === "already-reserved") {
          boncukError(
            "failed-precondition",
            "A campaign usage reservation already exists for this order.",
            "campaign/reservation-conflict",
          );
        }
      }

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
          campaign: campaignOrderSnapshot,
          discountMinorUnits: campaignDiscountMinorUnits,
        }),
      );

      return { orderId, orderNumber, duplicate: false };
    });
  },
);
