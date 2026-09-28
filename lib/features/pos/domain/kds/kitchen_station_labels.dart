import 'kitchen_station.dart';

/// Turkish display labels for every real [KitchenStation] value — the one
/// source of truth for both the board's station filter chips
/// (`_StationFilterBar`) and the device station-lock settings screen
/// (`KdsStationLockSettingsScreen`), so the two never drift out of sync.
/// Deliberately excludes a "Tümü" (all) entry — that's a filter-bar-only
/// concept (`null` selection), not a real station.
const kitchenStationLabels = <KitchenStation, String>{
  KitchenStation.hot: 'Sıcak',
  KitchenStation.cold: 'Soğuk',
  KitchenStation.beverage: 'İçecek',
  KitchenStation.dessert: 'Tatlı',
  KitchenStation.packing: 'Paketleme',
  KitchenStation.shared: 'Ortak',
};
