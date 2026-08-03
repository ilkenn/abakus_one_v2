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
/// is intentionally private to this file (see [_remoteConfigKeyByFlag]) —
/// no other file has any reason to know those key strings.
///
/// Not vendor-specific: this class depends only on the abstract
/// [RemoteConfigService] interface, so it behaves identically whether
/// that interface is backed by `NoOpRemoteConfigService` or
/// `FirebaseRemoteConfigService` — swapping the vendor never requires
/// touching this class. All Firebase-specific knowledge stays isolated
/// inside `RemoteConfigService`'s Firebase-backed implementation, not
/// here.
class RemoteConfigFeatureFlagsService implements FeatureFlagsService {
  RemoteConfigFeatureFlagsService(this._remoteConfig);

  final RemoteConfigService _remoteConfig;
  bool _isInitialized = false;

  static const Map<String, String> _remoteConfigKeyByFlag = {
    FeatureFlagsKeys.otpLoginEnabled: 'otp_login_enabled',
    FeatureFlagsKeys.bowlBuilderEnabled: 'bowl_builder_enabled',
    FeatureFlagsKeys.fortuneWheelEnabled: 'fortune_wheel_enabled',
    FeatureFlagsKeys.reservationsEnabled: 'reservations_enabled',
    FeatureFlagsKeys.qrScannerEnabled: 'qr_scanner_enabled',
    FeatureFlagsKeys.smartRestaurantSetupEnabled:
        'smart_restaurant_setup_enabled',
    FeatureFlagsKeys.menuImportEnabled: 'menu_import_enabled',
    FeatureFlagsKeys.inventoryEnabled: 'inventory_enabled',
    FeatureFlagsKeys.recipesEnabled: 'recipes_enabled',
    FeatureFlagsKeys.nutritionEnabled: 'nutrition_enabled',
    FeatureFlagsKeys.allergensEnabled: 'allergens_enabled',
    FeatureFlagsKeys.purchasingEnabled: 'purchasing_enabled',
    FeatureFlagsKeys.suppliersEnabled: 'suppliers_enabled',
    FeatureFlagsKeys.costingEnabled: 'costing_enabled',
    FeatureFlagsKeys.profitabilityEnabled: 'profitability_enabled',
    FeatureFlagsKeys.advancedReportingEnabled: 'advanced_reporting_enabled',
  };

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize() async {
    // RemoteConfigService implementations never throw from initialize()
    // (see FirebaseRemoteConfigService) — this await completing is enough
    // to mark this service initialized, even if the underlying fetch
    // itself failed and fell back to defaults.
    await _remoteConfig.initialize();
    _isInitialized = true;
  }

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

  @override
  String getString(String key, {String defaultValue = ''}) {
    final remoteConfigKey = _remoteConfigKeyByFlag[key];
    if (remoteConfigKey == null) return defaultValue;
    return _remoteConfig.getString(
      remoteConfigKey,
      defaultValue: defaultValue,
    );
  }

  @override
  int getInt(String key, {int defaultValue = 0}) {
    final remoteConfigKey = _remoteConfigKeyByFlag[key];
    if (remoteConfigKey == null) return defaultValue;
    return _remoteConfig.getInt(remoteConfigKey, defaultValue: defaultValue);
  }
}
