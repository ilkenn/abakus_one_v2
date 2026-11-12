import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp, type DocumentData } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { DELIVERY_PAYMENT_METHOD_CATALOG } from "./deliveryPaymentMethodCatalog";
import { COURIER_SETTLEMENTS_COLLECTION, DELIVERY_COLLECTIONS_COLLECTION } from "./courierSettlement";

/**
 * 2026-11-12 (Faz 4, ADR-080) — "Kurye & Paket Raporu": for a branch and a
 * date range, per courier and per courier kind (Restoran Kuryesi / Kayıtlı
 * Dış Kurye) — package count, average preparation and delivery time, the
 * tender mix (Nakit / POS / each meal-card brand), the cash-difference
 * total and the list of pool orders completed by external couriers.
 *
 * **Source of truth = the settlement records**, not the order list: a
 * package counts once it was closed at "Kurye Hesap Kapat"
 * (`deliveryCollections`, one per order, carrying the method the customer
 * actually paid with), and cash differences come from `courierSettlements`.
 * Both are written only by `settleCourierReturn`, so the report never
 * double-counts and never shows an order still on the road. The range
 * filters on `collectedAt` / `createdAt` (settlement time).
 *
 * Timing (minutes, per order, averaged over the orders that have the data):
 * - preparation = `timestamps.ready` − `timestamps.created`;
 * - delivery = (courier's "Teslim Ettim" `courierReportedDeliveredAt`, else
 *   the settlement time) − (courier's "Yola Çıktım" `departedAt`, else the
 *   `outForDelivery` status-history entry, else `timestamps.ready`). For a
 *   shop courier without the app this is "left the shop → account closed",
 *   so it includes the return trip; the screen says so.
 *
 * Read-only, `viewDeliveryReports` (manager and above) + branch access.
 */

export const MAX_REPORT_RANGE_DAYS = 92;
export const MAX_REPORT_COLLECTIONS = 5000;

export type CourierKind = "internal" | "pool";

export interface PaymentMethodTotal {
  paymentMethodId: string;
  displayName: string;
  reportingCategory: string;
  count: number;
  amountMinorUnits: number;
}

export interface ReportAggregate {
  packageCount: number;
  collectedMinorUnits: number;
  averagePreparationMinutes: number | null;
  averageDeliveryMinutes: number | null;
  cashDifferenceMinorUnits: number;
  settlementCount: number;
  paymentMethods: PaymentMethodTotal[];
}

export interface CourierReportRow extends ReportAggregate {
  courierId: string;
  courierName: string;
  courierKind: CourierKind;
}

export interface PoolOrderRow {
  orderId: string;
  orderNumber: string;
  courierId: string;
  courierName: string;
  neighborhoodName: string;
  amountMinorUnits: number;
  paymentMethodId: string;
  paymentMethodDisplayName: string;
  collectedAt: string;
  deliveryMinutes: number | null;
}

export interface CourierDeliveryReport {
  fromIso: string;
  toIso: string;
  totals: ReportAggregate;
  byKind: Record<CourierKind, ReportAggregate>;
  couriers: CourierReportRow[];
  poolOrders: PoolOrderRow[];
  truncated: boolean;
}

export interface ReportCollectionInput {
  orderId: string;
  orderNumber: string;
  courierId: string;
  paymentMethodId: string;
  paymentMethodDisplayName: string;
  reportingCategory: string;
  amountMinorUnits: number;
  collectedAtMillis: number;
}

export interface ReportSettlementInput {
  courierId: string;
  courierName: string;
  differenceMinorUnits: number;
}

export interface ReportOrderInput {
  courierType: string | null;
  neighborhoodName: string;
  createdMillis: number | null;
  readyMillis: number | null;
  dispatchedMillis: number | null;
  deliveredMillis: number | null;
}

export interface ReportCourierInput {
  displayName: string;
  type: string;
}

function toMillis(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (value instanceof Timestamp) return value.toMillis();
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
  }
  if (typeof value === "object" && typeof (value as { toMillis?: unknown }).toMillis === "function") {
    return (value as { toMillis: () => number }).toMillis();
  }
  return null;
}

/** The timing-relevant facts of an order document. Pure. */
export function reportOrderInputFrom(order: DocumentData): ReportOrderInput {
  const timestamps = (order.timestamps ?? {}) as Record<string, unknown>;
  const history = Array.isArray(order.statusHistory) ? (order.statusHistory as DocumentData[]) : [];
  const outForDelivery = history.find((entry) => entry?.newValue === "outForDelivery");
  const readyMillis = toMillis(timestamps.ready);
  return {
    courierType: typeof order.courierType === "string" ? order.courierType : null,
    neighborhoodName: String(order.deliveryAddressSnapshot?.neighborhoodName ?? ""),
    createdMillis: toMillis(timestamps.created),
    readyMillis,
    dispatchedMillis: toMillis(order.departedAt) ?? toMillis(outForDelivery?.timestamp) ?? readyMillis,
    deliveredMillis: toMillis(order.courierReportedDeliveredAt),
  };
}

function minutesBetween(from: number | null, to: number | null): number | null {
  if (from === null || to === null || to < from) return null;
  return (to - from) / 60000;
}

function roundOne(value: number): number {
  return Math.round(value * 10) / 10;
}

class Accumulator {
  packageCount = 0;
  collectedMinorUnits = 0;
  cashDifferenceMinorUnits = 0;
  settlementCount = 0;
  private prepSum = 0;
  private prepCount = 0;
  private deliverySum = 0;
  private deliveryCount = 0;
  private readonly methods = new Map<string, PaymentMethodTotal>();

  addCollection(c: ReportCollectionInput, prep: number | null, delivery: number | null) {
    this.packageCount += 1;
    this.collectedMinorUnits += c.amountMinorUnits;
    if (prep !== null) { this.prepSum += prep; this.prepCount += 1; }
    if (delivery !== null) { this.deliverySum += delivery; this.deliveryCount += 1; }
    const method = this.methods.get(c.paymentMethodId) ?? {
      paymentMethodId: c.paymentMethodId,
      displayName: c.paymentMethodDisplayName,
      reportingCategory: c.reportingCategory,
      count: 0,
      amountMinorUnits: 0,
    };
    method.count += 1;
    method.amountMinorUnits += c.amountMinorUnits;
    this.methods.set(c.paymentMethodId, method);
  }

  addSettlement(s: ReportSettlementInput) {
    this.settlementCount += 1;
    this.cashDifferenceMinorUnits += s.differenceMinorUnits;
  }

  build(): ReportAggregate {
    const categoryOrder = ["cash", "card", "mealCard"];
    return {
      packageCount: this.packageCount,
      collectedMinorUnits: this.collectedMinorUnits,
      averagePreparationMinutes: this.prepCount === 0 ? null : roundOne(this.prepSum / this.prepCount),
      averageDeliveryMinutes: this.deliveryCount === 0 ? null : roundOne(this.deliverySum / this.deliveryCount),
      cashDifferenceMinorUnits: this.cashDifferenceMinorUnits,
      settlementCount: this.settlementCount,
      paymentMethods: [...this.methods.values()].sort((a, b) => {
        const byCategory = categoryOrder.indexOf(a.reportingCategory) - categoryOrder.indexOf(b.reportingCategory);
        return byCategory !== 0 ? byCategory : b.amountMinorUnits - a.amountMinorUnits;
      }),
    };
  }
}

/** Builds the whole report from already-loaded records. Pure. */
export function buildCourierDeliveryReport(params: {
  fromIso: string;
  toIso: string;
  collections: readonly ReportCollectionInput[];
  settlements: readonly ReportSettlementInput[];
  orders: ReadonlyMap<string, ReportOrderInput>;
  couriers: ReadonlyMap<string, ReportCourierInput>;
  truncated?: boolean;
}): CourierDeliveryReport {
  const totals = new Accumulator();
  const byKind: Record<CourierKind, Accumulator> = { internal: new Accumulator(), pool: new Accumulator() };
  const perCourier = new Map<string, { name: string; kind: CourierKind; acc: Accumulator }>();
  const poolOrders: PoolOrderRow[] = [];

  const settlementNames = new Map<string, string>();
  for (const s of params.settlements) settlementNames.set(s.courierId, s.courierName);

  const courierEntry = (courierId: string, orderCourierType: string | null) => {
    let entry = perCourier.get(courierId);
    if (!entry) {
      const courier = params.couriers.get(courierId);
      const type = orderCourierType ?? courier?.type ?? "internal";
      entry = {
        name: courier?.displayName || settlementNames.get(courierId) || courierId,
        kind: type === "pool" ? "pool" : "internal",
        acc: new Accumulator(),
      };
      perCourier.set(courierId, entry);
    }
    return entry;
  };

  for (const c of params.collections) {
    const order = params.orders.get(c.orderId);
    const prep = minutesBetween(order?.createdMillis ?? null, order?.readyMillis ?? null);
    const delivery = minutesBetween(order?.dispatchedMillis ?? null, order?.deliveredMillis ?? c.collectedAtMillis);
    const entry = courierEntry(c.courierId, order?.courierType ?? null);
    entry.acc.addCollection(c, prep, delivery);
    byKind[entry.kind].addCollection(c, prep, delivery);
    totals.addCollection(c, prep, delivery);
    if (entry.kind === "pool") {
      poolOrders.push({
        orderId: c.orderId,
        orderNumber: c.orderNumber,
        courierId: c.courierId,
        courierName: entry.name,
        neighborhoodName: order?.neighborhoodName ?? "",
        amountMinorUnits: c.amountMinorUnits,
        paymentMethodId: c.paymentMethodId,
        paymentMethodDisplayName: c.paymentMethodDisplayName,
        collectedAt: new Date(c.collectedAtMillis).toISOString(),
        deliveryMinutes: delivery === null ? null : roundOne(delivery),
      });
    }
  }
  for (const s of params.settlements) {
    const entry = courierEntry(s.courierId, null);
    entry.acc.addSettlement(s);
    byKind[entry.kind].addSettlement(s);
    totals.addSettlement(s);
  }

  const couriers: CourierReportRow[] = [...perCourier.entries()]
    .map(([courierId, e]) => ({ courierId, courierName: e.name, courierKind: e.kind, ...e.acc.build() }))
    .sort((a, b) => (a.courierKind === b.courierKind
      ? b.packageCount - a.packageCount || a.courierName.localeCompare(b.courierName, "tr")
      : a.courierKind === "internal" ? -1 : 1));
  poolOrders.sort((a, b) => a.collectedAt.localeCompare(b.collectedAt));

  return {
    fromIso: params.fromIso,
    toIso: params.toIso,
    totals: totals.build(),
    byKind: { internal: byKind.internal.build(), pool: byKind.pool.build() },
    couriers,
    poolOrders,
    truncated: params.truncated ?? false,
  };
}

function requireString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return raw.trim();
}

/** `[from, to)` as Dates; `to` after `from`, at most [MAX_REPORT_RANGE_DAYS] apart. */
export function parseReportRange(fromRaw: unknown, toRaw: unknown): { from: Date; to: Date } {
  const from = new Date(requireString(fromRaw, "fromIso"));
  const to = new Date(requireString(toRaw, "toIso"));
  if (Number.isNaN(from.getTime()) || Number.isNaN(to.getTime())) {
    throw new HttpsError("invalid-argument", "fromIso and toIso must be ISO 8601 date-times.");
  }
  if (to.getTime() <= from.getTime()) throw new HttpsError("invalid-argument", "toIso must be after fromIso.");
  if (to.getTime() - from.getTime() > MAX_REPORT_RANGE_DAYS * 86400000) {
    throw new HttpsError("invalid-argument", `The range may span at most ${MAX_REPORT_RANGE_DAYS} days.`);
  }
  return { from, to };
}

export const getCourierDeliveryReport = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  const branchId = requireString(data.branchId, "branchId");
  const { from, to } = parseReportRange(data.fromIso, data.toIso);
  await requireStaffPermission(request, organizationId, "viewDeliveryReports");
  await requireBranchAccess(request, organizationId, branchId);

  const db = getFirestore();
  const fromTs = Timestamp.fromDate(from);
  const toTs = Timestamp.fromDate(to);
  const [collectionSnap, settlementSnap] = await Promise.all([
    db.collection(DELIVERY_COLLECTIONS_COLLECTION)
      .where("organizationId", "==", organizationId)
      .where("branchId", "==", branchId)
      .where("collectedAt", ">=", fromTs)
      .where("collectedAt", "<", toTs)
      .orderBy("collectedAt")
      .limit(MAX_REPORT_COLLECTIONS + 1)
      .get(),
    db.collection(COURIER_SETTLEMENTS_COLLECTION)
      .where("organizationId", "==", organizationId)
      .where("branchId", "==", branchId)
      .where("createdAt", ">=", fromTs)
      .where("createdAt", "<", toTs)
      .orderBy("createdAt")
      .limit(MAX_REPORT_COLLECTIONS)
      .get(),
  ]);
  const truncated = collectionSnap.docs.length > MAX_REPORT_COLLECTIONS;
  const collectionDocs = collectionSnap.docs.slice(0, MAX_REPORT_COLLECTIONS);

  const collections: ReportCollectionInput[] = collectionDocs.map((doc) => {
    const c = doc.data();
    const paymentMethodId = String(c.paymentMethodId ?? "");
    return {
      orderId: String(c.orderId ?? ""),
      orderNumber: String(c.orderNumber ?? c.orderId ?? ""),
      courierId: String(c.courierId ?? ""),
      paymentMethodId,
      paymentMethodDisplayName: String(
        c.paymentMethodDisplayName ?? DELIVERY_PAYMENT_METHOD_CATALOG[paymentMethodId]?.displayName ?? paymentMethodId,
      ),
      reportingCategory: String(c.reportingCategory ?? ""),
      amountMinorUnits: Number(c.amountMinorUnits ?? 0),
      collectedAtMillis: toMillis(c.collectedAt) ?? from.getTime(),
    };
  });
  const settlements: ReportSettlementInput[] = settlementSnap.docs.map((doc) => {
    const s = doc.data();
    return {
      courierId: String(s.courierId ?? ""),
      courierName: String(s.courierName ?? ""),
      differenceMinorUnits: Number(s.differenceMinorUnits ?? 0),
    };
  });

  const orders = new Map<string, ReportOrderInput>();
  const orderIds = [...new Set(collections.map((c) => c.orderId).filter((id) => id.length > 0))];
  for (let i = 0; i < orderIds.length; i += 300) {
    const refs = orderIds.slice(i, i + 300).map((id) => db.collection("orders").doc(id));
    for (const snap of await db.getAll(...refs)) {
      if (snap.exists && snap.data()!.organizationId === organizationId) {
        orders.set(snap.id, reportOrderInputFrom(snap.data()!));
      }
    }
  }
  const couriers = new Map<string, ReportCourierInput>();
  const courierIds = [...new Set([...collections.map((c) => c.courierId), ...settlements.map((s) => s.courierId)])]
    .filter((id) => id.length > 0);
  for (let i = 0; i < courierIds.length; i += 300) {
    const refs = courierIds.slice(i, i + 300).map((id) => db.collection("couriers").doc(id));
    for (const snap of await db.getAll(...refs)) {
      if (snap.exists) {
        couriers.set(snap.id, {
          displayName: String(snap.data()!.displayName ?? ""),
          type: String(snap.data()!.type ?? "internal"),
        });
      }
    }
  }

  return buildCourierDeliveryReport({
    fromIso: from.toISOString(),
    toIso: to.toISOString(),
    collections,
    settlements,
    orders,
    couriers,
    truncated,
  });
});
