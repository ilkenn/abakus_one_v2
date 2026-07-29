/// One required-document metadata entry — a **contract only**: no image
/// or file is ever stored here or anywhere in this phase (no secure
/// document/blob storage infrastructure exists in this codebase yet; per
/// the explicit rule, document-image storage is not implemented until one
/// does).
class CourierDocumentRequirement {
  const CourierDocumentRequirement({
    required this.documentType,
    this.isProvided = false,
    this.verifiedAt,
  });

  /// Free-text type label (e.g. `'driversLicense'`, `'vehicleRegistration'`)
  /// — not a closed enum, since the actual required-document set is a
  /// business/legal decision this phase doesn't make.
  final String documentType;

  final bool isProvided;
  final DateTime? verifiedAt;
}
