import type {
  ClientLocationEvidence,
  FraudEvidenceAvailability,
  MockLocationStatus,
} from "./fraudEvidenceTypes";

/**
 * Parses/validates the optional, fully client-controlled
 * `deviceLocationCandidate` payload a request to `saveDeliveryAddress` may
 * carry — FRAUD-F.1. **Never throws** — any malformed or missing input
 * degrades to a safe "no usable evidence" result rather than aborting the
 * address save, per the approved architecture's §8 ("location availability
 * must not make the normal address-save UX unusable"). This is the single
 * point where raw, untrusted client input is turned into the (still
 * untrusted, but now *shaped*) `ClientLocationEvidence` `saveDeliveryAddress`
 * stores — nothing here computes a server-authoritative field (distance,
 * geocode, risk); those are derived separately, after this function
 * returns.
 */

const KNOWN_MOCK_LOCATION_STATUSES: readonly MockLocationStatus[] = [
  "detected",
  "notDetected",
  "unsupported",
  "unavailable",
];

export interface ParsedDeviceLocationCandidate {
  availability: FraudEvidenceAvailability;
  clientLocation: ClientLocationEvidence | null;
  unavailableReason: string | null;
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

export function parseDeviceLocationCandidate(
  raw: unknown,
): ParsedDeviceLocationCandidate {
  if (raw === null || raw === undefined || typeof raw !== "object") {
    return {
      availability: "unavailable",
      clientLocation: null,
      unavailableReason: "not_supplied",
    };
  }

  const candidate = raw as Record<string, unknown>;

  if (candidate.status === "unavailable") {
    const reason =
      typeof candidate.unavailableReason === "string" &&
      candidate.unavailableReason.length > 0
        ? candidate.unavailableReason
        : "unspecified";
    return { availability: "unavailable", clientLocation: null, unavailableReason: reason };
  }

  if (candidate.status !== "available") {
    // Neither "available" nor "unavailable" — a malformed/forged shape.
    // A candidate was clearly attempted, so this is "incomplete", not a
    // clean "unavailable".
    return { availability: "incomplete", clientLocation: null, unavailableReason: null };
  }

  const latitude = candidate.latitude;
  const longitude = candidate.longitude;
  const accuracyMeters = candidate.accuracyMeters;
  const clientCapturedAt = candidate.clientCapturedAt;

  if (
    !isFiniteNumber(latitude) ||
    !isFiniteNumber(longitude) ||
    !isFiniteNumber(accuracyMeters) ||
    typeof clientCapturedAt !== "string" ||
    clientCapturedAt.length === 0
  ) {
    return { availability: "incomplete", clientLocation: null, unavailableReason: null };
  }

  const mockLocationStatus = KNOWN_MOCK_LOCATION_STATUSES.includes(
    candidate.mockLocationStatus as MockLocationStatus,
  )
    ? (candidate.mockLocationStatus as MockLocationStatus)
    : "unavailable";

  const permissionState =
    typeof candidate.permissionState === "string" && candidate.permissionState.length > 0
      ? candidate.permissionState
      : "unknown";
  const precisionState =
    typeof candidate.precisionState === "string" && candidate.precisionState.length > 0
      ? candidate.precisionState
      : "unknown";

  return {
    availability: "available",
    clientLocation: {
      latitude,
      longitude,
      accuracyMeters,
      clientCapturedAt,
      mockLocationStatus,
      permissionState,
      precisionState,
    },
    unavailableReason: null,
  };
}
