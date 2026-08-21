import { randomUUID } from "node:crypto";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Firestore, Transaction } from "firebase-admin/firestore";
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
  type RawItem,
} from "./submitTakeawayOrder";
import { parseDeviceLocationCandidate } from "./fraud/deviceLocationCandidate";
import { distanceMeters } from "./fraud/geoDistance";
import { FRAUD_F2_POLICY_VERSION } from "./fraud/fraudEvidenceRepository";
import type { FraudEvidenceRecord, ServerFraudInterpretation } from "./fraud/fraudEvidenceTypes";
import { defaultReverseGeocodeFn, type ReverseGeocodeFn } from "./googleGeocodingClient";
import { defaultPlaceDetailsFn, type PlaceDetailsFn } from "./googlePlacesClient";
import { normalizePlaceDetails } from "./googlePlacesFieldMapping";

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

async function buildDeliveryLines(
  db: Firestore,
  rawItems: RawItem[],
  scope: { restaurantId: string },
  policy: CanonicalChannelPricingPolicy,
  tx: Transaction,
): Promise<{ lines: ComputedOrderLine[]; normalizedItems: unknown[] }> {
  const lines: ComputedOrderLine[] = [];
  const normalizedItems: unknown[] = [];
  for (const item of rawItems) {
    if (item.kind === "product") {
      const line = await buildProductLine(db, item, scope, "delivery", policy, tx);
      lines.push(line);
      normalizedItems.push({
        kind: "product",
        productId: item.productId,
        quantity: item.quantity,
        selectedModifiers: item.selectedModifiers ?? [],
        note: item.note ?? "",
      });
    } else {
      const line = await buildBowlLine(db, item, scope, "delivery", policy, tx);
      lines.push(line);
      normalizedItems.push({
        kind: "bowl",
        quantity: item.quantity,
        ingredientIds: item.ingredientIds,
        note: item.note ?? "",
      });
    }
  }
  return { lines, normalizedItems };
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
      discount: moneyField(0),
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

      const policy = await loadCanonicalChannelPricingPolicy(db, area.restaurantId, tx);
      const { lines, normalizedItems } = await buildDeliveryLines(
        db,
        rawItems,
        { restaurantId: area.restaurantId },
        policy,
        tx,
      );
      const pricing = computeOrderPriceBreakdown(lines);

      // Correction §8 — minimum order evaluated against the SERVER-
      // CALCULATED subtotal (final delivery-channel prices already
      // applied), never a client-supplied total.
      if (pricing.grossSubtotalMinorUnits < area.minimumOrderMinorUnits) {
        throw new HttpsError("failed-precondition", "Minimum sipariş tutarı karşılanmıyor.");
      }

      const normalizedForFingerprint = {
        savedAddressId,
        paymentMethodId,
        items: normalizedItems,
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

