import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { getFirestore, Timestamp, FieldValue } from "firebase-admin/firestore";
import { requireStaffPermission } from "./staffAuthorization";
import { requirePlatformCapability } from "./platformCapabilities";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { generateCorrelationId, sanitizeClientRequestId } from "./correlationId";
import {
  PLATFORM_CUSTOMER_DIRECTORY_COLLECTION,
  CUSTOMER_DIRECTORY_ENTRIES_COLLECTION,
  TENANT_CUSTOMER_RESTRICTIONS_COLLECTION,
  PLATFORM_CUSTOMER_RESTRICTIONS_COLLECTION,
  phoneSearchHmacSecret,
  normalizeDisplayName,
  normalizePhoneForSearch,
  computePhoneSearchHash,
  type PlatformCustomerDirectoryEntryDoc,
  type CustomerDirectoryEntryDoc,
} from "./customerDirectoryConfig";

/**
 * AP-3 Wave 3 — Customer Directory read APIs and restriction authority
 * (corrected report §4/§5, Stage B refinements #1/#4/#10). Every callable
 * here uses an explicit permission/capability, never a bare role-name
 * check (§F) — tenant reads go through `viewTenantCustomerDirectory`/
 * `manageTenantCustomerRestriction` (`staffAuthorization.ts`), platform
 * reads go through named `PlatformCapability`s (`platformCapabilities.ts`),
 * never `platformRole == 'platformOwner'` inlined directly.
 */

const PAGE_SIZE = 30;

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}
function requireNonEmptyString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.length === 0) invalid(`${field} is required.`);
  return raw as string;
}

/** The one, minimized shape every list/search response returns — never the raw stored document (which carries `phoneNumber`/`phoneSearchHash`, neither ever returned to a client). */
function toListProjection(entry: { displayName: string; registrationDate: Timestamp; accountState: string }, id: string) {
  return {
    id,
    displayName: entry.displayName,
    registrationDate: entry.registrationDate.toDate().toISOString(),
    accountState: entry.accountState,
  };
}

/** Last-2-digit masked phone — the only phone representation any list/detail response ever includes; the full number and the search hash are never returned to any client, logged, or otherwise exposed. */
function maskPhone(phoneNumber: string): string {
  return phoneNumber.length <= 2 ? "**" : `${"*".repeat(phoneNumber.length - 2)}${phoneNumber.slice(-2)}`;
}

// -----------------------------------------------------------------------
// Projection maintenance — order-driven incremental updates
// -----------------------------------------------------------------------

/**
 * Event-driven, idempotent-by-construction (fires on CREATE only, so a
 * given order can only ever increment `totalOrderCount` once) tenant-
 * projection maintenance. Defensive: if the tenant projection doc doesn't
 * exist yet (a real-world impossibility today, since every dine-in/
 * takeaway/delivery order's `customerId` is always an already-registered
 * uid whose `completeCustomerProfile` call already created it — but never
 * assumed), the update is skipped rather than creating a malformed partial
 * entry with `.set({merge:true})`.
 */
export const onOrderCreatedForCustomerDirectory = onDocumentCreated("orders/{orderId}", async (event) => {
  const order = event.data?.data();
  if (!order || !order.customerId || !order.organizationId) return;
  const db = getFirestore();
  const ref = db.collection(CUSTOMER_DIRECTORY_ENTRIES_COLLECTION).doc(`${order.organizationId}_${order.customerId}`);
  const snap = await ref.get();
  if (!snap.exists) return;
  const now = Timestamp.now();
  await ref.update({
    lastActivityAt: now,
    lastOrderAt: now,
    totalOrderCount: FieldValue.increment(1),
    relatedBranchIds: order.branchId ? FieldValue.arrayUnion(order.branchId) : FieldValue.arrayUnion(),
    updatedAt: now,
  });
});

// -----------------------------------------------------------------------
// Platform Owner — global registered-customer directory
// -----------------------------------------------------------------------

export const listPlatformCustomers = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    requirePlatformCapability(request, "customerDirectory.listAllRegistered");
    const data = (request.data ?? {}) as Record<string, unknown>;
    const namePrefix = typeof data.namePrefix === "string" ? normalizeDisplayName(data.namePrefix) : null;
    const cursor = typeof data.cursor === "string" && data.cursor.length > 0 ? data.cursor : null;

    const db = getFirestore();
    let query: FirebaseFirestore.Query = db.collection(PLATFORM_CUSTOMER_DIRECTORY_COLLECTION);
    if (namePrefix) {
      query = query.orderBy("displayNameNormalized").where("displayNameNormalized", ">=", namePrefix).where("displayNameNormalized", "<", namePrefix + "\uF8FF");
    } else {
      query = query.orderBy("registrationDate", "desc");
    }
    query = query.limit(PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);
    const snap = await query.get();

    return {
      customers: snap.docs.map((d) => toListProjection(d.data() as PlatformCustomerDirectoryEntryDoc, d.id)),
      nextCursor: snap.docs.length === PAGE_SIZE ? (namePrefix ? snap.docs[snap.docs.length - 1].data().displayNameNormalized : snap.docs[snap.docs.length - 1].id) : null,
    };
  },
);

export const searchPlatformCustomersByPhone = onCall(
  { enforceAppCheck: shouldEnforceAppCheck(), secrets: [phoneSearchHmacSecret] },
  async (request: CallableRequest) => {
    requirePlatformCapability(request, "customerDirectory.listAllRegistered");
    const data = (request.data ?? {}) as Record<string, unknown>;
    const phoneNumber = requireNonEmptyString(data.phoneNumber, "phoneNumber");
    const hash = computePhoneSearchHash(normalizePhoneForSearch(phoneNumber));

    const db = getFirestore();
    const snap = await db.collection(PLATFORM_CUSTOMER_DIRECTORY_COLLECTION).where("phoneSearchHash", "==", hash).limit(5).get();
    return { customers: snap.docs.map((d) => toListProjection(d.data() as PlatformCustomerDirectoryEntryDoc, d.id)) };
  },
);

export const getPlatformCustomerDetail = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    requirePlatformCapability(request, "customerDirectory.listAllRegistered");
    const data = (request.data ?? {}) as Record<string, unknown>;
    const uid = requireNonEmptyString(data.uid, "uid");

    const db = getFirestore();
    const snap = await db.collection(PLATFORM_CUSTOMER_DIRECTORY_COLLECTION).doc(uid).get();
    if (!snap.exists) throw new HttpsError("not-found", "Customer not found.");
    const entry = snap.data() as PlatformCustomerDirectoryEntryDoc;

    const restrictionSnap = await db.collection(PLATFORM_CUSTOMER_RESTRICTIONS_COLLECTION).doc(uid).get();
    const tenantMembershipsSnap = await db.collection("tenantCustomers").where("uid", "==", uid).get();

    return {
      uid,
      displayName: entry.displayName,
      phoneMasked: maskPhone(entry.phoneNumber),
      registrationDate: entry.registrationDate.toDate().toISOString(),
      accountState: entry.accountState,
      relatedOrganizationIds: tenantMembershipsSnap.docs.map((d) => d.data().organizationId as string),
      platformRestriction: restrictionSnap.exists ? restrictionSnap.data() : { status: "none" },
      // Consent is never a global boolean — displayed honestly, always
      // `notCaptured` this phase (corrected report §6, no capture UI
      // exists yet; a real per-purpose/channel record is AP-7 scope).
      marketingConsent: "notCaptured",
    };
  },
);

/** Platform-capability-gated, mandatory reason, always audited — the ONLY path to a customer's full saved address book (corrected report §5). */
export const revealCustomerFullAddressBook = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    requirePlatformCapability(request, "customerDirectory.revealFullAddressBook");
    const data = (request.data ?? {}) as Record<string, unknown>;
    const uid = requireNonEmptyString(data.uid, "uid");
    const reason = requireNonEmptyString(data.reason, "reason");

    const db = getFirestore();
    const addressesSnap = await db.collection("customerAddresses").where("customerId", "==", uid).get();
    const now = Timestamp.now();

    await db.collection("auditEvents").add({
      organizationId: null, branchId: null, type: "customerDirectory.fullAddressBookRevealed",
      targetRef: `customers/${uid}`, previousValue: null, newValue: { addressCount: addressesSnap.size },
      actor: "platform", actorType: "platform", actorUid: request.auth!.uid, actorRoles: null,
      reasonCode: null, reasonMessage: reason,
      correlationId: generateCorrelationId(), clientRequestId: sanitizeClientRequestId(data.clientRequestId),
      timestamp: now.toDate().toISOString(),
    });

    return { addresses: addressesSnap.docs.map((d) => ({ id: d.id, ...d.data() })) };
  },
);

export const setPlatformCustomerRestriction = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    requirePlatformCapability(request, "customerDirectory.globalRestriction");
    const data = (request.data ?? {}) as Record<string, unknown>;
    const uid = requireNonEmptyString(data.uid, "uid");
    const status = data.status === "active" ? "active" : data.status === "none" ? "none" : invalid('status must be "active" or "none".');
    const reasonCode = requireNonEmptyString(data.reasonCode, "reasonCode");
    const reasonMessage = requireNonEmptyString(data.reasonMessage, "reasonMessage");
    const expiresAt = typeof data.expiresAtIso === "string" ? Timestamp.fromDate(new Date(data.expiresAtIso)) : null;

    const db = getFirestore();
    const now = Timestamp.now();
    await db.collection(PLATFORM_CUSTOMER_RESTRICTIONS_COLLECTION).doc(uid).set({
      uid, status, reasonCode, reasonMessage, expiresAt, actorUid: request.auth!.uid, createdAt: now, version: 1,
    }, { merge: true });
    return { uid, status };
  },
);

// -----------------------------------------------------------------------
// Tenant Admin / branch staff — organization-scoped directory
// -----------------------------------------------------------------------

export const listTenantCustomers = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    requireStaffPermission(request, organizationId, "viewTenantCustomerDirectory");
    const namePrefix = typeof data.namePrefix === "string" ? normalizeDisplayName(data.namePrefix) : null;
    const cursor = typeof data.cursor === "string" && data.cursor.length > 0 ? data.cursor : null;

    const db = getFirestore();
    let query: FirebaseFirestore.Query = db.collection(CUSTOMER_DIRECTORY_ENTRIES_COLLECTION).where("organizationId", "==", organizationId);
    if (namePrefix) {
      query = query.orderBy("displayNameNormalized").where("displayNameNormalized", ">=", namePrefix).where("displayNameNormalized", "<", namePrefix + "\uF8FF");
    } else {
      query = query.orderBy("lastActivityAt", "desc");
    }
    query = query.limit(PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);
    const snap = await query.get();

    return {
      customers: snap.docs.map((d) => {
        const entry = d.data() as CustomerDirectoryEntryDoc;
        return {
          id: entry.customerId,
          displayName: entry.displayName,
          registrationDate: entry.registrationDate.toDate().toISOString(),
          lastActivityAt: entry.lastActivityAt.toDate().toISOString(),
          accountState: entry.accountState,
          relatedBranchIds: entry.relatedBranchIds,
          lastOrderAt: entry.lastOrderAt ? entry.lastOrderAt.toDate().toISOString() : null,
          totalOrderCount: entry.totalOrderCount,
        };
      }),
      nextCursor: snap.docs.length === PAGE_SIZE ? (namePrefix ? snap.docs[snap.docs.length - 1].data().displayNameNormalized : snap.docs[snap.docs.length - 1].id) : null,
    };
  },
);

export const searchCustomersForPos = onCall(
  { enforceAppCheck: shouldEnforceAppCheck(), secrets: [phoneSearchHmacSecret] },
  async (request: CallableRequest) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    requireStaffPermission(request, organizationId, "viewTenantCustomerDirectory");
    const phoneNumber = typeof data.phoneNumber === "string" && data.phoneNumber.length > 0 ? data.phoneNumber : null;
    const namePrefix = typeof data.namePrefix === "string" && data.namePrefix.length > 0 ? normalizeDisplayName(data.namePrefix) : null;
    if (!phoneNumber && !namePrefix) invalid("Either phoneNumber or namePrefix is required.");

    const db = getFirestore();
    let query: FirebaseFirestore.Query = db.collection(CUSTOMER_DIRECTORY_ENTRIES_COLLECTION).where("organizationId", "==", organizationId);
    if (phoneNumber) {
      query = query.where("phoneSearchHash", "==", computePhoneSearchHash(normalizePhoneForSearch(phoneNumber)));
    } else {
      query = query.orderBy("displayNameNormalized").where("displayNameNormalized", ">=", namePrefix!).where("displayNameNormalized", "<", namePrefix + "\uF8FF");
    }
    const snap = await query.limit(10).get();
    return {
      customers: snap.docs.map((d) => {
        const entry = d.data() as CustomerDirectoryEntryDoc;
        return { id: entry.customerId, displayName: entry.displayName, phoneMasked: maskPhone(entry.phoneNumber) };
      }),
    };
  },
);

export const getTenantCustomerDetail = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const customerId = requireNonEmptyString(data.customerId, "customerId");
    requireStaffPermission(request, organizationId, "viewTenantCustomerDirectory");

    const db = getFirestore();
    const entrySnap = await db.collection(CUSTOMER_DIRECTORY_ENTRIES_COLLECTION).doc(`${organizationId}_${customerId}`).get();
    if (!entrySnap.exists) throw new HttpsError("not-found", "Customer not found for this organization.");
    const entry = entrySnap.data() as CustomerDirectoryEntryDoc;

    // Address visibility — ONLY this organization's own past delivery
    // orders for this customer, NEVER `customerAddresses` directly
    // (corrected report §5 — the address-privacy fix). Bounded, recent-
    // first, deduplicated by the snapshot's own serialized shape.
    const ordersSnap = await db.collection("orders")
      .where("organizationId", "==", organizationId)
      .where("customerId", "==", customerId)
      .orderBy("timestamps.created", "desc")
      .limit(20)
      .get();
    const seen = new Set<string>();
    const addressSnapshots: unknown[] = [];
    for (const doc of ordersSnap.docs) {
      const snapshot = doc.data().deliveryAddressSnapshot;
      if (!snapshot) continue;
      const key = JSON.stringify(snapshot);
      if (seen.has(key)) continue;
      seen.add(key);
      addressSnapshots.push(snapshot);
    }

    const restrictionSnap = await db.collection(TENANT_CUSTOMER_RESTRICTIONS_COLLECTION).doc(`${organizationId}_${customerId}`).get();

    return {
      id: customerId,
      displayName: entry.displayName,
      phoneMasked: maskPhone(entry.phoneNumber),
      registrationDate: entry.registrationDate.toDate().toISOString(),
      lastActivityAt: entry.lastActivityAt.toDate().toISOString(),
      accountState: entry.accountState,
      relatedBranchIds: entry.relatedBranchIds,
      lastOrderAt: entry.lastOrderAt ? entry.lastOrderAt.toDate().toISOString() : null,
      totalOrderCount: entry.totalOrderCount,
      orderAddressSnapshots: addressSnapshots,
      tenantRestriction: restrictionSnap.exists ? restrictionSnap.data() : { status: "none" },
      marketingConsent: "notCaptured",
    };
  },
);

/** Manager+ (`manageTenantCustomerRestriction`) — tenant-scoped only, NEVER writes `customers/{uid}` (the canonical global record). */
export const setTenantCustomerRestriction = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const customerId = requireNonEmptyString(data.customerId, "customerId");
    requireStaffPermission(request, organizationId, "manageTenantCustomerRestriction");
    const status = data.status === "active" ? "active" : data.status === "none" ? "none" : invalid('status must be "active" or "none".');
    const reasonCode = requireNonEmptyString(data.reasonCode, "reasonCode");
    const reasonMessage = requireNonEmptyString(data.reasonMessage, "reasonMessage");
    const expiresAt = typeof data.expiresAtIso === "string" ? Timestamp.fromDate(new Date(data.expiresAtIso)) : null;

    const db = getFirestore();
    const now = Timestamp.now();
    await db.collection(TENANT_CUSTOMER_RESTRICTIONS_COLLECTION).doc(`${organizationId}_${customerId}`).set({
      organizationId, customerId, status, reasonCode, reasonMessage, expiresAt, actorUid: request.auth!.uid, createdAt: now, version: 1,
    }, { merge: true });
    return { organizationId, customerId, status };
  },
);

