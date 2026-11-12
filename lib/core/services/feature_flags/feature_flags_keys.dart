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
/// 2026-11-12 — product owner decision: every phase and module is now
/// built and launched, so EVERY flag defaults to `true` (no "Bu özellik
/// henüz etkinleştirilmedi" gate left from development). A module can
/// still be turned off remotely once Remote Config is live, and
/// [ModuleEntitlementGate] still requires an active entitlement grant and
/// the actor's role permission.
///
/// Historical rule (superseded): per Sprint 2 ("critical functionality must
/// not become enabled merely because Remote Config initialization fails"),
/// flags gating features not yet built defaulted to `false` (fail-closed). [otpLoginEnabled] is the one exception: it gates the
/// app's *only* existing authentication flow, already shipped and in use
/// — defaulting it to `false` on a Remote Config outage would make the
/// entire app unusable rather than fail safely, so it defaults to `true`
/// (fail-open for already-shipped, non-experimental functionality).
abstract final class FeatureFlagsDefaults {
  FeatureFlagsDefaults._();

  static const bool otpLoginEnabled = true;
  static const bool bowlBuilderEnabled = true;
  static const bool fortuneWheelEnabled = true;
  static const bool reservationsEnabled = true;
  static const bool qrScannerEnabled = true;

  // Phase 7 — all fail-closed by default, matching every other
  // not-yet-launched flag above ("critical functionality must not become
  // enabled merely because Remote Config initialization fails" doesn't
  // apply here — none of these are critical, shipped functionality yet).
  static const bool smartRestaurantSetupEnabled = true;
  static const bool menuImportEnabled = true;
  static const bool inventoryEnabled = true;
  static const bool recipesEnabled = true;
  static const bool nutritionEnabled = true;
  static const bool allergensEnabled = true;
  static const bool purchasingEnabled = true;
  static const bool suppliersEnabled = true;
  static const bool costingEnabled = true;
  static const bool profitabilityEnabled = true;
  static const bool advancedReportingEnabled = true;

  // Phase 8 — same fail-closed default as every other not-yet-launched
  // flag above.
  static const bool crmEnabled = true;
  static const bool loyaltyEnabled = true;
  static const bool posModuleEnabled = true;
  static const bool kdsModuleEnabled = true;
  static const bool courierModuleEnabled = true;
  static const bool marketplaceEnabled = true;
  static const bool paymentsEnabled = true;
  static const bool aiEnabled = true;

  /// 2026-11-12 (ADR-079) — the documented default of [key], so every
  /// caller (notably `CheckModuleAccess`) reads the SAME default instead of
  /// `FeatureFlagsService.isEnabled`'s bare `false`. Unknown keys stay
  /// fail-closed.
  static bool valueFor(String key) => switch (key) {
        FeatureFlagsKeys.otpLoginEnabled => otpLoginEnabled,
        FeatureFlagsKeys.bowlBuilderEnabled => bowlBuilderEnabled,
        FeatureFlagsKeys.fortuneWheelEnabled => fortuneWheelEnabled,
        FeatureFlagsKeys.reservationsEnabled => reservationsEnabled,
        FeatureFlagsKeys.qrScannerEnabled => qrScannerEnabled,
        FeatureFlagsKeys.smartRestaurantSetupEnabled =>
          smartRestaurantSetupEnabled,
        FeatureFlagsKeys.menuImportEnabled => menuImportEnabled,
        FeatureFlagsKeys.inventoryEnabled => inventoryEnabled,
        FeatureFlagsKeys.recipesEnabled => recipesEnabled,
        FeatureFlagsKeys.nutritionEnabled => nutritionEnabled,
        FeatureFlagsKeys.allergensEnabled => allergensEnabled,
        FeatureFlagsKeys.purchasingEnabled => purchasingEnabled,
        FeatureFlagsKeys.suppliersEnabled => suppliersEnabled,
        FeatureFlagsKeys.costingEnabled => costingEnabled,
        FeatureFlagsKeys.profitabilityEnabled => profitabilityEnabled,
        FeatureFlagsKeys.advancedReportingEnabled => advancedReportingEnabled,
        FeatureFlagsKeys.crmEnabled => crmEnabled,
        FeatureFlagsKeys.loyaltyEnabled => loyaltyEnabled,
        FeatureFlagsKeys.posModuleEnabled => posModuleEnabled,
        FeatureFlagsKeys.kdsModuleEnabled => kdsModuleEnabled,
        FeatureFlagsKeys.courierModuleEnabled => courierModuleEnabled,
        FeatureFlagsKeys.marketplaceEnabled => marketplaceEnabled,
        FeatureFlagsKeys.paymentsEnabled => paymentsEnabled,
        FeatureFlagsKeys.aiEnabled => aiEnabled,
        _ => false,
      };
}
