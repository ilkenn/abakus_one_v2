/// Public, application-facing feature flag names — the only vocabulary
/// UI, routing, and business logic should ever pass to
/// `FeatureFlagsService.isEnabled`/`getString`/`getInt`.
///
/// See `RemoteConfigFeatureFlagsService` for how a name here maps onto the
/// underlying remote-config parameter key. See [FeatureFlagsDefaults] for
/// the documented safe default for each flag.
abstract final class FeatureFlagsKeys {
  FeatureFlagsKeys._();

  /// OTP phone login — the app's only existing auth flow
  /// (`LoginScreen`/`OtpScreen`). See [FeatureFlagsDefaults.otpLoginEnabled]
  /// for why this one defaults to *on*, unlike the others below.
  static const String otpLoginEnabled = 'otpLoginEnabled';

  /// Custom bowl composition flow.
  static const String bowlBuilderEnabled = 'bowlBuilderEnabled';

  /// Loyalty "fortune wheel" reward mechanic.
  static const String fortuneWheelEnabled = 'fortuneWheelEnabled';

  /// Table reservations.
  static const String reservationsEnabled = 'reservationsEnabled';

  /// QR-code table/session scanning.
  static const String qrScannerEnabled = 'qrScannerEnabled';
}

/// Documented safe default for each [FeatureFlagsKeys] flag — the value a
/// caller should pass as `defaultValue` when reading the flag, used
/// whenever the flag is unknown, initialization hasn't completed, or
/// Remote Config fetch/initialization failed.
///
/// Per Sprint 2's explicit rule ("critical functionality must not become
/// enabled merely because Remote Config initialization fails"), every flag
/// gating a feature not yet built or activated defaults to `false`
/// (fail-closed). [otpLoginEnabled] is the one exception: it gates the
/// app's *only* existing authentication flow, already shipped and in use
/// — defaulting it to `false` on a Remote Config outage would make the
/// entire app unusable rather than fail safely, so it defaults to `true`
/// (fail-open for already-shipped, non-experimental functionality).
abstract final class FeatureFlagsDefaults {
  FeatureFlagsDefaults._();

  static const bool otpLoginEnabled = true;
  static const bool bowlBuilderEnabled = false;
  static const bool fortuneWheelEnabled = false;
  static const bool reservationsEnabled = false;
  static const bool qrScannerEnabled = false;
}
