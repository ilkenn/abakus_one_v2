import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/crm/presentation/providers/current_customer_provider.dart';
import 'package:abakus_one_v2/features/profile/presentation/providers/profile_provider.dart';
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
  group('profileProvider canonical identity bridge (Sprint 9C)', () {
    test(
        'signed out returns null — no fabricated guest identity (P.1, '
        '2026-08-19)', () {
      final container = ProviderContainer(
        overrides: [authProvider.overrideWith(() => _SignedOutNotifier())],
      );
      addTearDown(container.dispose);

      expect(container.read(profileProvider), isNull);
    });

    test(
        'a signed-in session sets ProfileModel.id to the same canonical uid '
        'currentCustomerProvider resolves its Customer.id from — the '
        'signed-in user, profile, and CRM customer represent the same '
        'person via one literal shared id', () async {
      const uid = 'uid-abc123';
      const phoneNumber = '+905551112233';
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _SignedInNotifier(uid, phoneNumber)),
        ],
      );
      addTearDown(container.dispose);

      final profile = container.read(profileProvider);
      final customer = await container.read(currentCustomerProvider.future);

      expect(profile, isNotNull);
      expect(profile!.id, uid);
      expect(customer!.id, uid);
      expect(profile.id, customer.id);
      expect(profile.name, phoneNumber);
      expect(profile.email, isEmpty);
    });

    test(
        'two different signed-in sessions derive two different profile '
        'ids', () {
      final containerA = ProviderContainer(
        overrides: [
          authProvider
              .overrideWith(() => _SignedInNotifier('uid-1', '+905550000001')),
        ],
      );
      addTearDown(containerA.dispose);
      final containerB = ProviderContainer(
        overrides: [
          authProvider
              .overrideWith(() => _SignedInNotifier('uid-2', '+905550000002')),
        ],
      );
      addTearDown(containerB.dispose);

      expect(
        containerA.read(profileProvider)!.id,
        isNot(containerB.read(profileProvider)!.id),
      );
    });
  });
}
