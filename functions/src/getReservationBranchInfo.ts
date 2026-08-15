import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { resolveActiveReservationBranch } from "./reservationScope";
import { MINIMUM_ADVANCE_MINUTES } from "./reservationConfig";
import { shouldEnforceAppCheck } from "./appCheckConfig";

/**
 * Server-authoritative, read-only reservation branch info — Faz R.2 §9.
 * The customer reservation flow needs `ReservationPolicy.maxPartySize`
 * (step 1) and the list of active `reservationAreas` (step 2) before the
 * user has picked anything else — both currently sit in Firestore
 * collections with no client read access at all (`reservationPolicies`/
 * `reservationAreas` have no `firestore.rules` match block, falling
 * through to the fail-closed catch-all). This callable is the minimal,
 * server-authoritative, UI-shaped read model for exactly those two things
 * — never the raw policy/area documents, never anything about
 * capacity/occupancy (that's `getReservationAvailability`'s job, and even
 * it never exposes raw numbers either).
 *
 * Real phone-auth required, mirroring `submitReservation.ts`'s own gate —
 * every reservation-domain endpoint in this codebase requires a real
 * customer identity, this one included, even though it only reads.
 */
export const getReservationBranchInfo = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const isRealCustomer = request.auth.token?.firebase?.sign_in_provider === "phone";
    if (!isRealCustomer) {
      throw new HttpsError(
        "permission-denied",
        "This requires a phone-verified identity. Anonymous technical identities are not permitted.",
      );
    }

    const data = (request.data ?? {}) as Record<string, unknown>;
    if (typeof data.restaurantId !== "string" || data.restaurantId.length === 0) {
      throw new HttpsError("invalid-argument", "restaurantId is required.");
    }
    if (typeof data.branchId !== "string" || data.branchId.length === 0) {
      throw new HttpsError("invalid-argument", "branchId is required.");
    }
    const restaurantId = data.restaurantId;
    const branchId = data.branchId;

    const db = getFirestore();

    // resolveActiveReservationBranch requires a Transaction (Faz R.1A.1
    // REQUIRED fix #1 — every read it performs must participate in
    // Firestore's optimistic-concurrency read-set). This endpoint never
    // writes anything — the transaction here exists only to give the
    // restaurant/organization/branch/policy chain read a single consistent
    // snapshot, not for conflict-retry-on-write semantics; it commits as a
    // no-op once the reads complete. This is advisory data, not an
    // authoritative gate for any write — `submitReservation.ts`'s own
    // transaction is what actually enforces policy/scope validity at
    // submit time.
    const scope = await db.runTransaction(async (tx) =>
      resolveActiveReservationBranch(tx, db, { restaurantId, branchId }),
    );
    if (scope.status === "notFound") {
      throw new HttpsError("not-found", "Branch not found.");
    }
    if (scope.status === "invalid") {
      throw new HttpsError(
        "failed-precondition",
        "This branch is not currently accepting reservations.",
      );
    }
    const policy = scope.policy!;

    const areasSnapshot = await db
      .collection("reservationAreas")
      .where("branchId", "==", branchId)
      .where("isActive", "==", true)
      .get();
    const areas = areasSnapshot.docs
      .map((doc) => ({
        id: doc.id,
        displayName: String(doc.data().displayName ?? ""),
        sortOrder: typeof doc.data().sortOrder === "number" ? doc.data().sortOrder : 0,
      }))
      .sort((a, b) => a.sortOrder - b.sortOrder)
      .map(({ id, displayName }) => ({ id, displayName }));

    return {
      policy: {
        maxPartySize: policy.maxPartySize,
        slotIntervalMinutes: policy.slotIntervalMinutes,
        reservationDurationMinutes: policy.reservationDurationMinutes,
        bookingHorizonDays: policy.bookingHorizonDays,
        timezone: policy.timezone,
        minimumAdvanceMinutes: MINIMUM_ADVANCE_MINUTES,
      },
      areas,
    };
  },
);
