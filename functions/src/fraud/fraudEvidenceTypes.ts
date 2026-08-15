/**
 * Shared type vocabulary for the Delivery Fraud Location Evidence
 * architecture — FRAUD-F.0 (docs/decisions.md, docs/fraud_evidence_architecture.md).
 * Mirrors lib/core/fraud/domain/'s Dart types field-for-field; the two are
 * kept in sync by hand (this codebase has no shared IDL/codegen step — see
 * CLAUDE.md's "no code generation step").
 *
 * FRAUD-F.0 defines these types and the getPreciseFraudEvidence read path
 * only. No production code constructs a FraudEvidence document yet —
 * capture is FRAUD-F.1 (address save) and FRAUD-F.2 (order submit, blocked
 * on a real submitDeliveryOrder callable), neither started.
 */

export type FraudEvidenceKind = "addressSave" | "orderSubmit";

/**
 * Never a binary "is this location genuine" verdict — see each value's
 * own comment. Mirrors lib/core/fraud/domain/mock_location_status.dart.
 */
export type MockLocationStatus =
  /** The platform reported this reading as mocked/simulated. */
  | "detected"
  /**
   * The platform did not report the reading as mocked. Does NOT mean the
   * location is genuine — only that the one detector this platform
   * exposes did not fire.
   */
  | "notDetected"
  /** This platform exposes no mock-location signal at all (e.g. iOS). */
  | "unsupported"
  /** A signal exists on this platform but this reading didn't carry one. */
  | "unavailable";

export interface ClientLocationEvidence {
  latitude: number;
  longitude: number;
  accuracyMeters: number;
  /** Untrusted, client-reported device-clock timestamp (ISO 8601). Never
   *  used for risk-timing logic — see FraudEvidenceRecord.serverReceivedAt. */
  clientCapturedAt: string;
  mockLocationStatus: MockLocationStatus;
}

export interface ServerFraudInterpretation {
  distanceMeters?: number | null;
  province?: string | null;
  district?: string | null;
  neighborhood?: string | null;
  street?: string | null;
  /** `null` when unresolved — the UI fallback is the fixed string
   *  "Bina numarası belirlenemedi.", never a fabricated value. */
  buildingNumber?: string | null;
  formattedAddress?: string | null;
  providerPlaceId?: string | null;
  phoneVerified?: boolean | null;
  /** Sourced only from `request.app` (the Cloud Function's own trusted
   *  request context) — never from client-supplied data. */
  appCheckState?: string | null;
  policyVersion?: string | null;
}

export interface FraudEvidenceRecord {
  id: string;
  kind: FraudEvidenceKind;
  subjectUid: string;
  savedAddressId?: string | null;
  priorEvidenceId?: string | null;
  clientLocation: ClientLocationEvidence;
  serverReceivedAt: string;
  createdAt: string;
  expiresAt?: string | null;
  organizationId: string | null;
  branchId: string | null;
  orderId: string | null;
  interpretation: ServerFraudInterpretation;
}

export interface FraudEvidenceAccessLogEntry {
  id: string;
  evidenceId: string;
  actorUid: string;
  capability: "fraudEvidence.readPrecise";
  action: "read";
  accessedAt: string;
  /** Server-controlled scope metadata for the accessed evidence at the
   *  time of access — never a copy of the evidence's own sensitive
   *  payload (organizationId/branchId/orderId only). */
  scope: {
    organizationId: string | null;
    branchId: string | null;
    orderId: string | null;
  };
}
