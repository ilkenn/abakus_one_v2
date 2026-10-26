import 'package:abakus_one_v2/features/auth/data/repositories/auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/firebase_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/domain/models/otp_challenge.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/services/auth/fake_firebase_auth_client.dart';

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
  const phoneNumber = '+905321234567';
  late _FakeSessionStorage storage;
  late FakeFirebaseAuthClient client;
  late FirebaseAuthRepository repository;

  setUp(() {
    storage = _FakeSessionStorage();
    client = FakeFirebaseAuthClient(validSmsCode: '654321');
    repository = FirebaseAuthRepository(
      client: client,
      sessionStorage: storage,
    );
  });

  test('requestOtp calls the client and succeeds', () async {
    await repository.requestOtp(phoneNumber);
    expect(client.verifyCallCount, 1);
  });

  test('requestOtp maps a client rejection to AuthServiceUnavailableException',
      () async {
    client.throwOnVerify = true;
    await expectLater(
      repository.requestOtp(phoneNumber),
      throwsA(isA<AuthServiceUnavailableException>()),
    );
  });

  test('a second requestOtp before the cooldown elapses is rejected', () async {
    await repository.requestOtp(phoneNumber);
    await expectLater(
      repository.requestOtp(phoneNumber),
      throwsA(isA<AuthCooldownActiveException>()),
    );
  });

  test(
      'verifyOtp with the right code succeeds and persists a session with '
      'the real Firebase uid', () async {
    await repository.requestOtp(phoneNumber);

    final result = await repository.verifyOtp(
      phoneNumber: phoneNumber,
      code: client.validSmsCode,
    );

    expect(result, OtpVerificationResult.success);
    expect(storage.stored, isNotNull);
    expect(storage.stored!.uid, 'fake-phone-uid-$phoneNumber');
    expect(storage.stored!.phoneNumber, phoneNumber);
  });

  test('verifyOtp with the wrong code returns invalidCode, no session saved',
      () async {
    await repository.requestOtp(phoneNumber);

    final result =
        await repository.verifyOtp(phoneNumber: phoneNumber, code: '000000');

    expect(result, OtpVerificationResult.invalidCode);
    expect(storage.stored, isNull);
  });

  test('verifyOtp with no prior requestOtp returns expired', () async {
    final result = await repository.verifyOtp(
      phoneNumber: phoneNumber,
      code: client.validSmsCode,
    );

    expect(result, OtpVerificationResult.expired);
  });

  test('clearSession signs out of the Firebase client and clears storage',
      () async {
    storage.stored = AuthSession(
      uid: 'firebase-uid-1',
      phoneNumber: phoneNumber,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );

    await repository.clearSession();

    expect(client.signOutCalled, isTrue);
    expect(storage.stored, isNull);
  });

  test('loadSession returns null and clears storage for an expired session',
      () async {
    storage.stored = AuthSession(
      uid: 'firebase-uid-1',
      phoneNumber: phoneNumber,
      createdAt: DateTime.now().subtract(const Duration(days: 31)),
      expiresAt: DateTime.now().subtract(const Duration(days: 1)),
    );

    final session = await repository.loadSession();

    expect(session, isNull);
    expect(storage.stored, isNull);
  });
}
