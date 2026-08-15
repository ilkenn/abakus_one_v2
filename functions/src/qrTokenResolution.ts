import { getFirestore } from "firebase-admin/firestore";
import { epochMinuteOf } from "./reservationTableProtection";

/**
 * Server-side mirror of `TableQrValidityStatus`
 * (`lib/features/qr/domain/models/table_qr_resolution.dart`) — Table Guest
 * Session Phase 1/2. Kept as a hand-mirrored duplication for the same
 * reason `orderStatus.ts` mirrors the Dart order-status table: no
 * Dart<->TypeScript code-sharing mechanism exists in this repository.
 *
 * **`reserved`, Faz R.1C.2** — a table currently protected by an active
 * reservation's T-20 window (`tableProtectionMinuteBuckets`, Faz R.1C.1).
 * Deliberately a distinct value from `invalid` (which already meant "this
 * code is real but the table isn't accepting a new session right now" for
 * an unrelated reason — `table.status !== 'available'`): the customer-
 * facing message is different ("bu masa rezerve edilmiştir," never a
 * generic "invalid code" message), so the status itself must be
 * distinguishable, not inferred from context.
 */
export type TableQrValidityStatus = "valid" | "invalid" | "expired" | "notFound" | "reserved";

/** Mirrors `TableQrStatus` (`lib/features/qr/domain/models/table_qr_code.dart`) — centralized so no call site compares against a bare string literal. */
export type TableQrCodeStatus = "active" | "inactive" | "rotated" | "expired";
export const TABLE_QR_CODE_STATUS: Record<TableQrCodeStatus, TableQrCodeStatus> = {
  active: "active",
  inactive: "inactive",
  rotated: "rotated",
  expired: "expired",
};

/** Mirrors `TableStatus` (`lib/features/qr/domain/models/restaurant_table.dart`) — centralized for the same reason as [TABLE_QR_CODE_STATUS]. */
export type RestaurantTableStatus =
  | "available"
  | "occupied"
  | "reserved"
  | "cleaning"
  | "disabled";
export const RESTAURANT_TABLE_STATUS: Record<
  RestaurantTableStatus,
  RestaurantTableStatus
> = {
  available: "available",
  occupied: "occupied",
  reserved: "reserved",
  cleaning: "cleaning",
  disabled: "disabled",
};

/**
 * The full internal resolution — organization/restaurant/branch/table
 * identity included. Used server-side only (by `openTableGuestSession`,
 * which needs these ids to write a scoped `tableGuestSessions` document)
 * — **never returned to a client directly**. See [TableQrPublicPreview]
 * for the one shape a client (through the public `resolveTableQrToken`
 * call) is ever allowed to see.
 */
export interface TableQrResolution {
  validityStatus: TableQrValidityStatus;
  organizationId?: string;
  restaurantId?: string;
  branchId?: string;
  tableId?: string;
  tableDisplayName?: string;
  branchDisplayName?: string;
  /** The resolved `tableQrCodes` document id — audit use only (e.g. stamped onto a `tableGuestSessions` record), never returned to the client. */
  qrCodeId?: string;
}

/**
 * The minimized, public-safe shape `resolveTableQrToken` (unauthenticated,
 * callable from a bare QR scan before any session exists) actually
 * returns. Deliberately excludes `organizationId`/`restaurantId`/
 * `branchId`/`tableId`: nothing in the QR-scan preview UI (confirm-the-
 * table screen, "Masa 12 · Abaküs Ortaköy, devam et?") needs a raw
 * internal identifier, and `openTableGuestSession`'s only client input is
 * the original opaque token anyway — it never needs these ids echoed back
 * to it. Exposing them here would let anyone probe the public endpoint
 * with guessed tokens to map out real tenant/table id structure with no
 * authorization check at all, for no UI benefit. The canonical scope
 * itself is still resolved server-side, from scratch, inside
 * `openTableGuestSession` — this DTO only narrows what leaves the server
 * over the wire for this one preview call.
 */
export interface TableQrPublicPreview {
  status: TableQrValidityStatus;
  tableDisplayName?: string;
  branchDisplayName?: string;
}

export function toPublicPreview(
  resolution: TableQrResolution,
): TableQrPublicPreview {
  if (resolution.validityStatus !== "valid") {
    return { status: resolution.validityStatus };
  }
  return {
    status: "valid",
    tableDisplayName: resolution.tableDisplayName,
    branchDisplayName: resolution.branchDisplayName,
  };
}

function toDate(value: unknown): Date | null {
  if (value === null || value === undefined) return null;
  if (typeof (value as { toDate?: () => Date }).toDate === "function") {
    return (value as { toDate: () => Date }).toDate();
  }
  return new Date(value as string | number);
}

/**
 * Resolves an opaque QR token to organization/restaurant/branch/table
 * identity, entirely server-side (Admin SDK — bypasses Firestore Security
 * Rules by design, since `tableQrCodes`/`restaurantTables` are not
 * client-readable at all; see `firestore.rules`'s fail-closed catch-all).
 * Mirrors `ResolveTableQrToken`'s exact logic
 * (`lib/features/qr/application/use_cases/resolve_table_qr_token.dart`):
 *
 * 1. Unknown token -> `notFound`.
 * 2. A token whose `TableQrCode` is not `active`, or is past its own
 *    `expiresAt` -> `expired` (if the reason is specifically expiry) or
 *    `invalid` (anything else — inactive/rotated).
 * 3. A resolved table that doesn't exist or is `isActive: false` ->
 *    `notFound` (same reasoning as the Dart use case: an inactive table is
 *    treated as "no such table," not "found but denied").
 * 4. An active table that isn't currently `available` (occupied/reserved/
 *    cleaning/disabled) -> `invalid` — the code itself is genuine, but this
 *    specific table can't accept a new session right now.
 * 5. A table that otherwise would resolve `valid`, but whose current-minute
 *    `tableProtectionMinuteBuckets` entry still lists at least one
 *    reservationId (Faz R.1C.2 QR T-20 enforcement) -> `reserved`.
 * 6. Otherwise -> `valid`, with identity denormalized directly off the
 *    `tableQrCodes`/`restaurantTables` documents (both Cloud-Function/
 *    Admin-SDK-only-written today — see this phase's own report for why a
 *    live `branches`/`restaurants` join wasn't added yet).
 *
 * Used by both `resolveTableQrToken` (read-only preview) and
 * `openTableGuestSession` (which independently re-resolves from the raw
 * token rather than trusting a caller-supplied organization/branch/table
 * id — the whole point of this being a shared function, not two
 * independently-drifting copies).
 */
export async function resolveTableQrTokenInternal(
  token: string,
): Promise<TableQrResolution> {
  const db = getFirestore();

  const qrSnapshot = await db
    .collection("tableQrCodes")
    .where("opaqueToken", "==", token)
    .limit(1)
    .get();
  if (qrSnapshot.empty) {
    return { validityStatus: "notFound" };
  }
  const qrDoc = qrSnapshot.docs[0];
  const qr = qrDoc.data();

  const now = new Date();
  const expiresAt = toDate(qr.expiresAt);
  const isPastExpiry = expiresAt !== null && now >= expiresAt;
  if (qr.status !== TABLE_QR_CODE_STATUS.active || isPastExpiry) {
    return { validityStatus: isPastExpiry ? "expired" : "invalid" };
  }

  const tableId = qr.tableId;
  if (typeof tableId !== "string" || tableId.length === 0) {
    return { validityStatus: "notFound" };
  }

  const tableDoc = await db.collection("restaurantTables").doc(tableId).get();
  if (!tableDoc.exists) {
    return { validityStatus: "notFound" };
  }
  const table = tableDoc.data()!;
  if (table.isActive !== true) {
    return { validityStatus: "notFound" };
  }
  if (table.status !== RESTAURANT_TABLE_STATUS.available) {
    return { validityStatus: "invalid" };
  }

  // Faz R.1C.2 §1 — QR T-20 enforcement, server-authoritative. Deterministic
  // get-by-id only (`{tableId}__{epochMinute}`) — never a query, never a
  // scheduler dependency; `epochMinute = floor(serverNowMillis / 60000)`
  // against this call's own server clock, never anything client-supplied.
  // A missing bucket, or one whose `reservationIds` array is empty, means
  // normal QR behavior — only a bucket that both exists *and* still lists
  // at least one reservationId blocks a new session. This same function is
  // called fresh by both `resolveTableQrToken` (preview) and
  // `openTableGuestSession` (actual open) — each call independently
  // re-evaluates against its own current server time, so `openTableGuest
  // Session` never trusts a prior preview's result. Reuses the same [now]
  // snapshot taken above (this function's own single point-in-time for the
  // whole resolution), not a second, independently-drifting clock read.
  const minuteBucketDoc = await db
    .collection("tableProtectionMinuteBuckets")
    .doc(`${tableId}__${epochMinuteOf(now)}`)
    .get();
  if (minuteBucketDoc.exists) {
    const reservationIds = minuteBucketDoc.data()!.reservationIds;
    if (Array.isArray(reservationIds) && reservationIds.length > 0) {
      return { validityStatus: "reserved" };
    }
  }

  return {
    validityStatus: "valid",
    organizationId: table.organizationId,
    restaurantId: table.restaurantId,
    branchId: table.branchId,
    tableId,
    tableDisplayName: table.displayName,
    branchDisplayName: table.branchDisplayName,
    qrCodeId: qrDoc.id,
  };
}
