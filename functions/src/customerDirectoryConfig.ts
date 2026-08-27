import { createHmac } from "crypto";
import { HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import type { Timestamp } from "firebase-admin/firestore";

/**
 * AP-3 Wave 3 — Customer Directory domain contracts (corrected AP-3 Stage A
 * report §7, Stage B refinements #1/#2). No Firestore I/O beyond the pure
 * normalization/hash helpers lives here — mirrors `tableSessionConfig.ts`'s
 * own "policy/vocabulary only" shape.
 *
 * **Two structurally separate projections** (Stage B refinement #1):
 * `customerDirectoryEntries` (tenant-scoped relationship projection —
 * one entry per `(organizationId, uid)` pair, created only from a verified
 * tenant interaction) cannot answer "every registered customer" — it
 * duplicates a multi-tenant customer once per tenant and excludes a
 * registered customer with no tenant relationship at all.
 * `platformCustomerDirectoryEntries` (exactly one entry per registered
 * customer, `completeCustomerProfile` populates it immediately, no
 * org relationship invented) is the ONLY correct source for the Platform
 * Owner's global list.
 *
 * **Phone search is never a plain normalized duplicate** (Stage B
 * refinement #2) — `phoneSearchHash` is an HMAC-SHA256 of the normalized
 * phone number under a server-only secret (`defineSecret`, Firebase
 * Functions v2's real secret-binding mechanism — never a bare
 * `process.env` read of un-managed config). Missing/too-short
 * configuration fails closed (`computePhoneSearchHash` throws), never
 * silently falls back to an unkeyed hash. The raw normalized phone number
 * itself is never stored as a second, unkeyed search field.
 */

export const PLATFORM_CUSTOMER_DIRECTORY_COLLECTION = "platformCustomerDirectoryEntries";
export const CUSTOMER_DIRECTORY_ENTRIES_COLLECTION = "customerDirectoryEntries";
export const TENANT_CUSTOMER_RESTRICTIONS_COLLECTION = "tenantCustomerRestrictions";
export const PLATFORM_CUSTOMER_RESTRICTIONS_COLLECTION = "platformCustomerRestrictions";

export const phoneSearchHmacSecret = defineSecret("CUSTOMER_PHONE_SEARCH_HMAC_SECRET");

export function normalizeDisplayName(raw: string): string {
  return raw
    .toLocaleLowerCase("tr")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .trim();
}

/** E.164-ish digits-only normalization — never stored raw as a second search field, only ever fed into `computePhoneSearchHash`. */
export function normalizePhoneForSearch(raw: string): string {
  return raw.replace(/[^\d+]/g, "");
}

/**
 * Fails closed (`failed-precondition`) if the secret is missing or
 * implausibly short — never silently computes an unkeyed/weak hash. The
 * emulator/test environment injects a real, non-production value via
 * `functions/.env.local` (gitignored, never committed) — this function
 * itself has no emulator-specific branch; the SAME code path validates
 * both environments identically.
 */
export function computePhoneSearchHash(normalizedPhone: string): string {
  const secret = phoneSearchHmacSecret.value();
  if (!secret || secret.length < 16) {
    throw new HttpsError("failed-precondition", "Phone search is not configured in this environment.");
  }
  return createHmac("sha256", secret).update(normalizedPhone).digest("hex");
}

export interface PlatformCustomerDirectoryEntryDoc {
  uid: string;
  displayName: string;
  displayNameNormalized: string;
  /** Internal only — never returned by any read API to any client, redacted per the PII authority matrix at response time. */
  phoneNumber: string;
  phoneSearchHash: string;
  registrationDate: Timestamp;
  accountState: "active" | "restricted";
  updatedAt: Timestamp;
  version: number;
}

export interface CustomerDirectoryEntryDoc {
  organizationId: string;
  customerId: string;
  displayName: string;
  displayNameNormalized: string;
  phoneNumber: string;
  phoneSearchHash: string;
  registrationDate: Timestamp;
  lastActivityAt: Timestamp;
  accountState: "active" | "restricted";
  relatedBranchIds: string[];
  lastOrderAt: Timestamp | null;
  totalOrderCount: number;
  updatedAt: Timestamp;
  version: number;
}

export interface TenantCustomerRestrictionDoc {
  organizationId: string;
  customerId: string;
  status: "active" | "none";
  reasonCode: string;
  reasonMessage: string;
  expiresAt: Timestamp | null;
  actorUid: string;
  createdAt: Timestamp;
  version: number;
}

export interface PlatformCustomerRestrictionDoc {
  uid: string;
  status: "active" | "none";
  reasonCode: string;
  reasonMessage: string;
  expiresAt: Timestamp | null;
  actorUid: string;
  createdAt: Timestamp;
  version: number;
}
