import { test } from "node:test";
import assert from "node:assert";

import { displayTableStatus } from "../posOperationalView";

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
