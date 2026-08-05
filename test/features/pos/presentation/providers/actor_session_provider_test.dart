import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorized_action.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/real_pos_authorization_policy.dart'
    show kRestaurantIdAuthorizationContextKey;
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/actor_session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('actorSessionProvider / posAuthorizationPolicyProvider wiring', () {
    test('defaults to no active session, denying by default', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(actorSessionProvider), isNull);

      final policy = container.read(posAuthorizationPolicyProvider);
      final result = await policy.authorize(
        action: PosAuthorizedAction.acknowledgeKitchenItem,
        actorStaffId: 'staff-1',
      );

      expect(result.granted, isFalse);
    });

    test('setting a session takes effect on the very next check', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final policy = container.read(posAuthorizationPolicyProvider);

      container.read(actorSessionProvider.notifier).state = const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
      );

      final result = await policy.authorize(
        action: PosAuthorizedAction.manageVisitRewardRules,
        actorStaffId: 'manager-1',
      );

      expect(result.granted, isTrue);
    });

    test(
        'resolves the seeded restaurant-1 to org-1 for real (Phase 9 '
        'wiring regression) — an admin without org-1 access is still '
        'denied a restaurant-scoped action', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(actorSessionProvider.notifier).state = const ActorSession(
        actorId: 'admin-1',
        roles: {StaffRole.admin},
        activeRole: StaffRole.admin,
        // Deliberately no organizationAccess.
      );

      final policy = container.read(posAuthorizationPolicyProvider);
      final result = await policy.authorize(
        action: PosAuthorizedAction.manageOrganization,
        actorStaffId: 'admin-1',
        context: const {
          kRestaurantIdAuthorizationContextKey: 'restaurant-1',
        },
      );

      expect(result.granted, isFalse);
      expect(result.reason, contains('org-1'));
    });

    test(
        'resolves the seeded restaurant-1 to org-1 for real — an admin '
        'granted org-1 access is allowed a restaurant-scoped action', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(actorSessionProvider.notifier).state = const ActorSession(
        actorId: 'admin-1',
        roles: {StaffRole.admin},
        activeRole: StaffRole.admin,
        organizationAccess: {'org-1'},
      );

      final policy = container.read(posAuthorizationPolicyProvider);
      final result = await policy.authorize(
        action: PosAuthorizedAction.manageOrganization,
        actorStaffId: 'admin-1',
        context: const {
          kRestaurantIdAuthorizationContextKey: 'restaurant-1',
        },
      );

      expect(result.granted, isTrue);
    });
  });
}
