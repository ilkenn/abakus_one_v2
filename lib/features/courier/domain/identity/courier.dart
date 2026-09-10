import '../../../../shared/models/courier_type.dart';
import 'courier_registry_status.dart';
import 'courier_status.dart';
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
    this.vehicleType = CourierVehicleType.motorcycle,
    this.vehicleIdentifier = '',
    this.capacity = 1,
    this.status = CourierRegistryStatus.active,
    required this.registeredAt,
    // AP-6 Sprint 2 — additive, defaulted so every existing caller in this
    // 220-file domain keeps compiling unchanged.
    this.type = CourierType.internal,
    this.dispatchStatus = CourierStatus.offline,
    this.returnedAt,
    this.activeOrderIds = const [],
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

  /// AP-6 Sprint 2 — who actually delivers for this courier record. See
  /// [CourierType]'s own doc comment for the [CourierType.marketplace]
  /// caveat.
  final CourierType type;

  /// AP-6 Sprint 2 — this courier's current real-time dispatch standing.
  /// See [CourierStatus]'s own doc comment for why this is a new field,
  /// never conflated with [status] (registry) or the separate, shift-gated
  /// `CourierAvailabilityStatus`.
  final CourierStatus dispatchStatus;

  /// AP-6 Sprint 2 — this courier's last confirmed physical return to
  /// [primaryBranchId], stamped by `markCourierReturned.ts`. `null` until
  /// the first confirmed return. The FIFO dispatch sort key
  /// (`courier_return_fifo.dart`) — oldest first, "first back, first out."
  final DateTime? returnedAt;

  /// AP-6 Sprint 2 — order ids this courier currently has out for
  /// delivery, appended by `assignCourierToOrder.ts` and removed by
  /// `advanceDeliveryOrderStatus.ts`'s completion hook. Must be empty
  /// before `markCourierReturned.ts` will accept a return.
  final List<String> activeOrderIds;

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
    CourierType? type,
    CourierStatus? dispatchStatus,
    DateTime? returnedAt,
    List<String>? activeOrderIds,
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
      type: type ?? this.type,
      dispatchStatus: dispatchStatus ?? this.dispatchStatus,
      returnedAt: returnedAt ?? this.returnedAt,
      activeOrderIds: activeOrderIds ?? this.activeOrderIds,
    );
  }
}
