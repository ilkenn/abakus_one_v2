import 'kitchen_station.dart';

/// A physical/virtual kitchen display device paired to a branch — the
/// first `Device` concept of any kind in this codebase (no such type
/// existed before Phase 4; `docs/module_catalog.md`'s KDS sketch described
/// "device-level pairing to a branch" only as a requirement). Mutable
/// registry entity, like `RestaurantTable`/`CashDrawer` — a device's own
/// current shape is what matters, not a revision history of it; the
/// append-only requirement in this phase applies to the *operational*
/// records a device's sessions produce ([KitchenDisplaySession],
/// [KitchenEvent]), not to the registry entry itself.
class KitchenDisplayDevice {
  const KitchenDisplayDevice({
    required this.id,
    required this.branchId,
    required this.name,
    this.stationScope,
    this.isActive = true,
    required this.registeredAt,
  });

  final String id;
  final String branchId;
  final String name;

  /// `null` means "shared view" — every station's work items. A non-null,
  /// non-empty set restricts this device to a station-filtered view
  /// (Phase 4G's "station-filtered view" requirement) — purely a display
  /// filter; it never changes what work items exist or who may act on
  /// them.
  final Set<KitchenStation>? stationScope;

  /// Whether this device is still registered/in service — mirrors
  /// `CashDrawer.isActive`'s "in service, not currently connected"
  /// meaning; live connectivity is tracked separately by
  /// [KitchenDisplaySession]/`KitchenConnectionMonitor`, never duplicated
  /// onto this field.
  final bool isActive;

  final DateTime registeredAt;

  KitchenDisplayDevice copyWith({
    Set<KitchenStation>? stationScope,
    bool? isActive,
  }) {
    return KitchenDisplayDevice(
      id: id,
      branchId: branchId,
      name: name,
      stationScope: stationScope ?? this.stationScope,
      isActive: isActive ?? this.isActive,
      registeredAt: registeredAt,
    );
  }
}
