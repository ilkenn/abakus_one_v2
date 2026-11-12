import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp, type DocumentSnapshot, type Firestore, type Transaction } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission } from "./staffAuthorization";
import {
  CUSTOMER_DIRECTORY_ENTRIES_COLLECTION,
  computePhoneSearchHash,
  normalizeDisplayName,
  normalizePhoneForSearch,
  phoneSearchHmacSecret,
  type CustomerDirectoryEntryDoc,
} from "./customerDirectoryConfig";

/**
 * 2026-11-11 — the organization's own local customer book (product owner,
 * Faz 2 decision 2): phone / counter orders remember the customer's name,
 * FULL phone number and recent delivery addresses, so the next call fills
 * them in instead of the cashier asking again. Tenant-scoped, keyed by
 * (organization, HMAC of the E.164 phone) — one record per phone number per
 * organization, never shared across tenants. Server-only: no client rule
 * grants any read or write (`firestore.rules`' catch-all deny); the POS
 * reads it through [searchPosCustomers] and every staff delivery order
 * upserts it ([preparePosCustomerUpsert]). Deleting a record on request
 * (KVKK) is deferred by product-owner decision.
 */
export const POS_CUSTOMERS_COLLECTION = "posCustomers";

/** At most this many addresses are remembered, most recently used first. */
export const MAX_REMEMBERED_ADDRESSES = 5;

export interface PosCustomerAddress {
  label: string;
  neighborhoodName: string;
  streetName: string;
  buildingNo: string;
  apartmentNo: string;
  floor: string;
  addressDescription: string;
  lastUsedAt: string;
}

export interface PosCustomerDoc {
  organizationId: string;
  firstName: string;
  lastName: string;
  displayName: string;
  displayNameNormalized: string;
  /** E.164, e.g. "+905321112233". */
  phoneNumber: string;
  phoneSearchHash: string;
  addresses: PosCustomerAddress[];
  /** The app customer this phone belongs to, when staff picked one. */
  linkedCustomerId: string | null;
  orderCount: number;
  lastOrderAt: Timestamp;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/**
 * A Turkish phone number in E.164 (`+90` + 10 digits, first digit 2–5:
 * landline or mobile), or `null` when it is not one. Accepts the shapes
 * cashiers type: "0532 111 22 33", "5321112233", "+90 532 111 22 33".
 */
export function normalizeTurkishPhone(raw: string): string | null {
  const digits = raw.replace(/\D/g, "");
  let national: string;
  if (digits.length === 12 && digits.startsWith("90")) national = digits.slice(2);
  else if (digits.length === 11 && digits.startsWith("0")) national = digits.slice(1);
  else if (digits.length === 10) national = digits;
  else return null;
  return /^[2-5]\d{9}$/.test(national) ? `+90${national}` : null;
}

export function posCustomerDocId(organizationId: string, phoneSearchHash: string): string {
  return `${organizationId}_${phoneSearchHash}`;
}

function addressKey(address: Omit<PosCustomerAddress, "lastUsedAt" | "label">): string {
  return [address.neighborhoodName, address.streetName, address.buildingNo, address.apartmentNo, address.floor]
    .map((part) => normalizeDisplayName(part))
    .join("|");
}

/**
 * The address list after [used] was used now: moved (or added) to the front,
 * duplicates of the same place collapsed, capped at [MAX_REMEMBERED_ADDRESSES].
 * Pure.
 */
export function rememberAddress(
  existing: readonly PosCustomerAddress[],
  used: PosCustomerAddress,
): PosCustomerAddress[] {
  const key = addressKey(used);
  return [used, ...existing.filter((address) => addressKey(address) !== key)].slice(
    0,
    MAX_REMEMBERED_ADDRESSES,
  );
}

export interface PosCustomerUpsertPlan {
  ref: FirebaseFirestore.DocumentReference;
  data: PosCustomerDoc;
}

/**
 * Read phase (must run before the enclosing transaction's first write):
 * loads the book record for this phone and returns the record as it must
 * be written for this order. [address] is `null` for a Gel-Al order (name
 * and phone only).
 */
export async function preparePosCustomerUpsert(params: {
  tx: Transaction;
  db: Firestore;
  organizationId: string;
  phoneNumber: string;
  firstName: string;
  lastName: string;
  address: Omit<PosCustomerAddress, "lastUsedAt"> | null;
  linkedCustomerId: string | null;
  now: Timestamp;
}): Promise<PosCustomerUpsertPlan> {
  const phoneSearchHash = computePhoneSearchHash(params.phoneNumber);
  const ref = params.db.collection(POS_CUSTOMERS_COLLECTION).doc(posCustomerDocId(params.organizationId, phoneSearchHash));
  const snap: DocumentSnapshot = await params.tx.get(ref);
  const existing = snap.exists ? (snap.data() as PosCustomerDoc) : null;
  const displayName = `${params.firstName} ${params.lastName}`.trim();
  const addresses = params.address
    ? rememberAddress(existing?.addresses ?? [], { ...params.address, lastUsedAt: params.now.toDate().toISOString() })
    : existing?.addresses ?? [];
  return {
    ref,
    data: {
      organizationId: params.organizationId,
      firstName: params.firstName,
      lastName: params.lastName,
      displayName,
      displayNameNormalized: normalizeDisplayName(displayName),
      phoneNumber: params.phoneNumber,
      phoneSearchHash,
      addresses,
      linkedCustomerId: params.linkedCustomerId ?? existing?.linkedCustomerId ?? null,
      orderCount: (existing?.orderCount ?? 0) + 1,
      lastOrderAt: params.now,
      createdAt: existing?.createdAt ?? params.now,
      updatedAt: params.now,
    },
  };
}

export function applyPosCustomerUpsert(tx: Transaction, plan: PosCustomerUpsertPlan): void {
  tx.set(plan.ref, plan.data);
}

/** The wire shape the POS search returns. */
interface PosCustomerSearchResult {
  source: "book" | "directory";
  id: string;
  displayName: string;
  firstName: string;
  lastName: string;
  /** Full E.164 number for a book record; `null` for an app customer. */
  phoneNumber: string | null;
  phoneMasked: string;
  addresses: PosCustomerAddress[];
  linkedCustomerId: string | null;
}

function maskPhone(phoneNumber: string): string {
  return phoneNumber.length <= 2 ? "**" : `${"*".repeat(phoneNumber.length - 2)}${phoneNumber.slice(-2)}`;
}

function splitName(displayName: string): { firstName: string; lastName: string } {
  const parts = displayName.trim().split(/\s+/);
  return { firstName: parts[0] ?? "", lastName: parts.slice(1).join(" ") };
}

function bookResult(id: string, doc: PosCustomerDoc): PosCustomerSearchResult {
  return {
    source: "book",
    id,
    displayName: doc.displayName,
    firstName: doc.firstName,
    lastName: doc.lastName,
    phoneNumber: doc.phoneNumber,
    phoneMasked: maskPhone(doc.phoneNumber),
    addresses: doc.addresses ?? [],
    linkedCustomerId: doc.linkedCustomerId ?? null,
  };
}

const PHONE_LIKE = /^[+\d][\d\s()-]*$/;

/**
 * "Müşteri Ara (İsim veya Tel)" — the local book first (full phone and
 * remembered addresses), then the organization's app-customer directory
 * (masked phone, as before; included only when the caller may view that
 * directory). A phone query matches exactly (HMAC of the E.164 number); a
 * name query is a prefix match on the normalized display name. At most 10
 * of each.
 */
export const searchPosCustomers = onCall(
  { enforceAppCheck: shouldEnforceAppCheck(), secrets: [phoneSearchHmacSecret] },
  async (request: CallableRequest) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = typeof data.organizationId === "string" ? data.organizationId : "";
    if (organizationId.length === 0) throw new HttpsError("invalid-argument", "organizationId is required.");
    const query = typeof data.query === "string" ? data.query.trim() : "";
    if (query.length < 2) throw new HttpsError("invalid-argument", "query must be at least 2 characters.");
    await requireStaffPermission(request, organizationId, "manageDeliveryOrders");

    let mayViewDirectory = true;
    try {
      await requireStaffPermission(request, organizationId, "viewTenantCustomerDirectory");
    } catch {
      mayViewDirectory = false;
    }

    const db = getFirestore();
    const results: PosCustomerSearchResult[] = [];
    const linkedIds = new Set<string>();

    if (PHONE_LIKE.test(query)) {
      const phoneNumber = normalizeTurkishPhone(query);
      if (phoneNumber) {
        const hash = computePhoneSearchHash(phoneNumber);
        const snap = await db.collection(POS_CUSTOMERS_COLLECTION).doc(posCustomerDocId(organizationId, hash)).get();
        if (snap.exists) {
          const doc = snap.data() as PosCustomerDoc;
          results.push(bookResult(snap.id, doc));
          if (doc.linkedCustomerId) linkedIds.add(doc.linkedCustomerId);
        }
        if (mayViewDirectory) {
          const hashes = [...new Set([hash, computePhoneSearchHash(normalizePhoneForSearch(query))])];
          for (const directoryHash of hashes) {
            const directorySnap = await db.collection(CUSTOMER_DIRECTORY_ENTRIES_COLLECTION)
              .where("organizationId", "==", organizationId)
              .where("phoneSearchHash", "==", directoryHash)
              .limit(10)
              .get();
            for (const entryDoc of directorySnap.docs) {
              const entry = entryDoc.data() as CustomerDirectoryEntryDoc;
              if (linkedIds.has(entry.customerId)) continue;
              linkedIds.add(entry.customerId);
              results.push({
                source: "directory",
                id: entry.customerId,
                displayName: entry.displayName,
                ...splitName(entry.displayName),
                phoneNumber: null,
                phoneMasked: maskPhone(entry.phoneNumber),
                addresses: [],
                linkedCustomerId: entry.customerId,
              });
            }
          }
        }
      }
      return { customers: results };
    }

    const prefix = normalizeDisplayName(query);
    const bookSnap = await db.collection(POS_CUSTOMERS_COLLECTION)
      .where("organizationId", "==", organizationId)
      .orderBy("displayNameNormalized")
      .where("displayNameNormalized", ">=", prefix)
      .where("displayNameNormalized", "<", prefix + "")
      .limit(10)
      .get();
    for (const doc of bookSnap.docs) {
      const book = doc.data() as PosCustomerDoc;
      results.push(bookResult(doc.id, book));
      if (book.linkedCustomerId) linkedIds.add(book.linkedCustomerId);
    }
    if (mayViewDirectory) {
      const directorySnap = await db.collection(CUSTOMER_DIRECTORY_ENTRIES_COLLECTION)
        .where("organizationId", "==", organizationId)
        .orderBy("displayNameNormalized")
        .where("displayNameNormalized", ">=", prefix)
        .where("displayNameNormalized", "<", prefix + "")
        .limit(10)
        .get();
      for (const entryDoc of directorySnap.docs) {
        const entry = entryDoc.data() as CustomerDirectoryEntryDoc;
        if (linkedIds.has(entry.customerId)) continue;
        results.push({
          source: "directory",
          id: entry.customerId,
          displayName: entry.displayName,
          ...splitName(entry.displayName),
          phoneNumber: null,
          phoneMasked: maskPhone(entry.phoneNumber),
          addresses: [],
          linkedCustomerId: entry.customerId,
        });
      }
    }
    return { customers: results };
  },
);
