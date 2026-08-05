import 'package:abakus_one_v2/core/account_deletion/domain/account_deletion_request.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/profile/presentation/providers/account_data_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SignedInNotifier extends AuthNotifier {
  _SignedInNotifier(this.uid);
  final String uid;

  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        isGuest: false,
        session: AuthSession(
          uid: uid,
          phoneNumber: '+905321234567',
          createdAt: DateTime(2026, 1, 1),
          expiresAt: DateTime(2026, 12, 31),
        ),
      );
}

class _SignedOutNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState(isAuthenticated: false, isGuest: false);
}

void main() {
  group('AccountDataNotifier.requestAccountDeletion (Sprint 9G, ADR-026)', () {
    test('creates a real coolingOff request for the signed-in uid', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _SignedInNotifier('uid-1')),
        ],
      );
      addTearDown(container.dispose);

      final success = await container
          .read(accountDataProvider.notifier)
          .requestAccountDeletion();

      expect(success, isTrue);
      final request = container.read(accountDataProvider).deletionRequest;
      expect(request, isNotNull);
      expect(request!.uid, 'uid-1');
      expect(request.status, AccountDeletionStatus.coolingOff);
    });

    test('does nothing and returns false when signed out', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _SignedOutNotifier()),
        ],
      );
      addTearDown(container.dispose);

      final success = await container
          .read(accountDataProvider.notifier)
          .requestAccountDeletion();

      expect(success, isFalse);
      expect(container.read(accountDataProvider).deletionRequest, isNull);
    });

    test(
        'does not sign the user out — the current session stays valid so '
        'cancellation remains reachable', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _SignedInNotifier('uid-1')),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(accountDataProvider.notifier)
          .requestAccountDeletion();

      expect(container.read(authProvider).isAuthenticated, isTrue);
    });
  });

  group('AccountDataNotifier.cancelAccountDeletion', () {
    test('cancels an active request and updates state', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _SignedInNotifier('uid-1')),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(accountDataProvider.notifier)
          .requestAccountDeletion();

      final success = await container
          .read(accountDataProvider.notifier)
          .cancelAccountDeletion();

      expect(success, isTrue);
      expect(
        container.read(accountDataProvider).deletionRequest?.status,
        AccountDeletionStatus.cancelled,
      );
    });

    test('returns false when there is nothing to cancel', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _SignedInNotifier('uid-1')),
        ],
      );
      addTearDown(container.dispose);

      final success = await container
          .read(accountDataProvider.notifier)
          .cancelAccountDeletion();

      expect(success, isFalse);
    });
  });
}
