import 'package:shared_preferences/shared_preferences.dart';

import '../domain/kds/kitchen_station.dart';

/// The physical device's own local, restart-durable "station lock" — when
/// set, `KitchenDisplayBoardScreen` always opens pre-filtered to exactly
/// this [KitchenStation], every session, until explicitly cleared.
///
/// Purely a local device preference (`SharedPreferences`), deliberately NOT
/// the server-facing `KitchenDisplayDeviceRepository`/`KitchenDisplayDevice`
/// multi-device registry — that's a separate, still-deferred concept with
/// no real `deviceId` flowing into the board screen today. Mirrors
/// `OfflineLeaseStore`'s exact shape/reasoning, simplified further: a
/// single enum value needs no JSON envelope, just its `.name`.
abstract interface class KdsStationLockStore {
  Future<KitchenStation?> currentLock();
  Future<void> setLock(KitchenStation station);
  Future<void> clearLock();
}

class SharedPreferencesKdsStationLockStore implements KdsStationLockStore {
  SharedPreferencesKdsStationLockStore(this._prefs);
  final SharedPreferences _prefs;

  static const _lockKey = 'kds_station_lock_v1';

  @override
  Future<KitchenStation?> currentLock() async {
    final raw = _prefs.getString(_lockKey);
    if (raw == null || raw.isEmpty) return null;
    for (final station in KitchenStation.values) {
      if (station.name == raw) return station;
    }
    return null;
  }

  @override
  Future<void> setLock(KitchenStation station) async {
    await _prefs.setString(_lockKey, station.name);
  }

  @override
  Future<void> clearLock() async {
    await _prefs.remove(_lockKey);
  }
}
