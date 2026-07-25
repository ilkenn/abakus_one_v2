import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/development_local_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/domain/models/otp_challenge.dart';

/// In-memory [SessionStorage] fake — keeps tests independent of the real
/// `flutter_secure_storage` platform channel, which isn't available under
/// `flutter test`.
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
  late DevelopmentLocalAuthRepository repository;

  setUp(() {
    storage = _FakeSessionStorage();
    repository = DevelopmentLocalAuthRepository(sessionStorage: storage);
  });

  const phoneNumber = '+905321234567';

  test('gecerli telefon icin requestOtp basarili sekilde tamamlanir', () async {
    await repository.requestOtp(phoneNumber);
    // Tamamlandi (exception firlatmadi) - kabul edilebilir bir istektir.
  });

  test('cooldown suresi dolmadan ikinci requestOtp reddedilir', () async {
    await repository.requestOtp(phoneNumber);

    await expectLater(
      repository.requestOtp(phoneNumber),
      throwsA(isA<AuthCooldownActiveException>()),
    );
  });

  test('development kodu ile verifyOtp basarili doner ve oturum kaydeder',
      () async {
    await repository.requestOtp(phoneNumber);

    final result = await repository.verifyOtp(
      phoneNumber: phoneNumber,
      code: DevelopmentLocalAuthRepository.developmentOtpCode,
    );

    expect(result, OtpVerificationResult.success);
    expect(storage.stored, isNotNull);
    expect(storage.stored!.phoneNumber, phoneNumber);
    expect(storage.stored!.isExpired, isFalse);
  });

  test('development kodu disindaki her kod invalidCode doner', () async {
    await repository.requestOtp(phoneNumber);

    final result = await repository.verifyOtp(
      phoneNumber: phoneNumber,
      code: '000000',
    );

    expect(result, OtpVerificationResult.invalidCode);
    expect(storage.stored, isNull);
  });

  test('hic OTP istenmemis numara icin verifyOtp expired doner', () async {
    final result = await repository.verifyOtp(
      phoneNumber: phoneNumber,
      code: DevelopmentLocalAuthRepository.developmentOtpCode,
    );

    expect(result, OtpVerificationResult.expired);
  });

  test('loadSession suresi dolmus oturumu temizler ve null doner', () async {
    storage.stored = AuthSession(
      phoneNumber: phoneNumber,
      createdAt: DateTime.now().subtract(const Duration(days: 31)),
      expiresAt: DateTime.now().subtract(const Duration(days: 1)),
    );

    final session = await repository.loadSession();

    expect(session, isNull);
    expect(storage.stored, isNull);
  });

  test('loadSession gecerli oturumu doner', () async {
    final validSession = AuthSession(
      phoneNumber: phoneNumber,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
    storage.stored = validSession;

    final session = await repository.loadSession();

    expect(session, isNotNull);
    expect(session!.phoneNumber, phoneNumber);
  });

  test('clearSession depolamayi temizler', () async {
    storage.stored = AuthSession(
      phoneNumber: phoneNumber,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );

    await repository.clearSession();

    expect(storage.stored, isNull);
  });
}
