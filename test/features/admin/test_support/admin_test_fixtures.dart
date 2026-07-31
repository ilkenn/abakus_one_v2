import 'package:abakus_one_v2/features/admin/domain/staff/staff_member.dart';
import 'package:abakus_one_v2/features/admin/domain/staff/staff_member_status.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorization_policy.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorized_action.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';

/// A minimal, valid [StaffMember] for use-case tests that need one
/// without exercising `RegisterStaffMember` itself.
StaffMember buildTestStaffMember({
  String id = 'staff-member-1',
  String displayName = 'Test Personel',
  Set<StaffRole> roles = const {},
  Set<String> branchAccess = const {},
  Set<String> restaurantAccess = const {},
  StaffMemberStatus status = StaffMemberStatus.active,
  DateTime? sessionsRevokedAt,
  int revision = 1,
}) {
  return StaffMember(
    id: id,
    displayName: displayName,
    roles: roles,
    branchAccess: branchAccess,
    restaurantAccess: restaurantAccess,
    status: status,
    sessionsRevokedAt: sessionsRevokedAt,
    createdAt: DateTime(2026, 1, 1),
    revision: revision,
  );
}

/// A [PosAuthorizationPolicy] that grants every action — mirrors
/// `AllowAllCrmPolicy`.
class AllowAllAdminPolicy implements PosAuthorizationPolicy {
  const AllowAllAdminPolicy();

  @override
  Future<AuthorizationResult> authorize({
    required PosAuthorizedAction action,
    required String actorStaffId,
    Map<String, String> context = const {},
  }) async =>
      const AuthorizationResult(granted: true);
}

/// A [PosAuthorizationPolicy] that denies every action.
class DenyAllAdminPolicy implements PosAuthorizationPolicy {
  const DenyAllAdminPolicy();

  @override
  Future<AuthorizationResult> authorize({
    required PosAuthorizedAction action,
    required String actorStaffId,
    Map<String, String> context = const {},
  }) async =>
      const AuthorizationResult(granted: false);
}
