import { createHash } from "crypto";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp, type DocumentData, type DocumentSnapshot } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission } from "./staffAuthorization";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId } from "./correlationId";
import { POS_CUSTOMERS_COLLECTION, type PosCustomerDoc } from "./posCustomerBook";
import { DELIVERY_POOL_LISTINGS_COLLECTION } from "./courierPool";

/**
 * 2026-11-12 (Faz 4, ADR-082) — KVKK erasure on the customer's request:
 * the organization's local customer-book record (`posCustomers`) is
 * permanently deleted and the personal data of that customer's
 * shop-entered orders is anonymized.
 *
 * Scope ("which orders are this customer's"):
 * - orders that point at the record (`posCustomerId`), and
 * - orders of the same organization with the same `contactPhone` that are
 *   NOT an app customer's (`customerId == null`: POS phone/counter orders).
 *   An app customer's own orders belong to their app account and are erased
 *   by the account-deletion flow (`processAccountDeletion.ts`), never here.
 *
 * What is anonymized on each order: name → "Silinmiş Müşteri", phone →
 * `null`, courier note and line customer notes → "", and the open address
 * (label, street, building/apartment/floor, directions, coordinates, place
 * id, saved-address link) → blank. The neighborhood NAME is kept: it is an
 * area, not a person, and the delivery reports and pool history group by
 * it. Amounts, items, timings and audit trails are kept (financial and tax
 * records). A pool listing of such an order loses its address line.
 *
 * Refused while the customer has an order still in progress
 * (`posCustomer/active-orders`) — erasing the address of a package on the
 * road would strand the courier; the order is finished or cancelled first.
 *
 * `erasePosCustomerData` (manager and above). Audited without personal
 * data: the audit event and the `posCustomerErasures` record carry only
 * the erasure id, the count and the optional request reference (e.g. the
 * petition number). Re-running after a partial failure is safe (the record
 * is deleted last); running it again after success is `not-found`.
 */

export const POS_CUSTOMER_ERASURES_COLLECTION = "posCustomerErasures";
export const ERASED_CUSTOMER_NAME = "Silinmiş Müşteri";
const MAX_REQUEST_REFERENCE_LENGTH = 64;
const BATCH_SIZE = 200;

/** Statuses after which an order is finished (no courier still needs the address). */
export const ERASABLE_ORDER_STATUSES: ReadonlySet<string> = new Set([
  "completed",
  "cancelled",
  "rejected",
  "refunded",
  "served",
]);

/** The fields to write to anonymize [order]'s personal data. Pure. */
export function anonymizedOrderFields(order: DocumentData, erasureId: string, now: Timestamp): Record<string, unknown> {
  const address = order.deliveryAddressSnapshot as DocumentData | null | undefined;
  const lines = Array.isArray(order.lines) ? (order.lines as DocumentData[]) : null;
  return {
    contactFirstName: ERASED_CUSTOMER_NAME,
    contactLastName: "",
    contactPhone: null,
    customerNote: "",
    posCustomerId: null,
    ...(lines ? { lines: lines.map((line) => ({ ...line, customerNote: "" })) } : {}),
    ...(address
      ? {
        deliveryAddressSnapshot: {
          ...address,
          savedAddressId: null,
          label: "",
          streetId: null,
          streetName: "",
          buildingNo: null,
          buildingNoSource: null,
          apartmentNo: "",
          floor: null,
          addressDescription: null,
          latitude: null,
          longitude: null,
          providerPlaceId: null,
        },
      }
      : {}),
    personalDataErasure: { erasureId, erasedAt: now },
  };
}

function sanitizeRequestReference(raw: unknown): string | null {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== "string") throw new HttpsError("invalid-argument", "requestReference must be a string.");
  const trimmed = raw.trim();
  if (trimmed.length === 0) return null;
  if (trimmed.length > MAX_REQUEST_REFERENCE_LENGTH) {
    throw new HttpsError("invalid-argument", `requestReference must be at most ${MAX_REQUEST_REFERENCE_LENGTH} characters.`);
  }
  return trimmed;
}

export const erasePosCustomer = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = typeof data.organizationId === "string" ? data.organizationId.trim() : "";
  const posCustomerId = typeof data.posCustomerId === "string" ? data.posCustomerId.trim() : "";
  if (organizationId.length === 0) throw new HttpsError("invalid-argument", "organizationId is required.");
  if (posCustomerId.length === 0) throw new HttpsError("invalid-argument", "posCustomerId is required.");
  const requestReference = sanitizeRequestReference(data.requestReference);
  await requireStaffPermission(request, organizationId, "erasePosCustomerData");

  const db = getFirestore();
  const uid = request.auth.uid;
  const customerRef = db.collection(POS_CUSTOMERS_COLLECTION).doc(posCustomerId);
  const customerSnap = await customerRef.get();
  if (!customerSnap.exists || customerSnap.data()!.organizationId !== organizationId) {
    throw new HttpsError("not-found", "No such customer record.", { code: "posCustomer/not-found" });
  }
  const customer = customerSnap.data() as PosCustomerDoc;

  const [byRecord, byPhone] = await Promise.all([
    db.collection("orders")
      .where("organizationId", "==", organizationId)
      .where("posCustomerId", "==", posCustomerId)
      .get(),
    customer.phoneNumber
      ? db.collection("orders")
        .where("organizationId", "==", organizationId)
        .where("contactPhone", "==", customer.phoneNumber)
        .where("customerId", "==", null)
        .get()
      : Promise.resolve(null),
  ]);
  const orders = new Map<string, DocumentSnapshot>();
  for (const doc of [...byRecord.docs, ...(byPhone?.docs ?? [])]) orders.set(doc.id, doc);

  const active = [...orders.values()].filter((doc) => !ERASABLE_ORDER_STATUSES.has(String(doc.data()!.status)));
  if (active.length > 0) {
    throw new HttpsError("failed-precondition", "The customer has orders still in progress.", {
      code: "posCustomer/active-orders",
      activeOrderCount: active.length,
    });
  }

  const now = Timestamp.now();
  const erasureId = `erasure-${createHash("sha256").update(`${posCustomerId}|${uid}|${now.toMillis()}`).digest("hex").slice(0, 32)}`;
  const orderDocs = [...orders.values()];
  for (let i = 0; i < orderDocs.length; i += BATCH_SIZE) {
    const chunk = orderDocs.slice(i, i + BATCH_SIZE);
    const listings = await db.getAll(...chunk.map((doc) => db.collection(DELIVERY_POOL_LISTINGS_COLLECTION).doc(doc.id)));
    const batch = db.batch();
    for (const doc of chunk) batch.update(doc.ref, anonymizedOrderFields(doc.data()!, erasureId, now));
    for (const listing of listings) {
      if (listing.exists) batch.update(listing.ref, { addressLine: "", updatedAt: now });
    }
    await batch.commit();
  }

  await db.runTransaction(async (tx) => {
    const fresh = await tx.get(customerRef);
    if (fresh.exists) tx.delete(customerRef);
    const erasureRef = db.collection(POS_CUSTOMER_ERASURES_COLLECTION).doc(erasureId);
    const record = {
      organizationId,
      erasedAt: now,
      erasedByUid: uid,
      anonymizedOrderCount: orderDocs.length,
      requestReference,
    };
    tx.set(erasureRef, record);
    const roles = (request.auth!.token.roles as Record<string, unknown> | undefined)?.[organizationId];
    writeAuditEvent({
      tx, db, eventId: `posCustomer-${erasureId}`, organizationId, branchId: null,
      type: "posCustomer.erased", targetRef: erasureRef.path,
      newValue: { erasureId, anonymizedOrderCount: orderDocs.length, requestReference },
      actorType: "staff", actorUid: uid, actorRoles: Array.isArray(roles) ? (roles as string[]) : null,
      reasonCode: "kvkkErasureRequest",
      correlationId: generateCorrelationId(), now,
    });
  });

  return { erasureId, anonymizedOrderCount: orderDocs.length };
});
