import 'package:battery_plus/battery_plus.dart' as battery_plus;

import '../domain/location/battery_level_provider.dart';

/// Real, device-backed [BatteryLevelProvider] — Sprint 5B, wraps
/// `package:battery_plus`.
class BatteryPlusBatteryLevelProvider implements BatteryLevelProvider {
  BatteryPlusBatteryLevelProvider() : _battery = battery_plus.Battery();

  final battery_plus.Battery _battery;

  @override
  Future<int?> currentLevel() async {
    try {
      return await _battery.batteryLevel;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> isInBatterySaveMode() async {
    try {
      return await _battery.isInBatterySaveMode;
    } catch (_) {
      return false;
    }
  }
}
