import 'localization_scope_type.dart';
import 'supported_language.dart';

/// Which languages are enabled, and which is the fallback, for one
/// [LocalizationScopeType]/scope id pair — Phase 6N
/// (`docs/decisions.md` ADR-023). Mutable registry entity, mirroring
/// `Branch`/`StaffMember`: current shape is what matters, not a
/// revision history of it.
class LocalizationConfig {
  const LocalizationConfig({
    required this.id,
    required this.scopeType,
    required this.scopeId,
    this.enabledLanguages = const {SupportedLanguage.tr},
    this.fallbackLanguage = SupportedLanguage.tr,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final LocalizationScopeType scopeType;
  final String scopeId;

  /// [SupportedLanguage.tr] (the master language) is always a member —
  /// `SetLanguageEnabled` refuses to remove it.
  final Set<SupportedLanguage> enabledLanguages;

  /// Must always be a member of [enabledLanguages] —
  /// `SetLanguageEnabled`/`SetFallbackLanguage` both enforce this.
  final SupportedLanguage fallbackLanguage;

  final DateTime createdAt;
  final int revision;

  LocalizationConfig copyWith({
    Set<SupportedLanguage>? enabledLanguages,
    SupportedLanguage? fallbackLanguage,
    required int revision,
  }) {
    return LocalizationConfig(
      id: id,
      scopeType: scopeType,
      scopeId: scopeId,
      enabledLanguages: enabledLanguages ?? this.enabledLanguages,
      fallbackLanguage: fallbackLanguage ?? this.fallbackLanguage,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
