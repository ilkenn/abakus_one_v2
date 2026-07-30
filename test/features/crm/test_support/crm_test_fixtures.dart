import 'package:abakus_one_v2/features/crm/domain/segmentation/customer.dart';
import 'package:abakus_one_v2/features/crm/domain/segmentation/customer_category.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorization_policy.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorized_action.dart';

/// A minimal, valid [Customer] for use-case tests that need one without
/// exercising `RegisterCustomer` itself.
Customer buildTestCustomer({
  String id = 'customer-1',
  String displayName = 'Test Müşteri',
  String phoneNumber = '+905551112233',
  CustomerCategory? category,
  String? customCategoryLabel,
  int revision = 1,
}) {
  return Customer(
    id: id,
    displayName: displayName,
    phoneNumber: phoneNumber,
    category: category,
    customCategoryLabel: customCategoryLabel,
    registeredAt: DateTime(2026, 1, 1),
    revision: revision,
  );
}

/// A [PosAuthorizationPolicy] that grants every action — for CRM/Feedback
/// use-case tests that only need authorization to succeed, mirroring the
/// same fake used across the courier feature's own test suite.
class AllowAllCrmPolicy implements PosAuthorizationPolicy {
  const AllowAllCrmPolicy();

  @override
  Future<AuthorizationResult> authorize({
    required PosAuthorizedAction action,
    required String actorStaffId,
    Map<String, String> context = const {},
  }) async =>
      const AuthorizationResult(granted: true);
}

/// A [PosAuthorizationPolicy] that denies every action.
class DenyAllCrmPolicy implements PosAuthorizationPolicy {
  const DenyAllCrmPolicy();

  @override
  Future<AuthorizationResult> authorize({
    required PosAuthorizedAction action,
    required String actorStaffId,
    Map<String, String> context = const {},
  }) async =>
      const AuthorizationResult(granted: false);
}
