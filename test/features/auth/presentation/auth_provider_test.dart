import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/development_local_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/domain/models/otp_challenge.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';

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
  late _FakeSessionStorage storage;
  late ProviderContainer container;

  setUp(() {
    storage = _FakeSessionStorage();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          DevelopmentLocalAuthRepository(sessionStorage: storage),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  const validPhoneInput = '5321234567'; // ham 10 hane, kullanici girisi

  test('gecersiz telefon icin requestOtp repository\'ye istek gondermez',
      () async {
    final sent = await container.read(authProvider.notifier).requestOtp('123');

    expect(sent, isFalse);
    expect(container.read(authProvider).error, isNotNull);
    expect(container.read(authProvider).pendingPhoneNumber, isNull);
  });

  test(
      'gecerli telefon icin requestOtp basarili olur ve pendingPhoneNumber ayarlanir',
      () async {
    final sent =
        await container.read(authProvider.notifier).requestOtp(validPhoneInput);

    expect(sent, isTrue);
    expect(container.read(authProvider).pendingPhoneNumber, '+905321234567');
    expect(container.read(authProvider).error, isNull);
  });

  test(
      'OTP dogrulama basarili olunca isAuthenticated true olur ve oturum kaydedilir',
      () async {
    final notifier = container.read(authProvider.notifier);
    await notifier.requestOtp(validPhoneInput);

    final result = await notifier.verifyOtp(
      DevelopmentLocalAuthRepository.developmentOtpCode,
    );

    expect(result, OtpVerificationResult.success);
    expect(container.read(authProvider).isAuthenticated, isTrue);
    expect(container.read(authProvider).session, isNotNull);
    expect(container.read(authProvider).pendingPhoneNumber, isNull);
    expect(storage.stored, isNotNull);
  });

  test('OTP dogrulama basarisiz olunca isAuthenticated false kalir', () async {
    final notifier = container.read(authProvider.notifier);
    await notifier.requestOtp(validPhoneInput);

    final result = await notifier.verifyOtp('000000');

    expect(result, OtpVerificationResult.invalidCode);
    expect(container.read(authProvider).isAuthenticated, isFalse);
  });

  test(
      'kalici gecerli oturum varsa checkPersistedSession isAuthenticated yapar',
      () async {
    storage.stored = AuthSession(
      phoneNumber: '+905321234567',
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );

    await container.read(authProvider.notifier).checkPersistedSession();

    expect(container.read(authProvider).isAuthenticated, isTrue);
  });

  test(
      'oturum yoksa checkPersistedSession sonrasi onboarding/login akisi icin isAuthenticated false kalir',
      () async {
    await container.read(authProvider.notifier).checkPersistedSession();

    expect(container.read(authProvider).isAuthenticated, isFalse);
  });

  test('misafir girisi oturum/telefon numarasi olusturmadan isGuest true yapar',
      () async {
    container.read(authProvider.notifier).loginAsGuest();

    expect(container.read(authProvider).isGuest, isTrue);
    expect(container.read(authProvider).session, isNull);
    expect(storage.stored, isNull);
  });

  test('logout oturumu ve AuthState\'i temizler', () async {
    final notifier = container.read(authProvider.notifier);
    await notifier.requestOtp(validPhoneInput);
    await notifier.verifyOtp(DevelopmentLocalAuthRepository.developmentOtpCode);
    expect(container.read(authProvider).isAuthenticated, isTrue);

    await notifier.logout();

    expect(container.read(authProvider).isAuthenticated, isFalse);
    expect(container.read(authProvider).session, isNull);
    expect(storage.stored, isNull);
  });
}
