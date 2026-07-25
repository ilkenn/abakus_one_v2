import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/development_local_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/domain/models/otp_challenge.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/otp_provider.dart';

class _FakeSessionStorage implements SessionStorage {
  AuthSession? stored;

  @override
  Future<AuthSession?> readSession() async => stored;

  @override
  Future<void> writeSession(AuthSession session) async {
    stored = session;
  }

  @override
  Future<void> clearSession() async {
    stored = null;
  }
}

void main() {
  late ProviderContainer container;

  setUp(() async {
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          DevelopmentLocalAuthRepository(sessionStorage: _FakeSessionStorage()),
        ),
      ],
    );
    addTearDown(container.dispose);
    // otpProvider is `.autoDispose` (see the fix this file now regression-
    // tests) — a bare `.read()` with no listener is eligible for immediate
    // disposal, which would reset state between statements within a single
    // test. A dummy `listen` keeps this test's instance alive for the
    // duration of the test, exactly like a real OtpScreen watching it would.
    container.listen(otpProvider, (previous, next) {});
    await container.read(authProvider.notifier).requestOtp('5321234567');
  });

  test('OTP ekrani acildiginda cooldown repository suresiyle baslar', () {
    final cooldown = container.read(otpProvider).cooldownSeconds;
    expect(
      cooldown,
      DevelopmentLocalAuthRepository.resendCooldown.inSeconds,
    );
  });

  test('cooldown sirasinda resend yeni istek gondermez', () async {
    await container.read(otpProvider.notifier).resend();

    // pendingPhoneNumber degismedi cunku resend no-op oldu (cooldown aktif).
    expect(container.read(authProvider).pendingPhoneNumber, '+905321234567');
    // Ikinci bir requestOtp cagrisi yapilmadigi icin cooldown ayni kaldi.
    expect(container.read(otpProvider).cooldownSeconds, greaterThan(0));
  });

  test(
      '6 haneden kisa kod ile submit repository\'ye gitmez, ekran hatasi gosterir',
      () async {
    container.read(otpProvider.notifier).updateEnteredCode('123');

    final result = await container.read(otpProvider.notifier).submit();

    expect(result, isNull);
    expect(container.read(otpProvider).screenError, isNotNull);
  });

  test('dogru development kodu ile submit basarili sonuc doner', () async {
    container.read(otpProvider.notifier).updateEnteredCode(
          DevelopmentLocalAuthRepository.developmentOtpCode,
        );

    final result = await container.read(otpProvider.notifier).submit();

    expect(container.read(authProvider).isAuthenticated, isTrue);
    expect(result, OtpVerificationResult.success);
  });

  test('yanlis kod ile submit ekran hatasi gosterir', () async {
    container.read(otpProvider.notifier).updateEnteredCode('000000');

    await container.read(otpProvider.notifier).submit();

    expect(container.read(otpProvider).screenError, isNotNull);
    expect(container.read(authProvider).isAuthenticated, isFalse);
  });
}
