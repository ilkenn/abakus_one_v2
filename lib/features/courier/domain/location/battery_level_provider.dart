/// Backend/platform-neutral seam for device battery telemetry (Sprint 5B).
/// Feeds Part 6 ("live tracking" battery level), Part 3
/// (`AdaptiveTrackingPolicy`'s low-power-mode signal), and Part 12
/// (performance "battery consumption estimate"). Never used to punish or
/// block a courier by itself — an operational signal only, same standing
/// as `CourierFraudSignal`.
abstract interface class BatteryLevelProvider {
  /// Current battery level, 0-100. `null` when the platform can't report
  /// one.
  Future<int?> currentLevel();

  /// Whether the device is currently in a battery-saver/low-power mode.
  Future<bool> isInBatterySaveMode();
}

/// Honest "never reports" default for tests/environments with no real
/// device.
class NoOpBatteryLevelProvider implements BatteryLevelProvider {
  const NoOpBatteryLevelProvider();

  @override
  Future<int?> currentLevel() async => null;

  @override
  Future<bool> isInBatterySaveMode() async => false;
}
