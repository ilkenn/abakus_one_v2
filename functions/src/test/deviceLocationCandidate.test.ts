import { test } from "node:test";
import assert from "node:assert";
import { parseDeviceLocationCandidate } from "../fraud/deviceLocationCandidate";

/**
 * Pure, no-emulator unit tests — FRAUD-F.1. Mirrors
 * `deliveryPaymentPolicy.test.ts`'s "no Firestore/Functions/Auth emulator
 * involved" shape. Every case a malicious or buggy client could send is
 * exercised here — none of them may ever throw.
 */

test("parseDeviceLocationCandidate: undefined input is unavailable/not_supplied", () => {
  const result = parseDeviceLocationCandidate(undefined);
  assert.strictEqual(result.availability, "unavailable");
  assert.strictEqual(result.clientLocation, null);
  assert.strictEqual(result.unavailableReason, "not_supplied");
});

test("parseDeviceLocationCandidate: null input is unavailable/not_supplied", () => {
  const result = parseDeviceLocationCandidate(null);
  assert.strictEqual(result.availability, "unavailable");
});

test("parseDeviceLocationCandidate: a non-object input is unavailable/not_supplied", () => {
  const result = parseDeviceLocationCandidate("not an object");
  assert.strictEqual(result.availability, "unavailable");
});

test("parseDeviceLocationCandidate: an explicit unavailable status is honored with its reason", () => {
  const result = parseDeviceLocationCandidate({
    status: "unavailable",
    unavailableReason: "permission_denied",
  });
  assert.strictEqual(result.availability, "unavailable");
  assert.strictEqual(result.unavailableReason, "permission_denied");
  assert.strictEqual(result.clientLocation, null);
});

test("parseDeviceLocationCandidate: an unavailable status with no reason defaults to 'unspecified'", () => {
  const result = parseDeviceLocationCandidate({ status: "unavailable" });
  assert.strictEqual(result.unavailableReason, "unspecified");
});

test("parseDeviceLocationCandidate: an unrecognized status string is incomplete, not unavailable", () => {
  const result = parseDeviceLocationCandidate({ status: "definitely-real-i-promise" });
  assert.strictEqual(result.availability, "incomplete");
  assert.strictEqual(result.clientLocation, null);
});

test("parseDeviceLocationCandidate: a fully valid available candidate is parsed exactly", () => {
  const result = parseDeviceLocationCandidate({
    status: "available",
    latitude: 41.05,
    longitude: 29.01,
    accuracyMeters: 15,
    clientCapturedAt: "2026-08-15T09:00:00.000Z",
    mockLocationStatus: "detected",
    permissionState: "granted",
    precisionState: "precise",
  });
  assert.strictEqual(result.availability, "available");
  assert.deepStrictEqual(result.clientLocation, {
    latitude: 41.05,
    longitude: 29.01,
    accuracyMeters: 15,
    clientCapturedAt: "2026-08-15T09:00:00.000Z",
    mockLocationStatus: "detected",
    permissionState: "granted",
    precisionState: "precise",
  });
});

test("parseDeviceLocationCandidate: missing latitude is incomplete", () => {
  const result = parseDeviceLocationCandidate({
    status: "available",
    longitude: 29.01,
    accuracyMeters: 15,
    clientCapturedAt: "2026-08-15T09:00:00.000Z",
  });
  assert.strictEqual(result.availability, "incomplete");
  assert.strictEqual(result.clientLocation, null);
});

test("parseDeviceLocationCandidate: a non-numeric accuracyMeters is incomplete", () => {
  const result = parseDeviceLocationCandidate({
    status: "available",
    latitude: 41.05,
    longitude: 29.01,
    accuracyMeters: "fifteen",
    clientCapturedAt: "2026-08-15T09:00:00.000Z",
  });
  assert.strictEqual(result.availability, "incomplete");
});

test("parseDeviceLocationCandidate: NaN/Infinity coordinates are incomplete, never accepted", () => {
  const result = parseDeviceLocationCandidate({
    status: "available",
    latitude: Number.NaN,
    longitude: Number.POSITIVE_INFINITY,
    accuracyMeters: 15,
    clientCapturedAt: "2026-08-15T09:00:00.000Z",
  });
  assert.strictEqual(result.availability, "incomplete");
});

test("parseDeviceLocationCandidate: a missing clientCapturedAt is incomplete", () => {
  const result = parseDeviceLocationCandidate({
    status: "available",
    latitude: 41.05,
    longitude: 29.01,
    accuracyMeters: 15,
  });
  assert.strictEqual(result.availability, "incomplete");
});

test("parseDeviceLocationCandidate: an unrecognized mockLocationStatus falls back to 'unavailable', never rejected outright", () => {
  const result = parseDeviceLocationCandidate({
    status: "available",
    latitude: 41.05,
    longitude: 29.01,
    accuracyMeters: 15,
    clientCapturedAt: "2026-08-15T09:00:00.000Z",
    mockLocationStatus: "forged-value",
  });
  assert.strictEqual(result.availability, "available");
  assert.strictEqual(result.clientLocation?.mockLocationStatus, "unavailable");
});

test("parseDeviceLocationCandidate: missing permissionState/precisionState default to 'unknown', never rejected", () => {
  const result = parseDeviceLocationCandidate({
    status: "available",
    latitude: 41.05,
    longitude: 29.01,
    accuracyMeters: 15,
    clientCapturedAt: "2026-08-15T09:00:00.000Z",
  });
  assert.strictEqual(result.availability, "available");
  assert.strictEqual(result.clientLocation?.permissionState, "unknown");
  assert.strictEqual(result.clientLocation?.precisionState, "unknown");
});

test("parseDeviceLocationCandidate: extra/forged fields (distanceMeters, riskScore) are silently ignored, never surfaced", () => {
  const result = parseDeviceLocationCandidate({
    status: "available",
    latitude: 41.05,
    longitude: 29.01,
    accuracyMeters: 15,
    clientCapturedAt: "2026-08-15T09:00:00.000Z",
    distanceMeters: 999999,
    riskScore: 0,
    policyVersion: "forged-v1",
  });
  assert.strictEqual(result.availability, "available");
  assert.deepStrictEqual(Object.keys(result.clientLocation!).sort(), [
    "accuracyMeters",
    "clientCapturedAt",
    "latitude",
    "longitude",
    "mockLocationStatus",
    "permissionState",
    "precisionState",
  ]);
});
