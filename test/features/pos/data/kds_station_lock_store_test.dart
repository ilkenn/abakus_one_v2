import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abakus_one_v2/features/pos/data/kds_station_lock_store.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_station.dart';

void main() {
  group('SharedPreferencesKdsStationLockStore', () {
    test('an empty store has no lock', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesKdsStationLockStore(prefs);

      expect(await store.currentLock(), isNull);
    });

    test('setLock then currentLock round-trips the same station', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesKdsStationLockStore(prefs);

      await store.setLock(KitchenStation.hot);

      expect(await store.currentLock(), KitchenStation.hot);
    });

    test('clearLock resets currentLock to null', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesKdsStationLockStore(prefs);

      await store.setLock(KitchenStation.cold);
      await store.clearLock();

      expect(await store.currentLock(), isNull);
    });

    test(
        'the lock survives a fresh SharedPreferences.getInstance() call — proves persistence, not just in-memory state',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesKdsStationLockStore(prefs);
      await store.setLock(KitchenStation.beverage);

      final freshPrefs = await SharedPreferences.getInstance();
      final freshStore = SharedPreferencesKdsStationLockStore(freshPrefs);

      expect(await freshStore.currentLock(), KitchenStation.beverage);
    });
  });
}
