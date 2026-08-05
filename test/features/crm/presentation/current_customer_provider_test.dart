import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/crm/presentation/providers/crm_dependencies_provider.dart';
import 'package:abakus_one_v2/features/crm/presentation/providers/current_customer_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SignedInNotifier extends AuthNotifier {
  _SignedInNotifier(this.uid, this.phoneNumber);
  final String uid;
  final String phoneNumber;

  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        isGuest: false,
        session: AuthSession(
          uid: uid,
          phoneNumber: phoneNumber,
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
  group('currentCustomerProvider', () {
    test('resolves null when signed out', () async {
      final container = ProviderContainer(
        overrides: [authProvider.overrideWith(() => _SignedOutNotifier())],
      );
      addTearDown(container.dispose);

      final customer = await container.read(currentCustomerProvider.future);

      expect(customer, isNull);
    });

    test(
        'resolves a real Customer for a signed-in session, keyed by the '
        'canonical uid', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider
              .overrideWith(() => _SignedInNotifier('uid-1', '+905559998877')),
        ],
      );
      addTearDown(container.dispose);

      final customer = await container.read(currentCustomerProvider.future);

      expect(customer, isNotNull);
      expect(customer!.id, 'uid-1');
      expect(customer.phoneNumber, '+905559998877');
    });

    test(
        'resolving twice for the same session returns the same customer '
        'id — idempotent, not a new registration each time', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider
              .overrideWith(() => _SignedInNotifier('uid-1', '+905559998877')),
        ],
      );
      addTearDown(container.dispose);

      final first = await container.read(currentCustomerProvider.future);
      container.invalidate(currentCustomerProvider);
      final second = await container.read(currentCustomerProvider.future);

      expect(second!.id, first!.id);
      expect(await container.read(customerRepositoryProvider).findAll(),
          hasLength(1));
    });
  });
}
