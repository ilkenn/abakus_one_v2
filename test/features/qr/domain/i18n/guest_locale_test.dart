import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/qr/domain/i18n/guest_locale.dart';

void main() {
  group('guestLocaleFromLanguageCode', () {
    test('en maps to GuestLocale.en', () {
      expect(guestLocaleFromLanguageCode('en'), GuestLocale.en);
    });

    test('EN (uppercase) also maps to GuestLocale.en — case-insensitive', () {
      expect(guestLocaleFromLanguageCode('EN'), GuestLocale.en);
    });

    test('tr maps to GuestLocale.tr', () {
      expect(guestLocaleFromLanguageCode('tr'), GuestLocale.tr);
    });

    test('any other code (no real content yet) falls back to tr, not en', () {
      expect(guestLocaleFromLanguageCode('de'), GuestLocale.tr);
      expect(guestLocaleFromLanguageCode('ru'), GuestLocale.tr);
      expect(guestLocaleFromLanguageCode('ar'), GuestLocale.tr);
      expect(guestLocaleFromLanguageCode(''), GuestLocale.tr);
    });
  });

  group('GuestLocaleCode extension', () {
    test('languageCode round-trips through guestLocaleFromLanguageCode', () {
      for (final locale in GuestLocale.values) {
        expect(guestLocaleFromLanguageCode(locale.languageCode), locale);
      }
    });

    test('each locale has a distinct flag emoji', () {
      final emojis = GuestLocale.values.map((l) => l.flagEmoji).toSet();
      expect(emojis.length, GuestLocale.values.length);
    });
  });
}
