import 'courier_registry_status.dart';
import 'courier_vehicle_type.dart';

/// A courier's registry entry — the first `Courier` entity of any kind in
/// this codebase. `docs/decisions.md` ADR-015 (Sprint 3F) deliberately
/// referenced couriers by plain `String courierId` because no such entity
/// existed yet; this type now exists, and its [id] is that same string
/// value — no migration of Sprint 3F/Phase 4's existing `courierId`
/// fields is needed or performed.
///
/// Mutable registry entity, mirroring `CashDrawer`/`RestaurantTable`: a
/// courier's own current shape is what matters, not a revision history of
/// it — the append-only requirement in this phase applies to the
/// *operational* records a courier's shifts/deliveries produce, not to
/// this registry entry itself. "Archive without deletion" is satisfied by
/// [status] reaching [CourierRegistryStatus.archived] — no delete method
/// exists on `CourierRepository`.
///
/// Deliberately minimal contact data — only what dispatch/support actually
/// needs, per the explicit "do not store unnecessary sensitive personal
/// data" rule. No document images are stored (see
/// `CourierDocumentRequirement`'s own doc comment).
class Courier {
  const Courier({
    required this.id,
    required this.primaryBranchId,
    this.eligibleBranchIds = const [],
    required this.displayName,
    required this.phoneNumber,
    required this.vehicleType,
    this.vehicleIdentifier = '',
    required this.capacity,
    this.status = CourierRegistryStatus.active,
    required this.registeredAt,
  });

  final String id;
  final String primaryBranchId;

  /// Branches this courier may additionally operate at ("multi-branch
  /// eligibility where allowed") — empty means single-branch only
  /// ([primaryBranchId]).
  final List<String> eligibleBranchIds;

  final String displayName;
  final String phoneNumber;
  final CourierVehicleType vehicleType;
  final String vehicleIdentifier;

  /// Maximum concurrent active deliveries — the authoritative input to
  /// availability/capacity checks (`CourierAvailability`).
  final int capacity;

  final CourierRegistryStatus status;
  final DateTime registeredAt;

  bool eligibleForBranch(String branchId) =>
      branchId == primaryBranchId || eligibleBranchIds.contains(branchId);

  Courier copyWith({
    List<String>? eligibleBranchIds,
    String? displayName,
    String? phoneNumber,
    CourierVehicleType? vehicleType,
    String? vehicleIdentifier,
    int? capacity,
    CourierRegistryStatus? status,
  }) {
    return Courier(
      id: id,
      primaryBranchId: primaryBranchId,
      eligibleBranchIds: eligibleBranchIds ?? this.eligibleBranchIds,
      displayName: displayName ?? this.displayName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      vehicleType: vehicleType ?? this.vehicleType,
      vehicleIdentifier: vehicleIdentifier ?? this.vehicleIdentifier,
      capacity: capacity ?? this.capacity,
      status: status ?? this.status,
      registeredAt: registeredAt,
    );
  }
}
