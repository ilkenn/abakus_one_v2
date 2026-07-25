/// Top-level commercial/brand entity that owns one or more [Branch]es.
///
/// This is the current single-tenant "restaurant" concept. It intentionally
/// mirrors the shape a future `Tenant`/`Brand` split would need, without
/// introducing multi-tenancy itself.
class Restaurant {
  final String id;
  final String name;
  final String defaultLanguageCode;
  final List<String> supportedLanguageCodes;
  final bool isActive;

  const Restaurant({
    required this.id,
    required this.name,
    required this.defaultLanguageCode,
    required this.supportedLanguageCodes,
    required this.isActive,
  });

  Restaurant copyWith({
    String? id,
    String? name,
    String? defaultLanguageCode,
    List<String>? supportedLanguageCodes,
    bool? isActive,
  }) {
    return Restaurant(
      id: id ?? this.id,
      name: name ?? this.name,
      defaultLanguageCode: defaultLanguageCode ?? this.defaultLanguageCode,
      supportedLanguageCodes:
          supportedLanguageCodes ?? this.supportedLanguageCodes,
      isActive: isActive ?? this.isActive,
    );
  }
}
