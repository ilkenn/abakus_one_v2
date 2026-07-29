import 'courier_compensation_metadata.dart';
import 'courier_document_requirement.dart';

/// Operational metadata for a [Courier] — kept as a separate record from
/// the registry entry itself (mirrors `PackagePreparation` staying
/// separate from `Order`): a courier's core identity rarely changes,
/// while document/compensation metadata is updated independently and by
/// different actors (HR/onboarding vs. dispatch).
class CourierOperationalProfile {
  const CourierOperationalProfile({
    required this.courierId,
    this.requiredDocuments = const [],
    this.compensationMetadata = const CourierCompensationMetadata(),

    /// A plain optional reference string — no emergency-contact entity
    /// exists in this codebase's staff architecture to reference (no
    /// `Staff` entity exists at all, per BR-ROLE-003), so this is the
    /// minimal honest shape rather than a fabricated relation.
    this.emergencyContactNote,
    required this.updatedAt,
  });

  final String courierId;
  final List<CourierDocumentRequirement> requiredDocuments;
  final CourierCompensationMetadata compensationMetadata;
  final String? emergencyContactNote;
  final DateTime updatedAt;

  CourierOperationalProfile copyWith({
    List<CourierDocumentRequirement>? requiredDocuments,
    CourierCompensationMetadata? compensationMetadata,
    String? emergencyContactNote,
    required DateTime updatedAt,
  }) {
    return CourierOperationalProfile(
      courierId: courierId,
      requiredDocuments: requiredDocuments ?? this.requiredDocuments,
      compensationMetadata: compensationMetadata ?? this.compensationMetadata,
      emergencyContactNote: emergencyContactNote ?? this.emergencyContactNote,
      updatedAt: updatedAt,
    );
  }
}
