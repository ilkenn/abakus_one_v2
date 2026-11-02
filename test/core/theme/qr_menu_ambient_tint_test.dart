import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/theme/qr_menu_theme.dart';

void main() {
  group('QrMenuAmbientTint.forHour', () {
    test('gunduz saatlerinde (05:00-17:59) temel paleti degismeden dondurur',
        () {
      for (final hour in [5, 9, 12, 17]) {
        final palette = QrMenuAmbientTint.forHour(hour);
        expect(palette.background, QrMenuColors.background,
            reason: 'hour=$hour');
        expect(palette.primary, QrMenuColors.primary, reason: 'hour=$hour');
        expect(palette.accent, QrMenuColors.gold, reason: 'hour=$hour');
      }
    });

    test('18:00 ve sonrasinda daha sicak/koyu bir palet doner', () {
      for (final hour in [18, 20, 23]) {
        final palette = QrMenuAmbientTint.forHour(hour);
        expect(palette, isNot(equals(_daytime)), reason: 'hour=$hour');
        expect(palette.background, isNot(QrMenuColors.background));
        expect(palette.primary, isNot(QrMenuColors.primary));
        expect(palette.accent, isNot(QrMenuColors.gold));
      }
    });

    test('gece yarisindan sabah 05:00ye kadar da aksam paleti gecerlidir', () {
      for (final hour in [0, 2, 4]) {
        final palette = QrMenuAmbientTint.forHour(hour);
        expect(palette, isNot(equals(_daytime)), reason: 'hour=$hour');
      }
    });

    test('saat 5 tam olarak gunduz paletine doner (sinir degeri)', () {
      expect(QrMenuAmbientTint.forHour(5), equals(_daytime));
    });

    test('saat 18 tam olarak aksam paletine gecer (sinir degeri)', () {
      expect(QrMenuAmbientTint.forHour(18), isNot(equals(_daytime)));
    });

    test('ayni saat icin her zaman ayni sonucu dondurur (saf fonksiyon)', () {
      final a = QrMenuAmbientTint.forHour(21);
      final b = QrMenuAmbientTint.forHour(21);
      expect(a, equals(b));
    });

    test('gecersiz saat degeri assertion firlatir', () {
      expect(
          () => QrMenuAmbientTint.forHour(24), throwsA(isA<AssertionError>()));
      expect(
          () => QrMenuAmbientTint.forHour(-1), throwsA(isA<AssertionError>()));
    });
  });
}

const _daytime = QrMenuAmbientPalette(
  background: QrMenuColors.background,
  primary: QrMenuColors.primary,
  accent: QrMenuColors.gold,
);
