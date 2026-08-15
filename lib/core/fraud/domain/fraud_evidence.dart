import '../../errors/business_rule_violation.dart';
import 'fraud_evidence_availability.dart';
import 'fraud_evidence_kind.dart';
import 'mock_location_status.dart';

/// Client-originated location evidence, exactly as reported by the device
/// — FRAUD-F.0/F.1. **A candidate evidence input, not an automatically-trusted
/// fact** — see [FraudEvidence]'s own doc comment on provenance.
/// [clientCapturedAt] in particular must never be treated as authoritative
/// timing; risk/derivation logic keys off [FraudEvidence.serverReceivedAt]
/// instead (`docs/decisions.md` FRAUD-F.0, correction #2).
class ClientLocationEvidence {
  const ClientLocationEvidence({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.clientCapturedAt,
    required this.mockLocationStatus,
    required this.permissionState,
    required this.precisionState,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;

  /// Device clock at capture time — untrusted, client-reported provenance
  /// only.
  final DateTime clientCapturedAt;

  final MockLocationStatus mockLocationStatus;

  /// The permission state at capture time (e.g. `'granted'`) — FRAUD-F.1.
  /// Free-text, mirroring [FraudSignal.type]'s own "no fabricated taxonomy"
  /// discipline: only one value (`'granted'`) is ever actually produced by
  /// a real capture today, since a candidate only exists at all when
  /// permission was granted (see
  /// `lib/features/address_search/data/address_location_gateway.dart`).
  final String permissionState;

  /// The platform's location-precision state at capture time (e.g.
  /// `'precise'` / `'reduced'` / `'unknown'`) — FRAUD-F.1, iOS 14+'s
  /// reduced-accuracy toggle and its cross-platform equivalent.
  final String precisionState;
}

/// Server-derived interpretation of a [FraudEvidence] record — FRAUD-F.0.
/// Every field is either produced by a Cloud Function or left `null` when
/// genuinely unavailable; never fabricated (the approved architecture's
/// explicit "do not fabricate unavailable values" rule). FRAUD-F.0 defines
/// this shape only — nothing in this phase populates [distanceMeters] or
/// any geocoded field yet (that begins at FRAUD-F.1).
class ServerFraudInterpretation {
  const ServerFraudInterpretation({
    this.distanceMeters,
    this.province,
    this.district,
    this.neighborhood,
    this.street,
    this.buildingNumber,
    this.formattedAddress,
    this.providerPlaceId,
    this.phoneVerified,
    this.appCheckState,
    this.policyVersion,
  });

  final double? distanceMeters;
  final String? province;
  final String? district;
  final String? neighborhood;
  final String? street;

  /// `null` when the reverse-geocode provider did not resolve a building
  /// number. The UI-facing fallback for this is the fixed string
  /// `"Bina numarası belirlenemedi."`, never a fabricated value.
  final String? buildingNumber;
  final String? formattedAddress;
  final String? providerPlaceId;

  final bool? phoneVerified;

  /// Sourced only from a Cloud Function's own trusted request context
  /// (`request.app`) — never from client-supplied data. `null` when App
  /// Check was not enforced/verified for this request (e.g. the local
  /// emulator, where no App Check token is ever sent).
  final String? appCheckState;

  /// Which version of the (not-yet-defined) risk-derivation policy
  /// produced this interpretation. FRAUD-F.0 deliberately defines no real
  /// policy or thresholds — see [FraudSignal]'s own doc comment.
  final String? policyVersion;
}

/// Immutable, server-authoritative security evidence of a device's
/// reported location at a fraud-relevant moment — FRAUD-F.0, the shared
/// foundation for the approved Delivery Fraud Location Evidence
/// architecture (`docs/decisions.md` FRAUD-F.0). No production code
/// constructs one yet: capture is FRAUD-F.1 (address save) and FRAUD-F.2
/// (order submit), neither started.
///
/// **Provenance is modelled explicitly, never blurred**:
/// - [clientLocation] — what the device reported. Client-originated,
///   untrusted evidence *input*, never an automatically-trusted fact.
/// - [serverReceivedAt] — when the authoritative server request this
///   evidence was captured inside actually arrived. Authoritative.
/// - [createdAt] — when this evidence document was actually persisted;
///   may trail [serverReceivedAt] by however long server-side derivation
///   took. Authoritative.
/// - [expiresAt] — server-generated retention boundary, derived from a
///   `FraudEvidenceRetentionPolicy`. Authoritative; `null` only before a
///   retention policy has been applied.
///
/// **Tenant anchoring is a structural invariant, enforced in the
/// constructor, not merely documented**: for [FraudEvidenceKind.addressSave]
/// evidence, [organizationId]/[branchId]/[orderId] must all be `null` — no
/// tenant owns pre-order evidence, and tenant users have no access to it.
/// For [FraudEvidenceKind.orderSubmit] evidence, all three must be
/// non-null. A partial anchor throws
/// [PartialFraudEvidenceTenantAnchorViolation].
///
/// **Availability/clientLocation consistency is a second structural
/// invariant, added FRAUD-F.1**: [clientLocation] is non-null if and only
/// if [availability] is [FraudEvidenceAvailability.available] — enforced
/// in the constructor via [InconsistentFraudEvidenceAvailabilityViolation],
/// the same "fail fast on a structurally invalid record" discipline as the
/// tenant-anchor check.
class FraudEvidence {
  FraudEvidence({
    required this.id,
    required this.kind,
    required this.subjectUid,
    this.savedAddressId,
    this.priorEvidenceId,
    this.clientLocation,
    required this.availability,
    this.unavailableReason,
    required this.serverReceivedAt,
    required this.createdAt,
    this.expiresAt,
    this.organizationId,
    this.branchId,
    this.orderId,
    this.interpretation = const ServerFraudInterpretation(),
  }) {
    final tenantFields = [organizationId, branchId, orderId];
    final populatedCount = tenantFields.where((f) => f != null).length;
    if (populatedCount != 0 && populatedCount != tenantFields.length) {
      throw const PartialFraudEvidenceTenantAnchorViolation();
    }
    final isAvailable = availability == FraudEvidenceAvailability.available;
    if (isAvailable != (clientLocation != null)) {
      throw const InconsistentFraudEvidenceAvailabilityViolation();
    }
  }

  final String id;
  final FraudEvidenceKind kind;

  /// The customer this evidence concerns — never the actor who *accessed*
  /// it later (that is a wholly separate concern; see the
  /// `fraudEvidenceAccessLog` collection described in
  /// `docs/decisions.md` FRAUD-F.0).
  final String subjectUid;

  final String? savedAddressId;

  /// For [FraudEvidenceKind.orderSubmit] evidence only — references the
  /// [FraudEvidenceKind.addressSave] evidence this order's address
  /// originated from, if one exists. That prior evidence is never
  /// mutated when this reference is created.
  final String? priorEvidenceId;

  /// `null` unless [availability] is [FraudEvidenceAvailability.available].
  final ClientLocationEvidence? clientLocation;

  final FraudEvidenceAvailability availability;

  /// Internal diagnostic only (e.g. `'permission_denied'`) — never shown
  /// to the customer, never treated as an error. `null` when
  /// [availability] is [FraudEvidenceAvailability.available].
  final String? unavailableReason;

  final DateTime serverReceivedAt;
  final DateTime createdAt;
  final DateTime? expiresAt;

  final String? organizationId;
  final String? branchId;
  final String? orderId;

  final ServerFraudInterpretation interpretation;

  /// `true` iff this is pre-order evidence (all three tenant fields
  /// `null`) — never owned by a tenant, never readable by any tenant
  /// actor, regardless of role.
  bool get isPreOrderEvidence =>
      organizationId == null && branchId == null && orderId == null;
}
