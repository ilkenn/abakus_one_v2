/// A brand under an [Organization] — resurrects
/// `lib/shared/models/restaurant.dart`'s shape (which existed but had
/// zero repository/provider/call site anywhere — confirmed dead code
/// before Phase 6) as a real, repository-backed registry entity, additive
/// only (an [organizationId] reference is the one new field).
class Restaurant {
  const Restaurant({
    required this.id,
    required this.organizationId,
    required this.name,
    this.defaultLanguageCode = 'tr',
    this.supportedLanguageCodes = const ['tr'],
    this.isActive = true,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final String name;
  final String defaultLanguageCode;
  final List<String> supportedLanguageCodes;
  final bool isActive;
  final DateTime createdAt;
  final int revision;

  Restaurant copyWith({
    String? name,
    String? defaultLanguageCode,
    List<String>? supportedLanguageCodes,
    bool? isActive,
    required int revision,
  }) {
    return Restaurant(
      id: id,
      organizationId: organizationId,
      name: name ?? this.name,
      defaultLanguageCode: defaultLanguageCode ?? this.defaultLanguageCode,
      supportedLanguageCodes:
          supportedLanguageCodes ?? this.supportedLanguageCodes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
