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

  // Phase 7 — Smart Restaurant Setup, Inventory & Food Intelligence
  // (`docs/decisions.md` ADR-024). Each gates whether the module's
  // functionality is *technically enabled* — a separate axis from
  // `EntitlementModule` ("has the tenant purchased it?") and
  // `PosAuthorizedAction` ("may this actor do it?"); see
  // `features/entitlements/application/use_cases/check_module_access.dart`
  // for where all three combine.
  static const String smartRestaurantSetupEnabled =
      'smartRestaurantSetupEnabled';
  static const String menuImportEnabled = 'menuImportEnabled';
  static const String inventoryEnabled = 'inventoryEnabled';
  static const String recipesEnabled = 'recipesEnabled';
  static const String nutritionEnabled = 'nutritionEnabled';
  static const String allergensEnabled = 'allergensEnabled';
  static const String purchasingEnabled = 'purchasingEnabled';
  static const String suppliersEnabled = 'suppliersEnabled';
  static const String costingEnabled = 'costingEnabled';
  static const String profitabilityEnabled = 'profitabilityEnabled';
  static const String advancedReportingEnabled = 'advancedReportingEnabled';

  // Phase 8 — Platform, Integrations & White-Label Ecosystem
  // (`docs/decisions.md` ADR-025). `EntitlementModule.qrMenu`/
  // `.reservations` deliberately reuse the pre-existing
  // [qrScannerEnabled]/[reservationsEnabled] flags above rather than
  // duplicating them — those features predate module entitlements but
  // are exactly what those two new modules gate.
  static const String crmEnabled = 'crmEnabled';
  static const String loyaltyEnabled = 'loyaltyEnabled';
  static const String posModuleEnabled = 'posModuleEnabled';
  static const String kdsModuleEnabled = 'kdsModuleEnabled';
  static const String courierModuleEnabled = 'courierModuleEnabled';
  static const String marketplaceEnabled = 'marketplaceEnabled';
  static const String paymentsEnabled = 'paymentsEnabled';
  static const String aiEnabled = 'aiEnabled';
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

  // Phase 7 — all fail-closed by default, matching every other
  // not-yet-launched flag above ("critical functionality must not become
  // enabled merely because Remote Config initialization fails" doesn't
  // apply here — none of these are critical, shipped functionality yet).
  static const bool smartRestaurantSetupEnabled = false;
  static const bool menuImportEnabled = false;
  static const bool inventoryEnabled = false;
  static const bool recipesEnabled = false;
  static const bool nutritionEnabled = false;
  static const bool allergensEnabled = false;
  static const bool purchasingEnabled = false;
  static const bool suppliersEnabled = false;
  static const bool costingEnabled = false;
  static const bool profitabilityEnabled = false;
  static const bool advancedReportingEnabled = false;

  // Phase 8 — same fail-closed default as every other not-yet-launched
  // flag above.
  static const bool crmEnabled = false;
  static const bool loyaltyEnabled = false;
  static const bool posModuleEnabled = false;
  static const bool kdsModuleEnabled = false;
  static const bool courierModuleEnabled = false;
  static const bool marketplaceEnabled = false;
  static const bool paymentsEnabled = false;
  static const bool aiEnabled = false;
}
