import { createHash } from "crypto";
import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { requireActiveDeviceSession } from "./trustedDevice";
import { ORDER_PRICING_AUTHORITY_SERVER_V1 } from "./orderPricingAuthority";
import { loadCanonicalChannelPricingPolicy } from "./takeawayCatalog";
import { computeOrderPriceBreakdown, type ComputedOrderLine } from "./takeawayPricing";
import { vatAmountOf } from "./takeawayMoney";
import { buildProductLine, parseItems, sanitizeOrderNote, computeRequestFingerprint } from "./submitTakeawayOrder";
import { DELIVERY_PAYMENT_METHOD_CATALOG } from "./deliveryPaymentMethodCatalog";
import { prepareKitchenWorkAndStockConsumption, applyKitchenWorkAndStockConsumption } from "./acceptOrderLine";
import { preparePrintJobForAcceptance, applyPrintJobPlan } from "./printJobEngine";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId } from "./correlationId";
import { phoneSearchHmacSecret } from "./customerDirectoryConfig";
import {
  applyPosCustomerUpsert,
  normalizeTurkishPhone,
  preparePosCustomerUpsert,
  type PosCustomerAddress,
} from "./posCustomerBook";

/**
 * 2026-11-11 — Faz 2: staff open a Paket Servis (delivery) order from the
 * POS phone-order screen. Until now a delivery order could only come from a
 * phone-verified app customer (`submitDeliveryOrder`).
 *
 * - Authorization: `manageDeliveryOrders`, branch access, an active trusted
 *   device session — the same bar as confirming a delivery order.
 * - Pricing: every line is priced server-side on the delivery channel
 *   (`buildProductLine`, ×1.35 / nearest 5 TL policy); no campaign, Boncuk
 *   or reward (same as every staff entry).
 * - Product-owner decision 3 (flexible): no minimum-order or service-area
 *   gate; an optional manual delivery fee (default 0) carries 20% VAT.
 * - The staff entry IS the confirmation: the order is written `confirmed`
 *   and goes to the kitchen in the same transaction (kitchen work items,
 *   stock consumption, print job — `respondToDeliveryOrder`'s confirm path).
 * - The address is typed by hand: no coordinates, no provider verification
 *   (`providerSource: "staffManual"`); the dispatch board groups it by
 *   neighborhood as usual, the live map has no point for it.
 * - Courier note → `customerNote` (shown to the courier), kitchen note →
 *   `kitchenNote` (KDS + kitchen ticket), planned courier →
 *   `plannedCourierId` (assigned later with one tap — never automatically).
 * - The local customer book is upserted atomically (`posCustomerBook.ts`).
 * - Idempotent per (staff uid, submissionKey): a resend returns the same
 *   order; the same key with a different payload is refused.
 */

const DELIVERY_FEE_VAT_BASIS_POINTS = 2000;
const MAX_DELIVERY_FEE_MINOR_UNITS = 100000; // 1.000 TL
const MAX_SUBMISSION_KEY_LENGTH = 128;
const MAX_NAME_LENGTH = 80;
const MAX_ADDRESS_PART_LENGTH = 120;

/** Pay-on-delivery methods the POS offers — `DELIVERY_PAYMENT_METHOD_CATALOG` ids. */
export const STAFF_DELIVERY_PAYMENT_METHOD_IDS: ReadonlySet<string> = new Set([
  "cash",
  "credit_card",
  "pluxee",
  "multinet",
  "setcard",
  "edenred",
]);

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

function requireString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.trim().length === 0) invalid(`${field} is required.`);
  return (raw as string).trim();
}

function boundedString(raw: unknown, field: string, maxLength: number, { required = false } = {}): string {
  if (raw === undefined || raw === null || (typeof raw === "string" && raw.trim().length === 0)) {
    if (required) invalid(`${field} is required.`);
    return "";
  }
  if (typeof raw !== "string") invalid(`${field} must be a string.`);
  const trimmed = (raw as string).trim();
  if (trimmed.length > maxLength) invalid(`${field} must be at most ${maxLength} characters.`);
  return trimmed;
}

export interface StaffDeliveryAddressInput {
  label: string;
  neighborhoodName: string;
  streetName: string;
  buildingNo: string;
  apartmentNo: string;
  floor: string;
  addressDescription: string;
}

/** Neighborhood and street are required; the rest optional. */
export function parseStaffDeliveryAddress(raw: unknown): StaffDeliveryAddressInput {
  if (typeof raw !== "object" || raw === null) invalid("address is required.");
  const a = raw as Record<string, unknown>;
  return {
    label: boundedString(a.label, "address.label", 40),
    neighborhoodName: boundedString(a.neighborhoodName, "address.neighborhoodName", MAX_ADDRESS_PART_LENGTH, { required: true }),
    streetName: boundedString(a.streetName, "address.streetName", MAX_ADDRESS_PART_LENGTH, { required: true }),
    buildingNo: boundedString(a.buildingNo, "address.buildingNo", 20),
    apartmentNo: boundedString(a.apartmentNo, "address.apartmentNo", 20),
    floor: boundedString(a.floor, "address.floor", 20),
    addressDescription: boundedString(a.addressDescription, "address.addressDescription", 300),
  };
}

/** A manual delivery fee in minor units: absent = 0; an integer in [0, 1.000 TL]. */
export function parseDeliveryFee(raw: unknown): number {
  if (raw === undefined || raw === null) return 0;
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw < 0 || raw > MAX_DELIVERY_FEE_MINOR_UNITS) {
    invalid(`deliveryFeeMinorUnits must be an integer between 0 and ${MAX_DELIVERY_FEE_MINOR_UNITS}.`);
  }
  return raw as number;
}

export function parseStaffDeliveryPaymentMethod(raw: unknown): string {
  if (typeof raw !== "string" || !STAFF_DELIVERY_PAYMENT_METHOD_IDS.has(raw) || !DELIVERY_PAYMENT_METHOD_CATALOG[raw]) {
    invalid(`paymentMethodId must be one of: ${[...STAFF_DELIVERY_PAYMENT_METHOD_IDS].join(", ")}.`);
  }
  return raw as string;
}

/**
 * The order's pricing with the manual delivery fee added: the fee is part
 * of the grand total and carries its own 20% VAT (product lines keep their
 * own rate). Pure.
 */
export function priceWithDeliveryFee(lines: ComputedOrderLine[], deliveryFeeMinorUnits: number) {
  const breakdown = computeOrderPriceBreakdown(lines);
  const feeVat = vatAmountOf(deliveryFeeMinorUnits, DELIVERY_FEE_VAT_BASIS_POINTS);
  return {
    grossSubtotalMinorUnits: breakdown.grossSubtotalMinorUnits,
    taxableBaseMinorUnits: breakdown.taxableBaseMinorUnits + (deliveryFeeMinorUnits - feeVat),
    vatAmountMinorUnits: breakdown.vatAmountMinorUnits + feeVat,
    deliveryFeeMinorUnits,
    deliveryFeeVatMinorUnits: feeVat,
    grandTotalMinorUnits: breakdown.grandTotalMinorUnits + deliveryFeeMinorUnits,
  };
}

function sha256Hex(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export const submitStaffDeliveryOrder = onCall(
  { enforceAppCheck: shouldEnforceAppCheck(), secrets: [phoneSearchHmacSecret] },
  async (request: CallableRequest) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
    const staffUid = request.auth.uid;
    const data = (request.data ?? {}) as Record<string, unknown>;

    const organizationId = requireString(data.organizationId, "organizationId");
    const branchId = requireString(data.branchId, "branchId");
    const deviceId = requireString(data.deviceId, "deviceId");
    const deviceSessionId = requireString(data.deviceSessionId, "deviceSessionId");
    const submissionKey = requireString(data.submissionKey, "submissionKey");
    if (submissionKey.length > MAX_SUBMISSION_KEY_LENGTH) invalid("submissionKey is too long.");

    const rawItems = parseItems(data.items);
    const customer = (typeof data.customer === "object" && data.customer !== null ? data.customer : {}) as Record<string, unknown>;
    const firstName = boundedString(customer.firstName, "customer.firstName", MAX_NAME_LENGTH, { required: true });
    const lastName = boundedString(customer.lastName, "customer.lastName", MAX_NAME_LENGTH);
    const phoneNumber = normalizeTurkishPhone(requireString(customer.phone, "customer.phone"));
    if (!phoneNumber) invalid("customer.phone is not a valid Turkish phone number.");
    const linkedCustomerId = boundedString(customer.linkedCustomerId, "customer.linkedCustomerId", 128) || null;
    const address = parseStaffDeliveryAddress(data.address);
    const courierNote = sanitizeOrderNote(data.courierNote, "courierNote");
    const kitchenNote = sanitizeOrderNote(data.kitchenNote, "kitchenNote");
    const paymentMethodId = parseStaffDeliveryPaymentMethod(data.paymentMethodId);
    const deliveryFeeMinorUnits = parseDeliveryFee(data.deliveryFeeMinorUnits);
    const plannedCourierId = boundedString(data.plannedCourierId, "plannedCourierId", 128) || null;

    await requireStaffPermission(request, organizationId, "manageDeliveryOrders");
    await requireBranchAccess(request, organizationId, branchId);
    await requireActiveDeviceSession(organizationId, branchId, deviceId, deviceSessionId);

    const db = getFirestore();
    const branchDoc = await db.collection("branches").doc(branchId).get();
    if (!branchDoc.exists || branchDoc.data()!.organizationId !== organizationId) {
      throw new HttpsError("not-found", "Branch not found.");
    }
    const restaurantId = branchDoc.data()!.restaurantId as string;

    const orderId = `delivery-${sha256Hex(`${staffUid}|staff|${submissionKey}`)}`;
    const orderNumber = `DL-${orderId.slice(orderId.length - 8).toUpperCase()}`;
    const orderRef = db.collection("orders").doc(orderId);

    return db.runTransaction(async (tx) => {
      // --- read phase ----------------------------------------------------
      const policy = await loadCanonicalChannelPricingPolicy(db, restaurantId, tx);
      const lines: ComputedOrderLine[] = [];
      const normalizedItems: unknown[] = [];
      for (const item of rawItems) {
        if (item.kind !== "product") invalid('each item must have kind "product".');
        lines.push(await buildProductLine(db, item, { restaurantId }, "delivery", policy, tx));
        normalizedItems.push({
          productId: item.productId,
          quantity: item.quantity,
          selectedModifiers: item.selectedModifiers ?? [],
          note: item.note ?? "",
          excludedIngredients: item.excludedIngredients ?? [],
        });
      }
      const pricing = priceWithDeliveryFee(lines, deliveryFeeMinorUnits);
      const fingerprint = computeRequestFingerprint({
        path: "staffDelivery",
        organizationId,
        branchId,
        items: normalizedItems,
        firstName,
        lastName,
        phoneNumber,
        address,
        courierNote,
        kitchenNote,
        paymentMethodId,
        deliveryFeeMinorUnits,
        plannedCourierId,
      });

      const existing = await tx.get(orderRef);
      if (existing.exists) {
        const existingData = existing.data()!;
        if (existingData.deliverySubmissionFingerprint !== fingerprint) {
          throw new HttpsError("failed-precondition", "submissionKey was already used with a different order payload.");
        }
        return { orderId, orderNumber: existingData.orderNumber as string, duplicate: true };
      }

      let plannedCourierName: string | null = null;
      if (plannedCourierId) {
        const courierSnap = await tx.get(db.collection("couriers").doc(plannedCourierId));
        const courier = courierSnap.exists ? courierSnap.data()! : null;
        const eligible = Array.isArray(courier?.eligibleBranchIds) ? (courier!.eligibleBranchIds as string[]) : [];
        if (
          !courier ||
          (courier.branchId !== branchId && !eligible.includes(branchId)) ||
          (courier.status ?? "active") !== "active" ||
          (courier.type ?? "internal") !== "internal"
        ) {
          throw new HttpsError("failed-precondition", "The planned courier is not an active shop courier of this branch.", {
            code: "staffDelivery/courier-not-eligible",
          });
        }
        plannedCourierName = (courier.displayName as string | undefined) ?? null;
      }

      const now = Timestamp.now();
      const bookAddress: Omit<PosCustomerAddress, "lastUsedAt"> = { ...address };
      const customerPlan = await preparePosCustomerUpsert({
        tx,
        db,
        organizationId,
        phoneNumber,
        firstName,
        lastName,
        address: bookAddress,
        linkedCustomerId,
        now,
      });
      const stockPlan = await prepareKitchenWorkAndStockConsumption({
        tx,
        db,
        organizationId,
        branchId,
        orderId,
        channel: "delivery",
        acceptedLines: lines.map((line, index) => ({
          orderLineId: `kt-${orderId}-line-${index}`,
          productId: line.productId,
          quantity: line.quantity,
        })),
        performedByUid: staffUid,
        now,
      });
      const printPlan = await preparePrintJobForAcceptance({
        tx,
        db,
        organizationId,
        branchId,
        orderId,
        stationId: "shared",
        now,
      });

      // --- write phase ---------------------------------------------------
      const nowIso = now.toDate().toISOString();
      const money = (minorUnits: number) => ({ minorUnits, currencyCode: "TRY" });
      const payment = DELIVERY_PAYMENT_METHOD_CATALOG[paymentMethodId];
      tx.set(orderRef, {
        organizationId,
        orderId,
        orderNumber,
        status: "confirmed",
        channel: "delivery",
        pricingAuthority: ORDER_PRICING_AUTHORITY_SERVER_V1,
        branchId,
        restaurantId,
        // The order is the shop's, not an app customer's: no loyalty earning
        // or customer-app visibility is implied by a staff entry.
        customerId: null,
        tableId: null,
        tableSessionId: null,
        guestSessionId: null,
        guestAuthUid: null,
        reservationContextId: null,
        takeawayEntrySessionId: null,
        pickupMode: null,
        pickupTime: null,
        pickupTimeTimestamp: null,
        contactFirstName: firstName,
        contactLastName: lastName,
        contactPhone: phoneNumber,
        courierVisibility: "hidden",
        lines: lines.map((line) => ({
          productId: line.productId,
          productName: line.productName,
          modifiers: line.modifiers.map((m) => ({
            groupId: m.groupId,
            groupName: m.groupName,
            optionId: m.optionId,
            optionName: m.optionName,
            unitExtraPrice: money(m.unitExtraPriceMinorUnits),
            quantity: m.quantity,
          })),
          quantity: line.quantity,
          unitPrice: money(line.unitPriceMinorUnits),
          lineDiscount: money(line.lineDiscountMinorUnits),
          taxRateBasisPoints: line.taxBasisPoints,
          kitchenNote: line.kitchenNote,
          customerNote: line.customerNote,
          excludedIngredients: line.excludedIngredients,
        })),
        pricing: {
          grossSubtotal: money(pricing.grossSubtotalMinorUnits),
          discount: money(0),
          taxableBase: money(pricing.taxableBaseMinorUnits),
          vatAmount: money(pricing.vatAmountMinorUnits),
          serviceFee: money(0),
          deliveryFee: money(pricing.deliveryFeeMinorUnits),
          packagingFee: money(0),
          tip: money(0),
          grandTotal: money(pricing.grandTotalMinorUnits),
        },
        selectedBenefitType: "none",
        boncukRedemption: null,
        catalogReward: null,
        campaign: null,
        statusHistory: [
          {
            id: `${orderId}-transition-1`,
            type: "statusChange",
            description: "Status changed from created to confirmed",
            actor: "staff",
            timestamp: nowIso,
            previousValue: "created",
            newValue: "confirmed",
          },
        ],
        version: 1,
        timestamps: {
          created: nowIso,
          confirmed: nowIso,
          preparing: null,
          ready: null,
          served: null,
          completed: null,
          cancelled: null,
        },
        customerNote: courierNote,
        kitchenNote,
        deliveryAddressSnapshot: {
          savedAddressId: customerPlan.ref.id,
          label: address.label,
          provinceId: "",
          provinceName: "",
          districtId: "",
          districtName: "",
          neighborhoodId: null,
          neighborhoodName: address.neighborhoodName,
          streetId: null,
          streetName: address.streetName,
          buildingNo: address.buildingNo || null,
          buildingNoSource: null,
          apartmentNo: address.apartmentNo,
          floor: address.floor || null,
          addressDescription: address.addressDescription || null,
          latitude: null,
          longitude: null,
          providerSource: "staffManual",
          providerPlaceId: null,
          serverVerifiedAt: null,
        },
        paymentMethodSnapshot: {
          paymentMethodId: payment.id,
          displayName: payment.displayName,
          iconAssetPath: payment.iconAssetPath,
          brandColorValue: payment.brandColorValue,
          reportingCategory: payment.reportingCategory,
          providerId: payment.providerId,
          supportsSplitPaymentAtCapture: payment.supportsSplitPaymentAtCapture,
          supportsRefundAtCapture: payment.supportsRefundAtCapture,
          requiresReferenceNumberAtCapture: payment.requiresReferenceNumberAtCapture,
          requiresApprovalAtCapture: payment.requiresApprovalAtCapture,
          transactionReference: null,
          authorizationCode: null,
          terminalId: null,
        },
        payOnDelivery: true,
        plannedCourierId,
        plannedCourierName,
        posCustomerId: customerPlan.ref.id,
        staffEntry: { createdByStaffUid: staffUid, deviceId },
        deliverySubmissionFingerprint: fingerprint,
      });
      applyPosCustomerUpsert(tx, customerPlan);
      applyKitchenWorkAndStockConsumption(tx, db, stockPlan);
      applyPrintJobPlan(tx, db, printPlan);
      writeAuditEvent({
        tx,
        db,
        eventId: `staffDeliveryOrder-${orderId}`,
        organizationId,
        branchId,
        type: "order.staffDeliveryCreated",
        targetRef: orderRef.path,
        newValue: {
          status: "confirmed",
          grandTotalMinorUnits: pricing.grandTotalMinorUnits,
          deliveryFeeMinorUnits,
          paymentMethodId,
          plannedCourierId,
        },
        actorType: "staff",
        actorUid: staffUid,
        correlationId: generateCorrelationId(),
        now,
      });

      return {
        orderId,
        orderNumber,
        duplicate: false,
        grandTotalMinorUnits: pricing.grandTotalMinorUnits,
        posCustomerId: customerPlan.ref.id,
      };
    });
  },
);
