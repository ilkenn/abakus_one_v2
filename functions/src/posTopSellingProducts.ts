import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { requireActiveDeviceSession } from "./trustedDevice";
import { shouldEnforceAppCheck } from "./appCheckConfig";

/**
 * POS "Çok Tercih Edilenler" (Top 20 best-sellers), 2026-11-03 — product
 * owner-approved minimal design (`docs/business_rules.md` BR-POS-001):
 * every `orders` document for this branch, filtered **in memory** to the
 * last [LOOKBACK_DAYS] days and to `accepted` lines only (never a
 * cancelled/rejected/pendingApproval line — this is meant to reflect real
 * completed sales, not raw attempts), tallied by `productId`, top 20 by
 * total quantity.
 *
 * Deliberately queries by `organizationId`/`branchId` equality only, with
 * the date/status filtering done after the read, rather than adding a
 * `timestamps.created` range clause to the Firestore query — that would
 * need a new composite index (`organizationId` + `branchId` +
 * `timestamps.created`) to be created and deployed before this could ever
 * run against a real project, which is exactly the kind of Firebase
 * wiring CLAUDE.md §5 reserves for an explicit, separate decision. This is
 * the approved MVP: no precomputed/incrementally-updated aggregate, no new
 * index — correct for a single branch's realistic order volume today, not
 * a permanently scalable design. Revisit (a precomputed aggregate updated
 * by a Firestore trigger) if branch order volume grows enough that
 * fetching every order becomes slow.
 *
 * Same authorization bar as every other POS read (`getPosTableOperationalView`'s
 * own doc comment explains why both staff-permission AND device-session
 * checks are required, not just one).
 */

const LOOKBACK_DAYS = 30;
const TOP_N = 20;

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}
function requireNonEmptyString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.length === 0) invalid(`${field} is required.`);
  return raw as string;
}

export const getTopSellingProducts = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const branchId = requireNonEmptyString(data.branchId, "branchId");
    const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
    const deviceSessionId = requireNonEmptyString(data.deviceSessionId, "deviceSessionId");

    await requireStaffPermission(request, organizationId, "manageDineInOrders");
    await requireBranchAccess(request, organizationId, branchId);
    await requireActiveDeviceSession(organizationId, branchId, deviceId, deviceSessionId);

    const db = getFirestore();
    const ordersSnap = await db
      .collection("orders")
      .where("organizationId", "==", organizationId)
      .where("branchId", "==", branchId)
      .get();

    const cutoff = new Date(Date.now() - LOOKBACK_DAYS * 24 * 60 * 60 * 1000);
    const cutoffIso = cutoff.toISOString();

    const quantityByProductId = new Map<string, number>();
    const nameByProductId = new Map<string, string>();

    for (const doc of ordersSnap.docs) {
      const order = doc.data();
      const createdAt = (order.timestamps as Record<string, unknown> | undefined)?.created;
      if (typeof createdAt !== "string" || createdAt < cutoffIso) continue;

      const lines = (order.lines ?? []) as Array<Record<string, unknown>>;
      for (const line of lines) {
        if (line.status !== "accepted") continue;
        const productId = line.productId;
        const quantity = line.quantity;
        if (typeof productId !== "string" || typeof quantity !== "number") continue;
        quantityByProductId.set(productId, (quantityByProductId.get(productId) ?? 0) + quantity);
        if (typeof line.productName === "string" && !nameByProductId.has(productId)) {
          nameByProductId.set(productId, line.productName);
        }
      }
    }

    const products = Array.from(quantityByProductId.entries())
      .map(([productId, quantitySold]) => ({
        productId,
        productName: nameByProductId.get(productId) ?? "",
        quantitySold,
      }))
      .sort((a, b) => b.quantitySold - a.quantitySold)
      .slice(0, TOP_N);

    return { products, lookbackDays: LOOKBACK_DAYS };
  },
);
