import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abakus_one_v2/app.dart';
import 'package:abakus_one_v2/features/onboarding/presentation/screens/onboarding_screen.dart';

void main() {
  testWidgets(
    'Uygulama baslangic akisi: oturum yok, onboarding tamamlanmamis -> '
    'ilk kare dogrudan OnboardingScreen (splash asamasi yok)',
    (WidgetTester tester) async {
      // Uygulamayı ProviderScope ile ayağa kaldır — gerçek main()'de
      // olduğu gibi, oturum kontrolü bootstrap'ta (runApp'tan önce) zaten
      // çözülmüş kabul edilir; bu testte hiç oturum yok, bu yüzden
      // varsayılan (signed-out) authProvider durumu doğru senaryodur.
      await tester.pumpWidget(const ProviderScope(child: AbakusApp()));
      await tester.pumpAndSettle();

      // İlk kare zaten OnboardingScreen olmalı — ara bir Splash asamasi
      // yok, zamanlayici beklemeye gerek yok.
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(PageView), findsOneWidget);
    },
  );
}
