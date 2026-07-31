import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/crm/presentation/providers/current_customer_provider.dart';
import 'package:abakus_one_v2/features/profile/presentation/providers/profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SignedInNotifier extends AuthNotifier {
  _SignedInNotifier(this.phoneNumber);
  final String phoneNumber;

  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        isGuest: false,
        session: AuthSession(
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
  group('profileProvider identity bridge (Sprint 5E)', () {
    test('signed out keeps the existing mock profile id unchanged', () {
      final container = ProviderContainer(
        overrides: [authProvider.overrideWith(() => _SignedOutNotifier())],
      );
      addTearDown(container.dispose);

      expect(container.read(profileProvider).id, 'user_123');
    });

    test(
        'a signed-in session derives ProfileModel.id from the same phone '
        'number currentCustomerProvider resolves its Customer from — the '
        'signed-in user, profile, and CRM customer represent the same '
        'person', () async {
      const phoneNumber = '+905551112233';
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _SignedInNotifier(phoneNumber)),
        ],
      );
      addTearDown(container.dispose);

      final profile = container.read(profileProvider);
      final customer = await container.read(currentCustomerProvider.future);

      expect(profile.id, 'customer-$phoneNumber');
      expect(customer!.phoneNumber, phoneNumber);
      // Both are anchored to the exact same real signal (the auth
      // session's phone number) - proving they resolve to the same person,
      // even though the two id strings are not textually identical.
      expect(profile.id, contains(phoneNumber));
      expect(customer.phoneNumber, phoneNumber);
    });

    test(
        'two different signed-in sessions derive two different profile '
        'ids', () {
      final containerA = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _SignedInNotifier('+905550000001')),
        ],
      );
      addTearDown(containerA.dispose);
      final containerB = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _SignedInNotifier('+905550000002')),
        ],
      );
      addTearDown(containerB.dispose);

      expect(
        containerA.read(profileProvider).id,
        isNot(containerB.read(profileProvider).id),
      );
    });
  });
}
