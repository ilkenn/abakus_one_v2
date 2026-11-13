import 'package:abakus_one_v2/features/auth/data/repositories/auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/firebase_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/domain/staff_login_email.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../core/services/auth/fake_firebase_auth_client.dart';

/// ADR-085 (revision) — staff phone + password sign-in and own password
/// change, through the real `AuthNotifier` + `FirebaseAuthRepository` over
/// a fake Firebase client.
class _MemorySessionStorage implements SessionStorage {
  AuthSession? stored;
  @override
  Future<AuthSession?> readSession() async => stored;
  @override
  Future<void> writeSession(AuthSession session) async => stored = session;
  @override
  Future<void> clearSession() async => stored = null;
}

const _email = '905321234567@staff-login.abakus.invalid';

({ProviderContainer container, FakeFirebaseAuthClient client}) _setUp() {
  final client = FakeFirebaseAuthClient()
    ..passwordsByEmail[_email] = 'dogru-sifre-123';
  final container = ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(FirebaseAuthRepository(
      client: client,
      sessionStorage: _MemorySessionStorage(),
    )),
  ]);
  addTearDown(container.dispose);
  return (container: container, client: client);
}

void main() {
  test('the hidden sign-in e-mail matches the server derivation', () {
    expect(staffLoginEmailForPhone('+905321234567'), _email);
  });

  test('a correct phone + password signs in to a customer session', () async {
    final (:container, client: _) = _setUp();

    final result = await container
        .read(authProvider.notifier)
        .signInWithPassword('5321234567', 'dogru-sifre-123');

    expect(result, PasswordSignInResult.success);
    final state = container.read(authProvider);
    expect(state.isAuthenticated, isTrue);
    expect(state.session?.phoneNumber, '+905321234567');
    expect(state.error, isNull);
  });

  test('a wrong password and an unknown number fail with one message',
      () async {
    final (:container, client: _) = _setUp();
    final notifier = container.read(authProvider.notifier);

    for (final phone in ['5321234567', '5329999999']) {
      final result = await notifier.signInWithPassword(phone, 'yanlis');
      expect(result, PasswordSignInResult.invalidCredentials, reason: phone);
      expect(container.read(authProvider).isAuthenticated, isFalse);
      expect(container.read(authProvider).error,
          'Telefon numarası veya şifre hatalı.');
    }
  });

  test('an invalid phone number never reaches the repository', () async {
    final (:container, client: _) = _setUp();

    final result = await container
        .read(authProvider.notifier)
        .signInWithPassword('123', 'dogru-sifre-123');

    expect(result, PasswordSignInResult.invalidCredentials);
    expect(container.read(authProvider).error,
        'Lütfen geçerli bir telefon numarası girin.');
  });

  test('a signed-in staff member changes their own password', () async {
    final (:container, :client) = _setUp();
    final notifier = container.read(authProvider.notifier);
    await notifier.signInWithPassword('5321234567', 'dogru-sifre-123');

    expect(
      await notifier.changeOwnPassword(
          currentPassword: 'yanlis', newPassword: 'yeni-sifre-456'),
      PasswordChangeResult.wrongCurrentPassword,
    );
    expect(
      await notifier.changeOwnPassword(
          currentPassword: 'dogru-sifre-123', newPassword: 'kisa'),
      PasswordChangeResult.weakPassword,
    );
    expect(
      await notifier.changeOwnPassword(
          currentPassword: 'dogru-sifre-123', newPassword: 'yeni-sifre-456'),
      PasswordChangeResult.success,
    );
    expect(client.passwordsByEmail[_email], 'yeni-sifre-456');
  });
}
