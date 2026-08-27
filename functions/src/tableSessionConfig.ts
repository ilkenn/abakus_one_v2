import type { Timestamp } from "firebase-admin/firestore";

/**
 * AP-3 Wave 1 — shared domain contracts for the table-session / guest
 * sub-account foundation (`docs/order_operations_architecture.md`,
 * corrected AP-3 Stage A report §1/§6/§8). No Firestore I/O lives here —
 * mirrors `tableGuestSessionConfig.ts`'s own "policy/vocabulary only" shape.
 *
 * **Corrected ownership model (AP-3 Stage A correction #8)**: the original
 * Stage A draft proposed keying an anonymous guest's sub-account off the
 * `tableGuestSessions` document id (a session-scoped, not identity-scoped,
 * value) — broken, because a Firestore Security Rule cannot compare a
 * session doc id to `request.auth.uid`. `ownerAuthUid` — the caller's real
 * Firebase Auth uid, denormalized at creation exactly like
 * `tableGuestSessions.guestAuthUid`/`orders.guestAuthUid` already are — is
 * the only field a rule may ever authorize against.
 *
 * **Deterministic id refinement**: the corrected report's own draft (`
 * subaccount-{tableSessionId}-guest-{guestSessionId}`) keys an anonymous
 * guest's sub-account off the *session document id*, which is not a stable
 * identity if the same device/guest scans the same table's QR twice (each
 * scan currently creates a fresh `tableGuestSessions` doc —
 * `openTableGuestSession.ts` is unchanged in that respect). Since Firebase
 * anonymous auth sessions persist per device install, keying off
 * `request.auth.uid` (the same field the Security Rule itself authorizes
 * against) is both simpler and more robust — a re-scan by the same
 * anonymous device reuses its own sub-account rather than fragmenting into
 * a second one. Disclosed refinement, not a deviation in intent.
 *
 * The id is keyed on `(tableSessionId, uid)` alone, with no ownerType-
 * derived prefix — a single Firebase Auth uid is structurally either a real
 * phone customer or an anonymous guest, never both (`sign_in_provider` is
 * fixed for the life of that auth session), so the uid alone is already
 * unambiguous. `ownerType` is still stored on the document itself (for
 * display/audit), it just isn't needed to make the id collision-free.
 */

export const TABLE_SESSIONS_COLLECTION = "tableSessions";
export const GUEST_SUB_ACCOUNTS_COLLECTION = "guestSubAccounts";

export type TableSessionStatus = "active" | "closed" | "cancelled";

export interface TableSessionDoc {
  organizationId: string;
  restaurantId: string;
  branchId: string;
  tableId: string;
  status: TableSessionStatus;
  openedAt: Timestamp;
  closedAt: Timestamp | null;
  openedByType: "guestQrScan" | "staff";
  openedByStaffUid: string | null;
  /** Audit trail only (§6.4) — the session document itself is relocated on transfer, never re-created. */
  transferredFromTableId: string | null;
  version: number;
}

/**
 * `staffGeneral` — an unattributed catch-all, used only when the ordering
 * party is genuinely unknown (corrected report §10/#11). `namedWalkIn` — a
 * staff-entered display name for an unregistered walk-in guest, distinct
 * from the anonymous catch-all so a cashier's own attribution is never
 * conflated with "unknown."
 */
export type GuestSubAccountOwnerType =
  | "guestSession"
  | "authenticatedCustomer"
  | "namedWalkIn"
  | "staffGeneral";

/** Never "settled" — AP-3 never claims payment completion (corrected report §2). */
export type GuestSubAccountStatus = "open" | "closed" | "merged" | "voided";

export interface GuestSubAccountDoc {
  organizationId: string;
  branchId: string;
  tableSessionId: string;
  ownerType: GuestSubAccountOwnerType;
  /** Audit/reference only — never used in rules or in any authorization decision. */
  ownerSessionRef: string | null;
  /** The ONLY rules-authorization field. `null` only for `staffGeneral`. */
  ownerAuthUid: string | null;
  displayName: string;
  status: GuestSubAccountStatus;
  createdAt: Timestamp;
  createdByStaffUid: string | null;
  version: number;
}

export function deterministicIdentitySubAccountId(tableSessionId: string, uid: string): string {
  return `subaccount-${tableSessionId}-${uid}`;
}

export function staffGeneralSubAccountId(tableSessionId: string): string {
  return `subaccount-${tableSessionId}-staffGeneral`;
}

export function isTableSessionActive(session: { status: string }): boolean {
  return session.status === "active";
}
