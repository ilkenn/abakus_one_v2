import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/app.dart';
import 'package:abakus_one_v2/bootstrap/firebase_ready_provider.dart';
import 'package:abakus_one_v2/features/onboarding/presentation/screens/onboarding_screen.dart';

/// Proves the app still reaches its expected initial shell — directly
/// `OnboardingScreen`, no intermediate splash stage — when Firebase
/// bootstrap has failed (`firebaseReadyProvider` overridden to `false`,
/// exactly as `main()` would set it after
/// `FirebaseBootstrapService.initialize()` returns `false`). Nothing about
/// Onboarding/routing depends on Firebase today, so a failed bootstrap
/// must be invisible to this flow.
void main() {
  testWidgets(
    'Firebase bootstrap basarisiz olsa bile uygulama kabuğu normal '
    'sekilde acilir (degraded boot), splash asamasi olmadan',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [firebaseReadyProvider.overrideWithValue(false)],
          child: const AbakusApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsOneWidget);
    },
  );
}
