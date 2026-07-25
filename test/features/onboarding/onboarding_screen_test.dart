import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/development_local_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/navigation/presentation/screens/main_navigation_screen.dart';
import 'package:abakus_one_v2/features/onboarding/presentation/screens/onboarding_screen.dart';

class _FakeSessionStorage implements SessionStorage {
  AuthSession? stored;
  @override
  Future<AuthSession?> readSession() async => stored;
  @override
  Future<void> writeSession(AuthSession session) async => stored = session;
  @override
  Future<void> clearSession() async => stored = null;
}

void main() {
  testWidgets(
    'Onboarding tamamlaninca MainNavigationScreen degil LoginScreen acilir',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              DevelopmentLocalAuthRepository(
                sessionStorage: _FakeSessionStorage(),
              ),
            ),
          ],
          child: const MaterialApp(home: OnboardingScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Atla'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(MainNavigationScreen), findsNothing);
    },
  );
}
