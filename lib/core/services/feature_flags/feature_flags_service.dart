/// Boolean on/off feature gating.
///
/// Deliberately a separate seam from `RemoteConfigService` even though
/// `RemoteConfigKeys` already defines several boolean-shaped keys
/// (`loyaltyEnabled`, `campaignsEnabled`, etc.) — remote config is for
/// general parameter values, this is a narrower, purpose-built API for
/// simple on/off gates (and, later, staged-rollout/targeting logic remote
/// config's API doesn't model). Reconciling or migrating
/// `RemoteConfigKeys`'s existing boolean entries onto this service is a
/// separate, explicit decision, not made here.
abstract interface class FeatureFlagsService {
  /// Prepares the service for use (e.g. fetching the current flag set).
  /// Must be called and awaited before [isEnabled] is trusted to reflect
  /// anything beyond [defaultValue].
  Future<void> initialize();

  /// Whether the flag named [key] is enabled. Returns [defaultValue] if
  /// the flag is unknown or the service hasn't been initialized yet —
  /// never throws.
  bool isEnabled(String key, {bool defaultValue = false});
}
