import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/development_local_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/navigation/presentation/screens/main_navigation_screen.dart';
import 'package:abakus_one_v2/features/navigation/presentation/screens/splash_screen.dart';
import 'package:abakus_one_v2/features/onboarding/presentation/provider/onboarding_provider.dart';

class _FakeSessionStorage implements SessionStorage {
  AuthSession? stored;
  _FakeSessionStorage({this.stored});
  @override
  Future<AuthSession?> readSession() async => stored;
  @override
  Future<void> writeSession(AuthSession session) async => stored = session;
  @override
  Future<void> clearSession() async => stored = null;
}

class _CompletedOnboardingNotifier extends OnboardingCompleteNotifier {
  @override
  bool build() => true;
}

void main() {
  testWidgets(
    'kalici gecerli oturum varsa Splash MainNavigationScreen\'e gecer',
    (tester) async {
      final storage = _FakeSessionStorage(
        stored: AuthSession(
          phoneNumber: '+905321234567',
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(days: 1)),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              DevelopmentLocalAuthRepository(sessionStorage: storage),
            ),
          ],
          child: const MaterialApp(home: SplashScreen()),
        ),
      );

      await tester.pump(const Duration(milliseconds: 3000));
      await tester.pumpAndSettle();

      expect(find.byType(MainNavigationScreen), findsOneWidget);
      expect(find.byType(SplashScreen), findsNothing);
    },
  );

  testWidgets(
    'onboarding tamamlanmis ama oturum yoksa Splash LoginScreen\'e gecer',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              DevelopmentLocalAuthRepository(
                sessionStorage: _FakeSessionStorage(),
              ),
            ),
            onboardingCompleteProvider.overrideWith(
              _CompletedOnboardingNotifier.new,
            ),
          ],
          child: const MaterialApp(home: SplashScreen()),
        ),
      );

      await tester.pump(const Duration(milliseconds: 3000));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(MainNavigationScreen), findsNothing);
    },
  );
}
