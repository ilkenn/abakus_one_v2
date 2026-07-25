import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abakus_one_v2/app.dart';
import 'package:abakus_one_v2/features/navigation/presentation/screens/splash_screen.dart';
import 'package:abakus_one_v2/features/navigation/presentation/widgets/splash_abacus_animation.dart';
import 'package:abakus_one_v2/features/onboarding/presentation/screens/onboarding_screen.dart';

void main() {
  testWidgets('Uygulama baslangic akisi ve splash gecis testi', (
    WidgetTester tester,
  ) async {
    // Uygulamayı ProviderScope ile ayağa kaldır
    await tester.pumpWidget(const ProviderScope(child: AbakusApp()));

    // 1. Aşama: İlk açılışta SplashScreen yüklendiğini doğrula
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(SplashAbacusAnimation), findsOneWidget);

    // 2. Aşama: Splash üzerindeki sahneleme dizisini (3 saniye) tetikle ve pump et
    await tester.pump(const Duration(milliseconds: 3000));
    await tester.pumpAndSettle();

    // 3. Aşama: Onboarding ekranına geçiş yapıldığını güvenli widget tipleriyle doğrula
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
  });
}
