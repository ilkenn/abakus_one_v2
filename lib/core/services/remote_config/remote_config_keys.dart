/// Generic remote-config parameter keys — operational/app-lifecycle
/// values only, never a boolean product-feature decision.
///
/// This class previously also held boolean feature-availability keys
/// (`loyaltyEnabled`, `campaignsEnabled`, `reservationsEnabled`,
/// `deliveryEnabled`, `qrEnabled`, `customBowlEnabled`). They were removed
/// from here — confirmed to have zero consumers anywhere in `lib/` at the
/// time — and now live as a private mapping inside
/// `RemoteConfigFeatureFlagsService`
/// (`lib/core/services/feature_flags/remote_config_feature_flags_service.dart`),
/// the only file allowed to know that a feature flag happens to be backed
/// by remote config. `FeatureFlagsService` (see
/// `lib/core/services/feature_flags/feature_flags_service.dart`) is the
/// sole application-facing API for "is this feature available" — nothing
/// should read a feature decision from this class directly.
abstract final class RemoteConfigKeys {
  RemoteConfigKeys._();

  static const String maintenanceMode = 'maintenance_mode';
  static const String minimumAppVersion = 'minimum_app_version';
  static const String forceUpdate = 'force_update';
}
