import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorization_policy.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorized_action.dart';

class AllowAllProfitabilityPolicy implements PosAuthorizationPolicy {
  const AllowAllProfitabilityPolicy();

  @override
  Future<AuthorizationResult> authorize({
    required PosAuthorizedAction action,
    required String actorStaffId,
    Map<String, String> context = const {},
  }) async =>
      const AuthorizationResult(granted: true);
}

class DenyAllProfitabilityPolicy implements PosAuthorizationPolicy {
  const DenyAllProfitabilityPolicy();

  @override
  Future<AuthorizationResult> authorize({
    required PosAuthorizedAction action,
    required String actorStaffId,
    Map<String, String> context = const {},
  }) async =>
      const AuthorizationResult(granted: false);
}
