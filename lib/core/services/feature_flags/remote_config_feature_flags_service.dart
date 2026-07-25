import '../remote_config/remote_config_service.dart';
import 'feature_flags_keys.dart';
import 'feature_flags_service.dart';

/// The [FeatureFlagsService] implementation backed by [RemoteConfigService].
///
/// This is the only file in the codebase allowed to know that a feature
/// flag happens to be backed by remote config today — everywhere else
/// (UI, routing, business logic) talks to [FeatureFlagsService] and
/// [FeatureFlagsKeys] only, never to [RemoteConfigService] or
/// `RemoteConfigKeys` directly. The mapping from a public
/// [FeatureFlagsKeys] name to the underlying remote-config parameter key
/// is intentionally private to this file (see [_remoteConfigKeyFor]) —
/// no other file has any reason to know those key strings.
///
/// Not vendor-specific: this class depends only on the abstract
/// [RemoteConfigService] interface, so it behaves identically whether
/// that interface is backed by `NoOpRemoteConfigService` (today) or a
/// real vendor (once one is wired) — swapping the vendor later never
/// requires touching this class.
class RemoteConfigFeatureFlagsService implements FeatureFlagsService {
  const RemoteConfigFeatureFlagsService(this._remoteConfig);

  final RemoteConfigService _remoteConfig;

  static const Map<String, String> _remoteConfigKeyByFlag = {
    FeatureFlagsKeys.loyalty: 'loyalty_enabled',
    FeatureFlagsKeys.campaigns: 'campaigns_enabled',
    FeatureFlagsKeys.reservations: 'reservations_enabled',
    FeatureFlagsKeys.delivery: 'delivery_enabled',
    FeatureFlagsKeys.qr: 'qr_enabled',
    FeatureFlagsKeys.customBowl: 'custom_bowl_enabled',
  };

  @override
  Future<void> initialize() => _remoteConfig.initialize();

  @override
  bool isEnabled(String key, {bool defaultValue = false}) {
    final remoteConfigKey = _remoteConfigKeyByFlag[key];
    if (remoteConfigKey == null) {
      // An unrecognized flag name is never a crash — treated exactly like
      // remote config not having fetched a value yet: fall back to the
      // caller's stated default.
      return defaultValue;
    }
    return _remoteConfig.getBool(remoteConfigKey, defaultValue: defaultValue);
  }
}
