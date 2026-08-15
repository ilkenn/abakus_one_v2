import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { requireStaffPermission } from "./staffAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";

/**
 * Faz R.3A §4 — the admin list/calendar's server-authoritative read model.
 * The customer-facing `watchReservation` (`ReservationRepository`) is a
 * single-document real-time stream; staff need a *query* across many
 * reservations, and "the client constructs an arbitrary Firestore query
 * against `reservations` trusting rules alone" was explicitly rejected —
 * this callable is that server-authoritative alternative.
 *
 * **Bounded, never a blind collection scan.** [dateFrom]/[dateTo] are
 * required (not optional), capped at [MAX_DATE_RANGE_DAYS] apart, and are
 * the one Firestore range filter this query uses (`requestedTime`, the
 * one always-present time field every Reservation has — `confirmedTime`
 * is `null` until a Reservation is actually confirmed, so filtering on it
 * would silently exclude every still-pending request from a "Bugün"/
 * "Yaklaşan" view). `status`/`areaId` filters are applied **in-memory**
 * after one bounded, indexed Firestore fetch (`branchId` + `requestedTime`
 * range, `orderBy requestedTime`) rather than as additional Firestore
 * `where` clauses — avoids needing a combinatorial explosion of composite
 * indexes for every filter combination, mirrors
 * `getReservationAvailability.ts`'s own "one bulk query, filter/compute
 * in memory" precedent. [areaId] filters on `requestedAreaId` specifically
 * (disclosed limitation: a reservation whose area was *changed* via an
 * accepted change-proposal is filtered by the area it was originally
 * requested under, not its current `confirmedAreaId` — acceptable for
 * this phase's list/calendar use, not a correctness issue for any other
 * consumer).
 *
 * **Cross-tenant fails closed structurally**, not just by convention:
 * every returned document's `organizationId` is verified to equal the
 * caller-authorized [organizationId] before being included — belt-and-
 * suspenders on top of the `branchId`-scoped query itself, since
 * `branchId` values are opaque strings a caller could otherwise guess or
 * reuse across tenants.
 */

const MAX_DATE_RANGE_DAYS = 62;
const INTERNAL_FETCH_CAP = 400;
const DEFAULT_PAGE_SIZE = 50;
const MAX_PAGE_SIZE = 100;

interface ReservationListItem {
  id: string;
  status: string;
  partySize: number;
  requestedTime: string;
  requestedAreaId: string;
  confirmedTime: string | null;
  confirmedAreaId: string | null;
  contactFirstName: string;
  contactLastName: string;
  assignedTableId: string | null;
  preorderOrderId: string | null;
  activeProposalCustomerResponseDeadlineAt: string | null;
}

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value;
}

function requireIsoDate(value: unknown, field: string): Date {
  const raw = requireString(value, field);
  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) {
    throw new HttpsError("invalid-argument", `${field} must be a valid ISO 8601 timestamp.`);
  }
  return parsed;
}

function toIso(value: unknown): string | null {
  if (!value) return null;
  const asDate = (value as { toDate?: () => Date }).toDate?.() ?? (value as Date);
  return asDate instanceof Date ? asDate.toISOString() : null;
}

export const listReservationsForBranch = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireString(data.organizationId, "organizationId");
    const branchId = requireString(data.branchId, "branchId");
    const dateFrom = requireIsoDate(data.dateFrom, "dateFrom");
    const dateTo = requireIsoDate(data.dateTo, "dateTo");

    if (dateFrom.getTime() > dateTo.getTime()) {
      throw new HttpsError("invalid-argument", "dateFrom must not be after dateTo.");
    }
    const rangeDays = (dateTo.getTime() - dateFrom.getTime()) / 86_400_000;
    if (rangeDays > MAX_DATE_RANGE_DAYS) {
      throw new HttpsError(
        "invalid-argument",
        `The date range must not exceed ${MAX_DATE_RANGE_DAYS} days (requested ${Math.ceil(rangeDays)}).`,
      );
    }

    const statuses = Array.isArray(data.statuses) ? (data.statuses as unknown[]).filter((s) => typeof s === "string") as string[] : null;
    const areaId = typeof data.areaId === "string" && data.areaId.length > 0 ? data.areaId : null;
    const pageSize = Math.min(
      MAX_PAGE_SIZE,
      Math.max(1, typeof data.pageSize === "number" ? Math.floor(data.pageSize) : DEFAULT_PAGE_SIZE),
    );
    const cursor = typeof data.cursor === "string" && data.cursor.length > 0 ? new Date(data.cursor) : null;

    requireStaffPermission(request, organizationId, "manageReservations");

    const db = getFirestore();
    let query = db
      .collection("reservations")
      .where("branchId", "==", branchId)
      .where("requestedTime", ">=", dateFrom)
      .where("requestedTime", "<=", dateTo)
      .orderBy("requestedTime", "asc")
      .limit(INTERNAL_FETCH_CAP);
    if (cursor) {
      query = query.startAfter(cursor);
    }

    const snapshot = await query.get();

    const items: ReservationListItem[] = [];
    // The cursor for the *next* page must be the `requestedTime` of the
    // last document actually walked in this loop — never just
    // `snapshot.docs`'s own last entry, which (when the loop breaks early
    // on reaching `pageSize`) can sit far ahead of what was actually
    // returned, silently skipping every document in between on the next
    // call.
    let lastWalkedRequestedTime: unknown = null;
    let reachedPageSize = false;

    for (const doc of snapshot.docs) {
      const r = doc.data();
      lastWalkedRequestedTime = r.requestedTime;
      // Structural cross-tenant guard — belt-and-suspenders on top of the
      // branchId-scoped query itself.
      if (r.organizationId !== organizationId) continue;
      if (statuses && !statuses.includes(r.status)) continue;
      if (areaId && r.requestedAreaId !== areaId) continue;

      items.push({
        id: doc.id,
        status: String(r.status ?? ""),
        partySize: Number(r.partySize ?? 0),
        requestedTime: toIso(r.requestedTime) ?? "",
        requestedAreaId: String(r.requestedAreaId ?? ""),
        confirmedTime: toIso(r.confirmedTime),
        confirmedAreaId: (r.confirmedAreaId as string | null) ?? null,
        contactFirstName: String(r.contactFirstName ?? ""),
        contactLastName: String(r.contactLastName ?? ""),
        assignedTableId: (r.assignedTableId as string | null) ?? null,
        preorderOrderId: (r.preorderOrderId as string | null) ?? null,
        activeProposalCustomerResponseDeadlineAt: toIso(r.activeProposalCustomerResponseDeadlineAt),
      });

      if (items.length >= pageSize) {
        reachedPageSize = true;
        break;
      }
    }

    // A next page can only exist if either (a) we stopped early because
    // we filled this page, or (b) we walked the entire internal fetch cap
    // without filling it (there could be more matching documents beyond
    // the cap). If neither is true, the loop walked every document
    // Firestore had in range — there is nothing left to page to.
    const exhaustedInternalCap = !reachedPageSize && snapshot.docs.length >= INTERNAL_FETCH_CAP;
    const nextCursor = reachedPageSize || exhaustedInternalCap ? toIso(lastWalkedRequestedTime) : null;

    return { reservations: items, nextCursor };
  },
);
