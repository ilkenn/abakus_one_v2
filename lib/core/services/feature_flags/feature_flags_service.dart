/// Boolean on/off feature gating — the sole application-facing API for
/// "is this feature available." UI, routing, and business logic must
/// always ask this service (via [FeatureFlagsKeys] names), never read a
/// feature decision from `RemoteConfigService`/`RemoteConfigKeys`
/// directly.
///
/// `RemoteConfigService` is a separate, lower-level seam: a generic
/// remote value/configuration source with no opinion about what a
/// "feature" is. `RemoteConfigFeatureFlagsService` is the one adapter
/// allowed to bridge the two — see its doc comment for the full ownership
/// boundary. This keeps exactly one public owner per application
/// decision instead of two competing ways to ask "is X on."
abstract interface class FeatureFlagsService {
  /// Prepares the service for use (e.g. fetching the current flag set).
  /// Must be called and awaited before [isEnabled] is trusted to reflect
  /// anything beyond [defaultValue].
  Future<void> initialize();

  /// Whether the flag named [key] (see [FeatureFlagsKeys]) is enabled.
  /// Returns [defaultValue] if the flag is unknown or the service hasn't
  /// been initialized yet — never throws.
  bool isEnabled(String key, {bool defaultValue = false});
}
