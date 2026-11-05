/// The only two languages with real, human-written UI content today
/// (Self-Order QR Faz 1 — `docs/decisions.md` ADR-054). Deliberately a
/// closed enum, not a free-form language-code string: `GuestSession.
/// selectedLanguageCode`/`detectedLanguageCode` stay plain ISO 639-1
/// strings (per `docs/table_qr_architecture.md` §9 — an open, externally
/// standardized set), but the UI layer only ever renders one of these two
/// until a future phase adds real content for another language — showing
/// a flag with no real translation behind it would misrepresent
/// unfinished work as done.
enum GuestLocale { tr, en }

extension GuestLocaleCode on GuestLocale {
  String get languageCode => switch (this) {
        GuestLocale.tr => 'tr',
        GuestLocale.en => 'en',
      };

  String get flagEmoji => switch (this) {
        GuestLocale.tr => '🇹🇷',
        GuestLocale.en => '🇬🇧',
      };
}

/// Maps any ISO 639-1 code (detected from the device, or read back from a
/// stored [GuestSession.selectedLanguageCode]) onto one of the two
/// languages this phase actually has content for. Anything other than
/// `'en'` falls back to `'tr'` — the restaurant's own default language,
/// not an arbitrary choice.
GuestLocale guestLocaleFromLanguageCode(String code) {
  return code.toLowerCase() == 'en' ? GuestLocale.en : GuestLocale.tr;
}
