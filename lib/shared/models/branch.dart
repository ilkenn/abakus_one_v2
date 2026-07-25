/// A physical or virtual location operated by a [Restaurant].
///
/// Shared across features (orders, restaurant status/delivery, QR/table
/// ordering, and future staff-facing surfaces) because "which branch" is a
/// cross-cutting scoping concern, not owned by any single feature.
class Branch {
  final String id;
  final String restaurantId;
  final String name;
  final List<String> supportedLanguageCodes;
  final bool isActive;

  const Branch({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.supportedLanguageCodes,
    required this.isActive,
  });

  Branch copyWith({
    String? id,
    String? restaurantId,
    String? name,
    List<String>? supportedLanguageCodes,
    bool? isActive,
  }) {
    return Branch(
      id: id ?? this.id,
      restaurantId: restaurantId ?? this.restaurantId,
      name: name ?? this.name,
      supportedLanguageCodes:
          supportedLanguageCodes ?? this.supportedLanguageCodes,
      isActive: isActive ?? this.isActive,
    );
  }
}
