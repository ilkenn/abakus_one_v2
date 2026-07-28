import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorized_action.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_pos_authorization_policy.dart';

void main() {
  group('FakePosAuthorizationPolicy', () {
    test('returns exactly the injected result, and never invents one', () async {
      final policy = FakePosAuthorizationPolicy(
        const AuthorizationResult(granted: true, requiresManagerApproval: false),
      );

      final result = await policy.authorize(
        action: PosAuthorizedAction.reopenOrder,
        actorStaffId: 'staff-1',
      );

      expect(result.granted, isTrue);
      expect(policy.callCount, 1);
      expect(policy.lastAction, PosAuthorizedAction.reopenOrder);
      expect(policy.lastActorStaffId, 'staff-1');
    });

    test('a denial is reported as denial, not silently treated as granted', () async {
      final policy = FakePosAuthorizationPolicy(
        const AuthorizationResult(granted: false, reason: 'Not a manager'),
      );

      final result = await policy.authorize(
        action: PosAuthorizedAction.voidPayment,
        actorStaffId: 'staff-2',
      );

      expect(result.granted, isFalse);
      expect(result.reason, 'Not a manager');
    });
  });
}
