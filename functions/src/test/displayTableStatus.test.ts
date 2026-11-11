import { test } from "node:test";
import assert from "node:assert";

import { countActivePortions, displayTableStatus } from "../posOperationalView";

const BEVERAGES = new Set(["prod_su", "prod_kola"]);

/**
 * 2026-11-11 — a QR guest session leaves the stored table `status` at
 * "available" on purpose (QR resolution only accepts "available" tables),
 * so the POS showed a table with a live, ordering QR session as "Boş".
 * Pure function — no emulator needed.
 */
test("displayTableStatus: an available table with an active session is shown occupied", () => {
  assert.strictEqual(
    displayTableStatus({ status: "available", activeTableSessionId: "tsess-1" }),
    "occupied",
  );
});

test("displayTableStatus: an available table without a session stays available", () => {
  assert.strictEqual(displayTableStatus({ status: "available", activeTableSessionId: null }), "available");
  assert.strictEqual(displayTableStatus({}), "available");
});

test("displayTableStatus: a manual override always wins", () => {
  assert.strictEqual(
    displayTableStatus({ status: "available", activeTableSessionId: "tsess-1", statusOverride: "billRequested" }),
    "billRequested",
  );
});

test("displayTableStatus: any other stored status is shown unchanged, session or not", () => {
  for (const stored of ["occupied", "reserved", "cleaning", "disabled"]) {
    assert.strictEqual(displayTableStatus({ status: stored, activeTableSessionId: "tsess-1" }), stored);
    assert.strictEqual(displayTableStatus({ status: stored, activeTableSessionId: null }), stored);
  }
});

// 2026-11-11 — bird's-eye chairs: one per main portion, no manual headcount.
test("countActivePortions: sums line quantities of live orders", () => {
  assert.strictEqual(
    countActivePortions([
      { status: "confirmed", lines: [{ status: "accepted", productId: "prod_bowl", quantity: 2 }] },
      { status: "pendingConfirmation", lines: [{ status: "pendingApproval", productId: "prod_clasico", quantity: 1 }] },
    ], BEVERAGES),
    3,
  );
});

test("countActivePortions: beverages, cancelled/rejected lines and orders never count", () => {
  assert.strictEqual(
    countActivePortions([
      {
        status: "confirmed",
        lines: [
          { status: "accepted", productId: "prod_tava", quantity: 1 },
          { status: "accepted", productId: "prod_su", quantity: 3 },
          { status: "accepted", productId: "prod_kola", quantity: 1 },
          { status: "rejected", productId: "prod_tava", quantity: 2 },
          { status: "cancelled", productId: "prod_tava", quantity: 2 },
        ],
      },
      { status: "cancelled", lines: [{ status: "accepted", productId: "prod_tava", quantity: 5 }] },
      { status: "rejected", lines: [{ status: "accepted", productId: "prod_tava", quantity: 5 }] },
    ], BEVERAGES),
    1,
  );
});

test("countActivePortions: no orders, no lines or malformed lines count as zero", () => {
  assert.strictEqual(countActivePortions([], BEVERAGES), 0);
  assert.strictEqual(countActivePortions([{ status: "confirmed" }], BEVERAGES), 0);
  assert.strictEqual(countActivePortions([{ status: "confirmed", lines: [{ status: "accepted" }] }], BEVERAGES), 0);
});

test("countActivePortions: a line whose product is not in the catalog (e.g. Bowl Builder) counts", () => {
  assert.strictEqual(
    countActivePortions([{ status: "confirmed", lines: [{ status: "accepted", productId: "bowl-custom-1", quantity: 1 }] }], BEVERAGES),
    1,
  );
});
