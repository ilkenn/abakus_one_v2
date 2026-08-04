import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorization_policy.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorized_action.dart';

/// A [PosAuthorizationPolicy] that grants every action — mirrors
/// `AllowAllAdminPolicy`.
class AllowAllBrandingPolicy implements PosAuthorizationPolicy {
  const AllowAllBrandingPolicy();

  @override
  Future<AuthorizationResult> authorize({
    required PosAuthorizedAction action,
    required String actorStaffId,
    Map<String, String> context = const {},
  }) async {
    return const AuthorizationResult(granted: true);
  }
}

class DenyAllBrandingPolicy implements PosAuthorizationPolicy {
  const DenyAllBrandingPolicy();

  @override
  Future<AuthorizationResult> authorize({
    required PosAuthorizedAction action,
    required String actorStaffId,
    Map<String, String> context = const {},
  }) async {
    return const AuthorizationResult(granted: false, reason: 'denied');
  }
}
