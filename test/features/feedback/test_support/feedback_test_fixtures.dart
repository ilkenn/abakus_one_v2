import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorization_policy.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorized_action.dart';

/// A [PosAuthorizationPolicy] that grants every action — mirrors the CRM
/// feature's own `AllowAllCrmPolicy` test fake.
class AllowAllFeedbackPolicy implements PosAuthorizationPolicy {
  const AllowAllFeedbackPolicy();

  @override
  Future<AuthorizationResult> authorize({
    required PosAuthorizedAction action,
    required String actorStaffId,
    Map<String, String> context = const {},
  }) async =>
      const AuthorizationResult(granted: true);
}

/// A [PosAuthorizationPolicy] that denies every action.
class DenyAllFeedbackPolicy implements PosAuthorizationPolicy {
  const DenyAllFeedbackPolicy();

  @override
  Future<AuthorizationResult> authorize({
    required PosAuthorizedAction action,
    required String actorStaffId,
    Map<String, String> context = const {},
  }) async =>
      const AuthorizationResult(granted: false);
}
