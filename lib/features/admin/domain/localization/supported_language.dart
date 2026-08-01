/// The Admin Platform's default supported language set — Phase 6N
/// (`docs/decisions.md` ADR-023). [tr] is the **master language**
/// (`docs/business_rules.md` — "Master language Turkish (tr)") — fixed,
/// not admin-configurable, always enabled, and never itself disableable
/// (see `SetLanguageEnabled`).
enum SupportedLanguage {
  tr,
  en,
  ru,
  de,
  ar,
  es,
  fr;

  /// The one master language this codebase is built around — a
  /// constant, not stored data, since it is never meant to change.
  static const SupportedLanguage master = SupportedLanguage.tr;

  /// Right-to-left script — only [ar] today. Pure metadata: no RTL
  /// layout logic reads this yet (customer-facing localization/RTL
  /// support is separate, later work — this only records the fact for
  /// admin display and any future consumer).
  bool get isRtl => this == SupportedLanguage.ar;

  String get nativeLabel => switch (this) {
        SupportedLanguage.tr => 'Türkçe',
        SupportedLanguage.en => 'English',
        SupportedLanguage.ru => 'Русский',
        SupportedLanguage.de => 'Deutsch',
        SupportedLanguage.ar => 'العربية',
        SupportedLanguage.es => 'Español',
        SupportedLanguage.fr => 'Français',
      };
}
