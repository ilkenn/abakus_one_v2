/// A vendor a restaurant purchases ingredients from — Phase 7
/// (`docs/decisions.md` ADR-024). Organization-scoped.
class Supplier {
  const Supplier({
    required this.id,
    required this.organizationId,
    required this.name,
    this.contactPhone,
    this.contactEmail,
    this.isActive = true,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final String name;
  final String? contactPhone;
  final String? contactEmail;
  final bool isActive;
  final DateTime createdAt;
  final int revision;

  Supplier copyWith({
    String? name,
    String? contactPhone,
    String? contactEmail,
    bool? isActive,
    required int revision,
  }) {
    return Supplier(
      id: id,
      organizationId: organizationId,
      name: name ?? this.name,
      contactPhone: contactPhone ?? this.contactPhone,
      contactEmail: contactEmail ?? this.contactEmail,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
