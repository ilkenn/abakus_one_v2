/// Public, application-facing feature flag names — the only vocabulary
/// UI, routing, and business logic should ever pass to
/// `FeatureFlagsService.isEnabled`.
///
/// These correspond to the same six product features previously named
/// (but never consumed) as boolean keys on `RemoteConfigKeys`; see
/// `RemoteConfigFeatureFlagsService` for how a name here maps onto the
/// underlying remote-config value.
abstract final class FeatureFlagsKeys {
  FeatureFlagsKeys._();

  static const String loyalty = 'loyalty';
  static const String campaigns = 'campaigns';
  static const String reservations = 'reservations';
  static const String delivery = 'delivery';
  static const String qr = 'qr';
  static const String customBowl = 'custom_bowl';
}
