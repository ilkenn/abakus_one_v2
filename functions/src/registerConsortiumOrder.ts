import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission } from "./staffAuthorization";

/**
 * AP-6 Sprint 3 — registers a consortium/external-merchant delivery order:
 * a package our own courier fleet carries for another, independent
 * restaurant, never prepared by our own kitchen. Staff callable
 * (`manageCourierDispatch` — the same class of manager-supervised dispatch
 * decision as `assignCourierToOrder.ts`, reused rather than a new
 * permission).
 *
 * Writes the order directly at `status: "readyForPickup"`, `channel:
 * "delivery"`, with empty `lines`/zeroed commercial `pricing` (the
 * merchant's own menu/pricing is their business, not ours — only the
 * delivery fee we're charging them matters here, captured in both
 * `pricing.deliveryFee`/`grandTotal` for display and the dedicated
 * `consortiumDeliveryFeeMinorUnits` field the completion hook in
 * `advanceDeliveryOrderStatus.ts` copies verbatim into a
 * `ConsortiumDeliverySettlement`). Never routes through
 * `pendingConfirmation`/`confirmed`/`preparing` — the KDS-isolation
 * guarantee ("never enqueues kitchen work") is therefore structural: no
 * confirm callable that calls `prepareKitchenWorkAndStockConsumption`
 * (`acceptOrderLine.ts`) is ever invoked for an order created here. The
 * Firestore-rules-level half of that same guarantee lives on
 * `kitchenWorkItems`'s own client `create` rule.
 *
 * **The customer drop-off address is deliberately a lightweight, manually
 * entered shape this sprint** — not the full geocoded `DeliveryAddressSnapshot`
 * a real customer checkout produces (`savedAddressId`/provider place id/
 * verified lat-long). Only `neighborhoodName` (the dispatch console's own
 * clustering key) and a free-text `addressDescription` are meaningfully
 * collected from staff; every other `DeliveryAddressSnapshot` field the
 * Dart mapper's `fromFirestore` requires non-null is defaulted here
 * (`providerSource: "manual"`, `latitude`/`longitude: 0`, empty ids) so the
 * document still round-trips through the existing mapper without crashing.
 * A managed `consortiumMerchants` roster and true address geocoding are
 * both explicitly out of scope this sprint — `merchantId`/`merchantName`
 * are free-form, staff-entered strings, not a foreign-key relationship.
 */

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} must be a non-empty string.`);
  }
  return value;
}

function requireNonNegativeInt(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    throw new HttpsError("invalid-argument", `${field} must be a non-negative integer.`);
  }
  return value;
}

function optionalString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

export const registerConsortiumOrder = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireString(data.organizationId, "organizationId");
    const branchId = requireString(data.branchId, "branchId");
    const merchantId = requireString(data.merchantId, "merchantId");
    const merchantName = requireString(data.merchantName, "merchantName");
    const pickupAddress = requireString(data.pickupAddress, "pickupAddress");
    const consortiumDeliveryFeeMinorUnits = requireNonNegativeInt(
      data.consortiumDeliveryFeeMinorUnits,
      "consortiumDeliveryFeeMinorUnits",
    );
    const contactFirstName = requireString(data.contactFirstName, "contactFirstName");
    const contactLastName = requireString(data.contactLastName, "contactLastName");
    const contactPhone = requireString(data.contactPhone, "contactPhone");
    const dropoffAddressDescription = requireString(
      data.dropoffAddressDescription,
      "dropoffAddressDescription",
    );
    const dropoffNeighborhoodName = optionalString(data.dropoffNeighborhoodName);
    const dropoffProvinceName = optionalString(data.dropoffProvinceName) ?? "İstanbul";
    const dropoffDistrictName = optionalString(data.dropoffDistrictName) ?? "";

    requireStaffPermission(request, organizationId, "manageCourierDispatch");

    const db = getFirestore();
    const branchDoc = await db.collection("branches").doc(branchId).get();
    if (!branchDoc.exists) {
      throw new HttpsError("not-found", "Branch not found.");
    }
    const branch = branchDoc.data()!;
    if (branch.organizationId !== organizationId) {
      throw new HttpsError("not-found", "Branch not found.");
    }
    const restaurantId = String(branch.restaurantId ?? "");

    const orderRef = db.collection("orders").doc();
    const orderId = orderRef.id;
    const orderNumber = `CO-${orderId.slice(-8).toUpperCase()}`;
    const now = new Date();
    const moneyField = (minorUnits: number) => ({ minorUnits, currencyCode: "TRY" });

    await orderRef.set({
      organizationId,
      orderId,
      orderNumber,
      status: "readyForPickup",
      channel: "delivery",
      branchId,
      restaurantId,
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
      scheduledFor: null,
      scheduledForTimestamp: null,
      estimatedReadyAt: null,
      assignedCourierId: null,
      courierType: null,
      trackingToken: null,
      merchantId,
      merchantName,
      pickupAddress,
      consortiumDeliveryFeeMinorUnits,
      contactFirstName,
      contactLastName,
      contactPhone,
      courierVisibility: "hidden",
      lines: [],
      pricing: {
        grossSubtotal: moneyField(0),
        discount: moneyField(0),
        taxableBase: moneyField(0),
        vatAmount: moneyField(0),
        serviceFee: moneyField(0),
        deliveryFee: moneyField(consortiumDeliveryFeeMinorUnits),
        packagingFee: moneyField(0),
        tip: moneyField(0),
        grandTotal: moneyField(consortiumDeliveryFeeMinorUnits),
      },
      deliveryAddressSnapshot: {
        savedAddressId: "",
        label: "Konsorsiyum Teslimatı",
        provinceId: "",
        provinceName: dropoffProvinceName,
        districtId: "",
        districtName: dropoffDistrictName,
        neighborhoodId: null,
        neighborhoodName: dropoffNeighborhoodName,
        streetId: null,
        streetName: null,
        buildingNo: null,
        buildingNoSource: null,
        apartmentNo: "",
        floor: null,
        addressDescription: dropoffAddressDescription,
        latitude: 0,
        longitude: 0,
        providerSource: "manual",
        providerPlaceId: null,
        serverVerifiedAt: now.toISOString(),
      },
      paymentMethodSnapshot: null,
      selectedBenefitType: "none",
      boncukRedemption: null,
      catalogReward: null,
      campaign: null,
      statusHistory: [
        {
          id: `${orderId}-transition-1`,
          type: "statusChange",
          description: "Status changed from created to readyForPickup",
          actor: "staff",
          timestamp: now.toISOString(),
          previousValue: "created",
          newValue: "readyForPickup",
        },
      ],
      version: 1,
      timestamps: {
        created: now.toISOString(),
        confirmed: null,
        preparing: null,
        ready: null,
        served: null,
        completed: null,
        cancelled: null,
      },
      customerNote: "",
      kitchenNote: "",
    });

    return { orderId, orderNumber };
  },
);
