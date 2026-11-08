import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { isTableGuestSessionActive } from "./tableGuestSessionConfig";
import { CHECKS_COLLECTION, CHECK_FINANCIAL_ADJUSTMENTS_COLLECTION } from "./checkAllocationConfig";

/**
 * Adım 5 (2026-11-07) — "Canlı Adisyon Okuma Gateway'i", the callable
 * ADR-058 deferred ("too large and too security-sensitive to responsibly
 * bolt on inside an already-large six-phase sequential pass") and
 * `docs/feature_status.md`'s own entry named in advance: `getLiveTableBill`,
 * mirroring `getPosTableOperationalView`'s "narrow read-only slice, nothing
 * raw" shape — but for an anonymous table guest instead of staff.
 *
 * **No Security Rules change** — `checks`/`checkAllocations`/
 * `checkFinancialAdjustments` stay `allow read: if false` for every
 * non-Admin-SDK caller exactly as before; this reads via the Admin SDK
 * (which always bypasses rules) from inside an authorization-checked Cloud
 * Function, the same boundary every other guest-facing read in this
 * codebase already uses.
 *
 * **Ownership check mirrors `submitDineInOrder.ts`'s own `guestSession`
 * mode exactly** (same `tableGuestSessions` doc lookup, same
 * `guestAuthUid === uid` check, same `isTableGuestSessionActive` gate, same
 * `session.tableSessionId` field — note this is a DIFFERENT id than the
 * `tableGuestSessions` doc id itself, the AP-3 Wave 1 table-session-group
 * concept `orders`/`checks` are actually grouped by) — never a new,
 * independently-invented verification path.
 *
 * **Why the running total is computed from `orders`, never from
 * `checks.computedTotalMinorUnits` directly**: a check's
 * `computedTotalMinorUnits` is "recomputed, transactionally, from this
 * check's own active allocations" (`checkAllocationConfig.ts`'s own doc
 * comment) — it only reflects money that has already been explicitly
 * allocated/split, which for the common "nobody has split yet" case stays
 * at (or near) zero throughout the whole meal even as the guest keeps
 * ordering. Exactly the trap `TableReceiptBuilder.build` already avoids by
 * summing `accepted` order lines directly and treating any
 * `subtotal - computedTotal` gap as a discount, not as "nothing ordered
 * yet." This function mirrors that same reasoning, but keeps the discount
 * source to genuinely unambiguous `checkFinancialAdjustments` records
 * (İkram/comp) rather than a subtotal-vs-computedTotal subtraction, which
 * would misreport "no discount" as "fully unbilled" for every unsplit
 * check — the same kind of pricing-correctness mistake ADR-058 was
 * guarding against by deferring this feature in the first place.
 *
 * **Disclosed scope boundary**: [runningTotalMinorUnits] is the current
 * owed amount BEFORE any payment already made against it — this does not
 * subtract partial/split payment attempts already recorded. A guest who
 * has already paid for part of a split check will see the table's full
 * remaining bill, not their own already-settled share. Narrowing this to
 * "what do I personally still owe after my own payments" is a separate,
 * larger design question (which split/sub-account is "mine," how it
 * reconciles with `PaymentAttempt` records) left for a future pass.
 */
export const getLiveTableBill = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const uid = request.auth.uid;
    const data = (request.data ?? {}) as Record<string, unknown>;
    const guestSessionId = data.tableSessionId;
    if (typeof guestSessionId !== "string" || guestSessionId.length === 0) {
      throw new HttpsError("invalid-argument", "tableSessionId is required.");
    }

    const db = getFirestore();
    const sessionDoc = await db.collection("tableGuestSessions").doc(guestSessionId).get();
    if (!sessionDoc.exists) {
      throw new HttpsError("not-found", "Table guest session not found.");
    }
    const session = sessionDoc.data()!;
    if (session.guestAuthUid !== uid) {
      throw new HttpsError("failed-precondition", "This table session does not belong to the caller.");
    }
    if (
      !isTableGuestSessionActive({
        status: String(session.status),
        expiresAt: session.expiresAt,
      })
    ) {
      throw new HttpsError("failed-precondition", "This table session is not active.");
    }
    const tableSessionId = session.tableSessionId as string | undefined;
    if (!tableSessionId) {
      throw new HttpsError(
        "failed-precondition",
        "This table guest session has no associated table session — re-scan the QR code.",
      );
    }

    const [ordersSnap, checksSnap] = await Promise.all([
      db.collection("orders").where("dineInSessionGroupId", "==", tableSessionId).get(),
      db.collection(CHECKS_COLLECTION).where("tableSessionId", "==", tableSessionId).get(),
    ]);

    let currencyCode = "TRY";
    const lines: Array<{ productName: string; quantity: number; unitPriceMinorUnits: number }> = [];
    let subtotalMinorUnits = 0;
    for (const orderDoc of ordersSnap.docs) {
      const orderLines = (orderDoc.data().lines ?? []) as Array<{
        status: string;
        productName: string;
        quantity: number;
        unitPrice?: { minorUnits: number; currencyCode?: string };
      }>;
      for (const line of orderLines) {
        if (line.status !== "accepted") continue;
        const unitPriceMinorUnits = line.unitPrice?.minorUnits ?? 0;
        if (line.unitPrice?.currencyCode) currencyCode = line.unitPrice.currencyCode;
        lines.push({ productName: line.productName, quantity: line.quantity, unitPriceMinorUnits });
        subtotalMinorUnits += unitPriceMinorUnits * line.quantity;
      }
    }

    const activeCheckIds = checksSnap.docs
      .filter((d) => d.data().status !== "cancelled")
      .map((d) => d.id);
    if (checksSnap.docs.length > 0 && typeof checksSnap.docs[0].data().currencyCode === "string") {
      currencyCode = checksSnap.docs[0].data().currencyCode as string;
    }

    let appliedDiscountsMinorUnits = 0;
    // Firestore `in` queries are capped at 30 values — chunk defensively,
    // same reasoning as `getPosTableOperationalView`'s own allocations
    // lookup (a real table realistically has a small, bounded number of
    // checks).
    for (let i = 0; i < activeCheckIds.length; i += 30) {
      const chunk = activeCheckIds.slice(i, i + 30);
      if (chunk.length === 0) continue;
      const adjustmentsSnap = await db
        .collection(CHECK_FINANCIAL_ADJUSTMENTS_COLLECTION)
        .where("checkId", "in", chunk)
        .where("status", "==", "active")
        .get();
      for (const doc of adjustmentsSnap.docs) {
        const amount = doc.data().appliedAmountMinorUnits as number | null;
        if (typeof amount === "number") appliedDiscountsMinorUnits += amount;
      }
    }

    const runningTotalMinorUnits = Math.max(0, subtotalMinorUnits - appliedDiscountsMinorUnits);

    return {
      exists: true,
      currencyCode,
      subtotalMinorUnits,
      appliedDiscountsMinorUnits,
      runningTotalMinorUnits,
      lines,
    };
  },
);
