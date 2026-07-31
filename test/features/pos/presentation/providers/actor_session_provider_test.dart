import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorized_action.dart';
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
  });
}
