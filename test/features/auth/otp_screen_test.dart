import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/development_local_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/otp_screen.dart';
import 'package:abakus_one_v2/features/navigation/presentation/screens/main_navigation_screen.dart';

class _FakeSessionStorage implements SessionStorage {
  AuthSession? stored;
  @override
  Future<AuthSession?> readSession() async => stored;
  @override
  Future<void> writeSession(AuthSession session) async => stored = session;
  @override
  Future<void> clearSession() async => stored = null;
}

/// Reaches OtpScreen the same way a real user would: through LoginScreen,
/// so `AuthState.pendingPhoneNumber` is genuinely set by the flow rather
/// than injected directly.
Future<void> _pumpOtpScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          DevelopmentLocalAuthRepository(
            sessionStorage: _FakeSessionStorage(),
          ),
        ),
      ],
      child: const MaterialApp(home: LoginScreen()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField), '5321234567');
  await tester.tap(find.text('OTP Gönder'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('gelistirme kodu ipucu metni gosterilir', (tester) async {
    await _pumpOtpScreen(tester);

    expect(
      find.text(
        'Geliştirme kodu: ${DevelopmentLocalAuthRepository.developmentOtpCode}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('yeniden gonder butonu baslangicta cooldown ile pasiftir', (
    tester,
  ) async {
    await _pumpOtpScreen(tester);

    expect(
      find.textContaining('Yeniden gönder ('),
      findsOneWidget,
    );
  });

  testWidgets(
      'yanlis kod hata mesaji gosterir ve MainNavigationScreen\'e gecmez', (
    tester,
  ) async {
    await _pumpOtpScreen(tester);

    await tester.enterText(find.byType(TextField), '000000');
    await tester.tap(find.text('Doğrula'));
    await tester.pumpAndSettle();

    expect(find.text('Girdiğiniz kod hatalı. Lütfen tekrar deneyin.'),
        findsOneWidget);
    expect(find.byType(MainNavigationScreen), findsNothing);
  });

  testWidgets(
    'dogru gelistirme kodu MainNavigationScreen\'e gecer ve stack\'i temizler',
    (tester) async {
      await _pumpOtpScreen(tester);

      await tester.enterText(
        find.byType(TextField),
        DevelopmentLocalAuthRepository.developmentOtpCode,
      );
      await tester.tap(find.text('Doğrula'));
      await tester.pumpAndSettle();

      expect(find.byType(MainNavigationScreen), findsOneWidget);
      expect(find.byType(OtpScreen), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
    },
  );

  testWidgets('Telefon numarasini degistir LoginScreen\'e geri doner', (
    tester,
  ) async {
    await _pumpOtpScreen(tester);

    await tester.tap(find.text('Telefon numarasını değiştir'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
