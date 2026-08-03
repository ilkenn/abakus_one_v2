import 'package:abakus_one_v2/core/services/feature_flags/feature_flags_service.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorization_policy.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorized_action.dart';

/// A [PosAuthorizationPolicy] that grants every action — mirrors
/// `AllowAllAdminPolicy`.
class AllowAllEntitlementPolicy implements PosAuthorizationPolicy {
  const AllowAllEntitlementPolicy();

  @override
  Future<AuthorizationResult> authorize({
    required PosAuthorizedAction action,
    required String actorStaffId,
    Map<String, String> context = const {},
  }) async =>
      const AuthorizationResult(granted: true);
}

/// A [PosAuthorizationPolicy] that denies every action.
class DenyAllEntitlementPolicy implements PosAuthorizationPolicy {
  const DenyAllEntitlementPolicy();

  @override
  Future<AuthorizationResult> authorize({
    required PosAuthorizedAction action,
    required String actorStaffId,
    Map<String, String> context = const {},
  }) async =>
      const AuthorizationResult(granted: false);
}

/// A configurable [FeatureFlagsService] fixture — [enabledKeys] are
/// `isEnabled` `true`, everything else falls back to [defaultValue].
class FakeFeatureFlagsService implements FeatureFlagsService {
  FakeFeatureFlagsService({this.enabledKeys = const {}});

  final Set<String> enabledKeys;
  bool _isInitialized = false;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize() async => _isInitialized = true;

  @override
  bool isEnabled(String key, {bool defaultValue = false}) =>
      enabledKeys.contains(key) ? true : defaultValue;

  @override
  String getString(String key, {String defaultValue = ''}) => defaultValue;

  @override
  int getInt(String key, {int defaultValue = 0}) => defaultValue;
}
