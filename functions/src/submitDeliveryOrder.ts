import { randomUUID } from "node:crypto";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Firestore, Transaction, Timestamp } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { googlePlacesServerKey, resolveApiKey } from "./deliveryPlaces";
import { resolveDeliveryServiceArea, slugifyAddressComponent } from "./deliveryServiceAreas";
import { isEnabledForDeliveryCheckout } from "./deliveryPaymentPolicy";
import { DELIVERY_PAYMENT_METHOD_CATALOG } from "./deliveryPaymentMethodCatalog";
import { ORDER_PRICING_AUTHORITY_SERVER_V1 } from "./orderPricingAuthority";
import {
  loadCanonicalChannelPricingPolicy,
  type CanonicalChannelPricingPolicy,
} from "./takeawayCatalog";
import {
  computeOrderPriceBreakdown,
  type ComputedOrderLine,
  type ComputedPriceBreakdown,
} from "./takeawayPricing";
import {
  invalid,
  parseItems,
  buildProductLine,
  buildBowlLine,
  sha256Hex,
  computeRequestFingerprint,
  findFirstEligibleCartProductId,
  type RawItem,
  type CatalogRewardOrderSnapshot,
} from "./submitTakeawayOrder";
import { parseDeviceLocationCandidate } from "./fraud/deviceLocationCandidate";
import { distanceMeters } from "./fraud/geoDistance";
import { FRAUD_F2_POLICY_VERSION } from "./fraud/fraudEvidenceRepository";
import type { FraudEvidenceRecord, ServerFraudInterpretation } from "./fraud/fraudEvidenceTypes";
import { defaultReverseGeocodeFn, type ReverseGeocodeFn } from "./googleGeocodingClient";
import { defaultPlaceDetailsFn, type PlaceDetailsFn } from "./googlePlacesClient";
import { normalizePlaceDetails } from "./googlePlacesFieldMapping";
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
import {
  boncukError,
  sanitizeRequestedBoncukAmount,
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
 * Boncuk Loyalty P7-D (2026-08-24) — the real, server-derived commercial
 * channel of every order this callable ever creates. Mirrors
 * `submitTakeawayOrder.ts`'s own `TAKEAWAY_COMMERCIAL_CHANNEL` exactly.
 */
const DELIVERY_COMMERCIAL_CHANNEL: CanonicalCommercialChannel = "delivery";

/**
 * The ONLY authoritative creation path for customer delivery orders —
 * Paket Servis P.3. Mirrors `submitTakeawayOrder.ts`'s exact shape and
 * reuses its item-parsing/line-building functions verbatim (exported from
 * that file for this reason — both take `channel` as a plain parameter
 * already, so nothing there needed to change). No standalone
 * `captureOrderSubmitFraudEvidence` callable exists — FRAUD-F.2 evidence
 * is created inside this same callable, in the same transaction as the
 * order itself.
 *
 * **Server is sole authority** for organization/branch/restaurant scope
 * (resolved from the customer's own verified address via
 * `deliveryServiceAreas`, never from client input), product/bowl
 * existence/availability/price, channel-adjusted pricing, computed totals,
 * payment-method eligibility, delivery-address snapshot, initial status,
 * and every fraud-evidence field. No field in the accepted request shape
 * carries a price, a risk value, an App Check state, or a tenant id.
 *
 * **Login is required. No guest/anonymous delivery ordering exists.**
 * `isRealCustomer` (phone-verified) is required unconditionally — unlike
 * `submitTakeawayOrder`'s dual QR-guest/authenticated dispatch, there is
 * only one path here.
 */

const MAX_SUBMISSION_KEY_LENGTH = 200;

function sanitizeSubmissionKey(raw: unknown): string {
  if (typeof raw !== "string" || raw.length === 0) invalid("submissionKey is required.");
  if (raw.length > MAX_SUBMISSION_KEY_LENGTH) invalid("submissionKey is too long.");
  return raw;
}

function requireNonEmptyString(raw: unknown, fieldName: string): string {
  if (typeof raw !== "string" || raw.length === 0) invalid(`${fieldName} is required.`);
  return raw as string;
}

/** Deterministic order id from (actor uid, submissionKey) — mirrors `deriveOrderId` in submitTakeawayOrder.ts exactly, distinct prefix so delivery/takeaway ids can never collide. */
function deriveDeliveryOrderId(uid: string, submissionKey: string): string {
  return `delivery-${sha256Hex(`${uid}|${submissionKey}`)}`;
}

function deriveDeliveryOrderNumber(orderId: string): string {
  return `DL-${orderId.slice(orderId.length - 8).toUpperCase()}`;
}

/**
 * Server-Authoritative Campaign Engine P8-C.1 (2026-08-25) —
 * `campaignLineDiscounts` (line index -> resolved minor-unit discount) is
 * threaded through to each line's own `buildOrderLine` call, and every
 * built line's real, channel-priced info is ALSO captured into
 * `campaignLines` (`campaignPricing.ts`'s own input shape), piggybacking on
 * data already fetched for the line — no extra Firestore reads. Mirrors
 * `submitTakeawayOrder.ts`'s own `buildLines` two-pass pattern exactly (the
 * shared campaign engine reused verbatim, never re-implemented) —
 * `campaignLineDiscounts: null` (the default) means "no campaign discount
 * to apply this call," so every pre-P8-C.1 caller behaves identically to
 * before.
 */
async function buildDeliveryLines(
  db: Firestore,
  rawItems: RawItem[],
  scope: { restaurantId: string },
  policy: CanonicalChannelPricingPolicy,
  tx: Transaction,
  rewardedProductId: string | null = null,
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
      // Only the FIRST matching line ever receives the free unit — mirrors
      // findFirstEligibleCartProductId's own tie-break exactly (P7-C's
      // `buildLines`), so the pre-buildLines eligibility scan and this
      // application are always consistent with each other.
      const isRewardedLine =
        rewardAppliedLineIndex === null &&
        rewardedProductId !== null &&
        item.productId === rewardedProductId;
      const line = await buildProductLine(
        db,
        item,
        scope,
        "delivery",
        policy,
        tx,
        isRewardedLine ? 1 : 0,
        campaignDiscountForLine,
      );
      if (isRewardedLine) rewardAppliedLineIndex = lineIndex;
      lines.push(line);
      campaignLines.push({
        lineIndex,
        productId: line.productId,
        categoryId: line.categoryId,
        quantity: line.quantity,
        unitBaseMinorUnits: line.unitPriceMinorUnits + line.modifierTotalMinorUnits,
      });
      normalizedItems.push({
        kind: "product",
        productId: item.productId,
        quantity: item.quantity,
        selectedModifiers: item.selectedModifiers ?? [],
        note: item.note ?? "",
      });
    } else {
      const line = await buildBowlLine(
        db,
        item,
        scope,
        "delivery",
        policy,
        tx,
        0,
        campaignDiscountForLine,
      );
      lines.push(line);
      campaignLines.push({
        lineIndex,
        // A Bowl Builder line has no real canonical product/category id —
        // structurally ineligible for any product/category-scoped campaign,
        // never a fake id standing in for one.
        productId: null,
        categoryId: null,
        quantity: line.quantity,
        unitBaseMinorUnits: line.unitPriceMinorUnits + line.modifierTotalMinorUnits,
      });
      normalizedItems.push({
        kind: "bowl",
        quantity: item.quantity,
        ingredientIds: item.ingredientIds,
        note: item.note ?? "",
      });
    }
  }
  return { lines, normalizedItems, rewardAppliedLineIndex, campaignLines };
}

interface DeliveryAddressFields {
  savedAddressId: string;
  label: string;
  provinceId: string;
  provinceName: string;
  districtId: string;
  districtName: string;
  neighborhoodId: string | null;
  neighborhoodName: string | null;
  streetId: string | null;
  streetName: string | null;
  buildingNo: string | null;
  buildingNoSource: string | null;
  apartmentNo: string;
  floor: string | null;
  addressDescription: string | null;
  latitude: number;
  longitude: number;
  providerSource: string;
  providerPlaceId: string | null;
  serverVerifiedAt: string;
}

/** Mirrors `SavedAddress.toDeliveryAddressSnapshot()` (Dart) — reimplemented server-side since no Dart<->TypeScript sharing mechanism exists in this codebase (same duplication precedent as every other mirrored file). */
function buildDeliveryAddressFields(
  address: FirebaseFirestore.DocumentData,
  savedAddressId: string,
  provinceId: string,
  districtId: string,
): DeliveryAddressFields {
  const neighborhoodName = typeof address.neighborhoodName === "string" ? address.neighborhoodName : null;
  const streetName = typeof address.streetName === "string" ? address.streetName : null;
  return {
    savedAddressId,
    label: String(address.label ?? ""),
    provinceId,
    provinceName: String(address.provinceName),
    districtId,
    districtName: String(address.districtName),
    neighborhoodId: neighborhoodName ? slugifyAddressComponent(neighborhoodName) : null,
    neighborhoodName,
    streetId: streetName ? slugifyAddressComponent(streetName) : null,
    streetName,
    buildingNo: typeof address.buildingNo === "string" ? address.buildingNo : null,
    buildingNoSource: typeof address.buildingNoSource === "string" ? address.buildingNoSource : null,
    apartmentNo: String(address.apartmentNo ?? ""),
    floor: typeof address.floor === "string" ? address.floor : null,
    addressDescription: typeof address.addressDescription === "string" ? address.addressDescription : null,
    latitude: Number(address.latitude),
    longitude: Number(address.longitude),
    providerSource: String(address.providerSource ?? ""),
    providerPlaceId: typeof address.providerPlaceId === "string" ? address.providerPlaceId : null,
    serverVerifiedAt: String(address.verifiedAt),
  };
}

/** The fully-resolved, not-yet-written redemption effects — computed during the transaction's read phase, applied only during its write phase (Firestore requires every `tx.get()` to happen before any `tx.set()`/`tx.create()`). Mirrors `submitTakeawayOrder.ts`'s own `PendingBoncukRedemption` exactly — same shape, same fields, channel-neutral. */
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

function buildDeliveryOrderDocument(params: {
  organizationId: string;
  orderId: string;
  orderNumber: string;
  branchId: string;
  restaurantId: string;
  customerId: string;
  addressFields: DeliveryAddressFields;
  paymentMethodId: string;
  lines: ComputedOrderLine[];
  pricing: ComputedPriceBreakdown;
  now: Date;
  fingerprint: string;
  selectedBenefitType: SelectedBenefitType;
  boncukRedemption: PendingBoncukRedemption["orderSnapshot"] | null;
  catalogReward: CatalogRewardOrderSnapshot | null;
  /**
   * Server-Authoritative Campaign Engine P8-C.1 (2026-08-25) — the
   * immutable per-order campaign snapshot when `selectedBenefitType ===
   * "campaign"`; `null` otherwise, including every pre-P8-C.1 order. Never
   * re-read from the live `campaigns` document by any future consumer —
   * this snapshot is the sole source of historical truth for what was
   * applied. Mirrors `submitTakeawayOrder.ts`'s own `buildOrderDocument`
   * field exactly.
   */
  campaign: CampaignOrderSnapshot | null;
  /**
   * The EXACT total campaign discount already baked into `pricing`'s own
   * `grossSubtotal`/`grandTotal` via the discounted lines above — `0` for
   * every order without a campaign (preserves the pre-P8-C.1 hardcoded-zero
   * behavior byte-for-byte).
   */
  discountMinorUnits: number;
}) {
  const currencyCode = "TRY";
  const moneyField = (minorUnits: number) => ({ minorUnits, currencyCode });
  const paymentMetadata = DELIVERY_PAYMENT_METHOD_CATALOG[params.paymentMethodId];

  return {
    organizationId: params.organizationId,
    orderId: params.orderId,
    orderNumber: params.orderNumber,
    status: "pendingConfirmation",
    channel: "delivery",
    // Boncuk Loyalty P2A security fix (2026-08-21) — server-stamped only,
    // never accepted from a request parameter. See
    // `functions/src/orderPricingAuthority.ts` for why this is a distinct
    // concept from `channel`. Stamped here for consistency even though
    // delivery is already structurally blocked from direct client
    // creation — one reusable pricing-authority contract for every
    // trusted server channel, present and future.
    pricingAuthority: ORDER_PRICING_AUTHORITY_SERVER_V1,
    branchId: params.branchId,
    restaurantId: params.restaurantId,
    customerId: params.customerId,
    tableId: null,
    tableSessionId: null,
    guestSessionId: null,
    guestAuthUid: null,
    reservationContextId: null,
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
      // The delivery "surcharge" is already baked into each line's
      // unitPrice via the channel-adjusted pricing policy (LOCKED rule) —
      // there is no separate flat delivery fee to record here.
      deliveryFee: moneyField(0),
      packagingFee: moneyField(0),
      tip: moneyField(0),
      grandTotal: moneyField(params.pricing.grandTotalMinorUnits),
    },
    // Boncuk Loyalty P5-B (2026-08-24) — settlement, never a discount
    // (BR-LOYALTY-019): `pricing` above is never touched by redemption.
    // Server-computed and server-stamped only, mirroring
    // `submitTakeawayOrder.ts`'s own `buildOrderDocument` exactly — see
    // `firestore.rules`' `clientOrderCreateOmitsBoncukRedemption()` (already
    // generic across every order-create branch, no change needed there).
    selectedBenefitType: params.selectedBenefitType,
    boncukRedemption: params.boncukRedemption,
    // Boncuk Loyalty P7-D (2026-08-24) — same audit-snapshot discipline as
    // `submitTakeawayOrder.ts`'s own `buildOrderDocument`: `pricing` above
    // already reflects the reward (the rewarded line's own `lineDiscount`),
    // this is a read-only record of what was redeemed, never a second,
    // independently-applied discount.
    catalogReward: params.catalogReward,
    // Server-Authoritative Campaign Engine P8-C.1 (2026-08-25) — same
    // discipline: `pricing` above already reflects the campaign discount
    // (the discounted lines' own `lineDiscount`s), this is a read-only
    // audit record of what was applied, never a second discount.
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
    customerNote: "",
    kitchenNote: "",
    deliveryAddressSnapshot: { ...params.addressFields },
    paymentMethodSnapshot: {
      paymentMethodId: paymentMetadata.id,
      displayName: paymentMetadata.displayName,
      iconAssetPath: paymentMetadata.iconAssetPath,
      brandColorValue: paymentMetadata.brandColorValue,
      reportingCategory: paymentMetadata.reportingCategory,
      providerId: paymentMetadata.providerId,
      supportsSplitPaymentAtCapture: paymentMetadata.supportsSplitPaymentAtCapture,
      supportsRefundAtCapture: paymentMetadata.supportsRefundAtCapture,
      requiresReferenceNumberAtCapture: paymentMetadata.requiresReferenceNumberAtCapture,
      requiresApprovalAtCapture: paymentMetadata.requiresApprovalAtCapture,
      transactionReference: null,
      authorizationCode: null,
      terminalId: null,
    },
    deliverySubmissionFingerprint: params.fingerprint,
  };
}

export const submitDeliveryOrder = onCall(
  { secrets: [googlePlacesServerKey], enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    // FRAUD-F.2 — captured before any other work, mirrors FRAUD-F.1's
    // own serverReceivedAt discipline exactly.
    const serverReceivedAt = new Date();

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const uid = request.auth.uid;

    // Login is REQUIRED; no guest/anonymous delivery ordering. Unlike
    // submitTakeawayOrder's dual QR-guest/authenticated dispatch, there
    // is exactly one path here — a table/takeaway anonymous identity can
    // never reach it.
    const isRealCustomer = request.auth.token?.firebase?.sign_in_provider === "phone";
    if (!isRealCustomer) {
      throw new HttpsError(
        "permission-denied",
        "Delivery ordering requires a real, phone-verified customer identity.",
      );
    }

    const data = (request.data ?? {}) as Record<string, unknown>;
    const submissionKey = sanitizeSubmissionKey(data.submissionKey);
    const rawItems = parseItems(data.items);
    const savedAddressId = requireNonEmptyString(data.savedAddressId, "savedAddressId");
    const paymentMethodId = requireNonEmptyString(data.paymentMethodId, "paymentMethodId");
    // Boncuk Loyalty P5-B (2026-08-24) — the customer submits only a whole
    // Boncuk COUNT; every payment method (cash/card/mealCard alike) remains
    // compatible, since Boncuk settles part of the order regardless of how
    // the REMAINING amount is later collected — never treated as another
    // "benefit" competing with `paymentMethodId`.
    const requestedBoncukAmount = sanitizeRequestedBoncukAmount(data.requestedBoncukAmount);
    const selectedRewardId = sanitizeSelectedRewardId(data.selectedRewardId);
    // Server-Authoritative Campaign Engine P8-C.1 (2026-08-25) — the ONLY
    // campaign-related value this callable ever accepts; the server
    // resolves and re-validates everything else itself.
    const selectedCampaignId = sanitizeSelectedCampaignId(data.selectedCampaignId);

    // Boncuk Loyalty P7-D (2026-08-24) / Server-Authoritative Campaign
    // Engine P8-C.1 — locked rule, identical to `submitTakeawayOrder.ts`'s
    // own: cash Boncuk redemption, a catalog reward, and a campaign are all
    // mutually exclusive, exactly one benefit per order. Static,
    // data-independent — checked before any Firestore work. Reuses the one
    // shared exclusivity enforcement point (`benefitExclusivity.ts`) rather
    // than a delivery-specific duplicate of this check.
    enforceBenefitExclusivity({ requestedBoncukAmount, selectedRewardId, selectedCampaignId });

    if (!isEnabledForDeliveryCheckout(paymentMethodId)) {
      throw new HttpsError(
        "invalid-argument",
        "Seçtiğiniz ödeme yöntemi şu anda kullanılamıyor.",
      );
    }
    const paymentMetadata = DELIVERY_PAYMENT_METHOD_CATALOG[paymentMethodId];
    if (!paymentMetadata) {
      // Defensive — isEnabledForDeliveryCheckout and the catalog must stay
      // in sync (same 7 ids); this only trips if that invariant is ever
      // violated by a future edit.
      throw new HttpsError("invalid-argument", "Seçtiğiniz ödeme yöntemi şu anda kullanılamıyor.");
    }

    const appCheckState = request.app ? "VERIFIED" : "MISSING";
    const phoneVerified =
      typeof request.auth.token?.phone_number === "string" &&
      request.auth.token.phone_number.length > 0;
    const parsedCandidate = parseDeviceLocationCandidate(data.deviceLocationCandidate);

    const db = getFirestore();

    // ---------------------------------------------------------------
    // Address ownership + service-area resolution — the ONLY source of
    // organization/branch/restaurant scope for a delivery order. No
    // client-supplied restaurantId/branchId is ever accepted (unlike
    // submitTakeawayOrder's authenticated path, which requires an
    // explicit branch selection since a customer can walk into different
    // locations — delivery has no such concept; the address decides).
    // ---------------------------------------------------------------
    const addressSnap = await db.collection("customerAddresses").doc(savedAddressId).get();
    if (!addressSnap.exists) {
      throw new HttpsError("not-found", "No such address.");
    }
    const address = addressSnap.data()!;
    if (address.uid !== uid) {
      throw new HttpsError("permission-denied", "This address does not belong to the caller.");
    }
    if (address.verificationStatus !== "verified") {
      throw new HttpsError(
        "failed-precondition",
        "Bu adres için teslimat doğrulaması tamamlanmamış.",
      );
    }
    const requiredFields = ["latitude", "longitude", "provinceName", "districtName", "providerSource", "verifiedAt"];
    for (const field of requiredFields) {
      if (address[field] === undefined || address[field] === null) {
        throw new HttpsError(
          "failed-precondition",
          "Bu adres teslimat için yeterince doğrulanmamış.",
        );
      }
    }
    const provinceId = slugifyAddressComponent(String(address.provinceName));
    const districtId = slugifyAddressComponent(String(address.districtName));
    const neighborhoodId = slugifyAddressComponent(String(address.neighborhoodName ?? ""));

    const areaResult = await resolveDeliveryServiceArea(db, { districtId, neighborhoodId });
    if (areaResult.status === "notCovered") {
      throw new HttpsError(
        "failed-precondition",
        "Bu adrese şu anda paket servis hizmeti veremiyoruz.",
      );
    }
    if (areaResult.status === "ambiguous") {
      throw new HttpsError(
        "failed-precondition",
        "Bu adres için teslimat bölgesi yapılandırması belirsiz.",
      );
    }
    const area = areaResult.area;

    // ---------------------------------------------------------------
    // FRAUD-F.2 — device-location reverse-geocode, BEFORE the
    // transaction (external HTTP call; mirrors FRAUD-F.1's exact
    // reasoning for why this can't run inside a Firestore transaction).
    // Distance is computed against the SAVED ADDRESS's own verified
    // coordinates (the natural reference point at order-submit time),
    // never a client-supplied value.
    // ---------------------------------------------------------------
    let interpretation: ServerFraudInterpretation = {
      policyVersion: FRAUD_F2_POLICY_VERSION,
      phoneVerified,
      appCheckState,
    };
    if (parsedCandidate.availability === "available" && parsedCandidate.clientLocation) {
      const deviceLat = parsedCandidate.clientLocation.latitude;
      const deviceLon = parsedCandidate.clientLocation.longitude;
      interpretation = {
        ...interpretation,
        distanceMeters: distanceMeters(
          Number(address.latitude),
          Number(address.longitude),
          deviceLat,
          deviceLon,
        ),
      };
      try {
        const reverseGeocode: ReverseGeocodeFn = defaultReverseGeocodeFn();
        const devicePlaceId = await reverseGeocode(resolveApiKey(), deviceLat, deviceLon);
        if (devicePlaceId) {
          const detailsFn: PlaceDetailsFn = defaultPlaceDetailsFn();
          const raw = await detailsFn(resolveApiKey(), devicePlaceId, randomUUID());
          if (raw) {
            const normalized = normalizePlaceDetails(devicePlaceId, raw);
            interpretation = {
              ...interpretation,
              province: normalized.provinceName,
              district: normalized.districtName,
              neighborhood: normalized.neighborhoodName,
              street: normalized.routeName,
              buildingNumber: normalized.streetNumber,
              formattedAddress: normalized.formattedAddress,
              providerPlaceId: normalized.providerPlaceId,
            };
          }
        }
      } catch (error) {
        logger.warn(
          "[submitDeliveryOrder] order-submit device-location reverse-geocode failed; " +
            "order submission proceeds, evidence keeps raw coordinates only.",
          { message: error instanceof Error ? error.message : String(error) },
        );
      }
    }

    const orderId = deriveDeliveryOrderId(uid, submissionKey);
    const orderNumber = deriveDeliveryOrderNumber(orderId);
    const fraudEvidenceId = `${orderId}-order-submit-evidence`;
    const fraudRiskContextId = `${orderId}-risk-context`;

    // ---------------------------------------------------------------
    // Single authoritative transaction — order document, delivery/
    // payment snapshots, orderSubmit FraudEvidence, and FraudRiskContext
    // all committed together or not at all. Menu/pricing resolution
    // (Firestore reads only, no external calls) happens inside, mirroring
    // submitTakeawayOrder.ts's own transaction shape exactly.
    // ---------------------------------------------------------------
    return db.runTransaction(async (tx) => {
      const orderRef = db.collection("orders").doc(orderId);
      const existing = await tx.get(orderRef);

      // -------------------------------------------------------------
      // Boncuk Loyalty P7-D (2026-08-24) — catalog-reward PRE-resolution.
      // Deliberately BEFORE `buildDeliveryLines`, mirroring
      // `submitTakeawayOrder.ts`'s own placement exactly: a catalog
      // reward's validity/eligibility checks need no pricing at all, only
      // the reward definition and the raw cart contents — resolving here
      // lets `buildDeliveryLines` receive the rewarded product id and apply
      // the free unit as it builds the line.
      // -------------------------------------------------------------
      const organizationId = area.organizationId;
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
        if (!reward.eligibleChannels.includes(DELIVERY_COMMERCIAL_CHANNEL)) {
          boncukError(
            "failed-precondition",
            "The selected reward is not available for the Paket Servis (Delivery) channel.",
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
      // Server-Authoritative Campaign Engine P8-C.1 (2026-08-25) —
      // campaign PRE-check. Mirrors `submitTakeawayOrder.ts`'s own
      // placement/shape exactly, reusing the shared engine
      // (`campaignEngine.ts`/`campaignScheduling.ts`) verbatim — no
      // delivery-specific duplicate eligibility logic. Trusted server
      // state only: existence, tenant match, active/non-archived,
      // `eligibleChannels` includes `"delivery"`, and currently within the
      // campaign's own schedule (trusted server time + the resolved
      // branch's own timezone, never a client-supplied instant).
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
        if (!campaign.eligibleChannels.includes(DELIVERY_COMMERCIAL_CHANNEL)) {
          boncukError(
            "failed-precondition",
            "The selected campaign is not available for the Paket Servis (Delivery) channel.",
            "campaign/channel-not-eligible",
          );
        }
        const branchSnap = await tx.get(db.collection("branches").doc(area.branchId));
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

      const policy = await loadCanonicalChannelPricingPolicy(db, area.restaurantId, tx);
      const pass1 = await buildDeliveryLines(
        db,
        rawItems,
        { restaurantId: area.restaurantId },
        policy,
        tx,
        catalogRewardPreCheck?.redeemedProductId ?? null,
      );
      let lines = pass1.lines;
      const rewardAppliedLineIndex = pass1.rewardAppliedLineIndex;
      let normalizedItems = pass1.normalizedItems;
      let pricing = computeOrderPriceBreakdown(lines);

      // Correction §8 — minimum order evaluated against the SERVER-
      // CALCULATED subtotal (final delivery-channel prices already
      // applied), never a client-supplied total. Deliberately evaluated
      // against PASS 1 (pre-campaign-discount) — the restaurant's own
      // operational minimum is about what it must prepare/deliver, not
      // what the customer ultimately pays after a discount, the exact same
      // "pre-discount canonical basket" reasoning `resolveCampaignDiscount`
      // itself uses for the campaign's own `minimumBasketMinorUnits`.
      if (pricing.grossSubtotalMinorUnits < area.minimumOrderMinorUnits) {
        throw new HttpsError("failed-precondition", "Minimum sipariş tutarı karşılanmıyor.");
      }

      // Server-Authoritative Campaign Engine P8-C.1 — discount resolution
      // + PASS 2 rebuild. `resolveCampaignDiscount` (campaignPricing.ts) is
      // the exact same pure, shared resolver `submitTakeawayOrder.ts` uses
      // — never a delivery-specific reimplementation. Minimum-basket is
      // evaluated by that resolver itself against PASS 1's own
      // (pre-discount) line subtotals.
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
            "invalid-argument",
            "This order does not meet the selected campaign's trigger quantity requirement.",
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
        const lineDiscounts = new Map(discountResult.lineDiscounts.map((d) => [d.lineIndex, d.discountMinorUnits]));
        const pass2 = await buildDeliveryLines(
          db,
          rawItems,
          { restaurantId: area.restaurantId },
          policy,
          tx,
          null,
          lineDiscounts,
        );
        lines = pass2.lines;
        normalizedItems = pass2.normalizedItems;
        pricing = computeOrderPriceBreakdown(lines);
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
          orderChannel: DELIVERY_COMMERCIAL_CHANNEL,
        };
      }

      const normalizedForFingerprint = {
        savedAddressId,
        paymentMethodId,
        items: normalizedItems,
        // Boncuk Loyalty P5-B — a retry that reuses the same submissionKey
        // but changes requestedBoncukAmount must be treated as "a different
        // order payload," mirroring submitTakeawayOrder.ts's own §10 rule
        // exactly — folding this into the fingerprint makes the EXISTING
        // mismatch-rejection branch below cover it for free.
        requestedBoncukAmount,
        // Boncuk Loyalty P7-D — same reasoning, for the mutually exclusive
        // catalog-reward selection.
        selectedRewardId,
        // Server-Authoritative Campaign Engine P8-C.1 — same reasoning, for
        // the mutually exclusive campaign selection.
        selectedCampaignId,
      };
      const fingerprint = computeRequestFingerprint(normalizedForFingerprint);

      if (existing.exists) {
        const existingData = existing.data()!;
        if (existingData.deliverySubmissionFingerprint !== fingerprint) {
          throw new HttpsError(
            "failed-precondition",
            "submissionKey was already used with a different order payload.",
          );
        }
        // Replay of an already-accepted submission — return immediately.
        // Never touches FraudEvidence/FraudRiskContext again; they were
        // already created (or deliberately not) on the original attempt.
        return { orderId, orderNumber: existingData.orderNumber, duplicate: true };
      }

      // -------------------------------------------------------------
      // Boncuk Loyalty P5-B — redemption resolution (reads only; this whole
      // block runs strictly before this transaction's first write, so
      // every tx.get() here is safely ordered ahead of every tx.set()/
      // tx.create() below, including the fraud-evidence reads that follow).
      // Reuses `calculateBoncukRedemption`/`resolveAccountForRedemption`
      // (loyaltyRedemption.ts) and the deterministic-ledger-id/account-
      // transaction/idempotency discipline verbatim — mirrors
      // submitTakeawayOrder.ts's own §7 block exactly, adapted only for
      // delivery's own eligible-basis (no separate delivery fee/tip to
      // subtract — the whole grandTotal is the basis, LOCKED per P5-B §4).
      // "if Boncuk requested: require a real phone customer" is already
      // structurally guaranteed above (delivery requires isRealCustomer
      // unconditionally, unlike takeaway's guest path) — no additional
      // branch needed. `organizationId` was already declared above (in the
      // catalog-reward pre-check block) — reused here, never redeclared.
      // `selectedBenefitType` was already declared above (Server-
      // Authoritative Campaign Engine P8-C.1's own two-pass block) — reused
      // here too, never redeclared; a campaign selection guarantees
      // `requestedBoncukAmount === 0` and `catalogRewardPreCheck === null`
      // (enforceBenefitExclusivity), so neither branch below ever
      // overwrites an already-`"campaign"` value.
      // -------------------------------------------------------------
      let pendingRedemption: PendingBoncukRedemption | null = null;
      let pendingCatalogReward: PendingCatalogRewardRedemption | null = null;

      if (requestedBoncukAmount > 0) {
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
          requestedBoncukAmount,
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
          sourceId: orderId,
        });
        const ledgerEntryRef = db.collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(ledgerEntryId);
        const ledgerSnap = await tx.get(ledgerEntryRef);
        if (ledgerSnap.exists) {
          // Defense-in-depth only — the order-level dedupe check above
          // already guarantees this transaction only reaches here for a
          // genuinely new order, so this should never happen. Fail closed
          // rather than silently proceeding.
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
            sourceId: orderId,
            orderId,
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
            idempotencyKey: orderId,
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
          // Structurally unreachable — buildDeliveryLines was given the
          // exact same redeemedProductId findFirstEligibleCartProductId
          // just found, so it always applies the free unit to a real
          // line. Defensive only.
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
          orderChannel: DELIVERY_COMMERCIAL_CHANNEL,
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
            orderChannel: DELIVERY_COMMERCIAL_CHANNEL,
          },
        };
      }

      // Prior addressSave evidence — equality-only query (no orderBy),
      // so no new Firestore composite index is required. `null` when
      // none exists; order submission remains valid either way.
      const priorSnap = await tx.get(
        db
          .collection("fraudEvidence")
          .where("subjectUid", "==", uid)
          .where("savedAddressId", "==", savedAddressId)
          .where("kind", "==", "addressSave")
          .limit(1),
      );
      const priorEvidenceId = priorSnap.empty ? null : priorSnap.docs[0].id;

      const now = new Date();
      const addressFields = buildDeliveryAddressFields(address, savedAddressId, provinceId, districtId);

      // ---------------------------------------------------------------
      // Write phase begins here — every tx.get() this transaction will
      // ever perform (menu/pricing, fraud-evidence, and — when a Boncuk
      // redemption was requested — loyaltyAccounts/loyaltyPolicies/ledger)
      // has already happened above.
      // ---------------------------------------------------------------
      // Server-Authoritative Campaign Engine P8-C.1 (2026-08-25) — usage
      // reservation is the FIRST write-phase statement, mirroring
      // `submitTakeawayOrder.ts`'s own placement exactly.
      // `reserveCampaignUsage` (the shared `campaignUsage.ts` primitive,
      // reused verbatim) performs its OWN internal reads (counter/
      // reservation existence) THEN writes atomically — calling it here
      // guarantees ALL of its reads happen before ANY write in this ENTIRE
      // transaction, satisfying "no reads after writes" without a manual
      // read/write split. `customerId` is always the real, authenticated
      // `uid` — delivery has no guest/anonymous path at all (unlike
      // takeaway), so there is no "campaign-on-guest" case to separately
      // reject here.
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

      tx.set(
        orderRef,
        buildDeliveryOrderDocument({
          organizationId: area.organizationId,
          orderId,
          orderNumber,
          branchId: area.branchId,
          restaurantId: area.restaurantId,
          customerId: uid,
          addressFields,
          paymentMethodId,
          lines,
          pricing,
          now,
          fingerprint,
          selectedBenefitType,
          boncukRedemption: pendingRedemption ? pendingRedemption.orderSnapshot : null,
          catalogReward: pendingCatalogReward ? pendingCatalogReward.orderSnapshot : null,
          campaign: campaignOrderSnapshot,
          discountMinorUnits: campaignDiscountMinorUnits,
        }),
      );

      const evidenceRecord: FraudEvidenceRecord = {
        id: fraudEvidenceId,
        kind: "orderSubmit",
        subjectUid: uid,
        savedAddressId,
        priorEvidenceId,
        clientLocation: parsedCandidate.clientLocation,
        availability: parsedCandidate.availability,
        unavailableReason: parsedCandidate.unavailableReason,
        serverReceivedAt: serverReceivedAt.toISOString(),
        createdAt: now.toISOString(),
        expiresAt: null,
        organizationId: area.organizationId,
        branchId: area.branchId,
        orderId,
        interpretation,
      };
      tx.set(db.collection("fraudEvidence").doc(fraudEvidenceId), evidenceRecord);

      tx.set(db.collection("fraudRiskContexts").doc(fraudRiskContextId), {
        id: fraudRiskContextId,
        orderId,
        evidenceIds: [fraudEvidenceId],
        signalIds: [],
        priorEvidenceId,
        policyVersion: FRAUD_F2_POLICY_VERSION,
        createdAt: now.toISOString(),
      });

      return { orderId, orderNumber, duplicate: false };
    });
  },
);

