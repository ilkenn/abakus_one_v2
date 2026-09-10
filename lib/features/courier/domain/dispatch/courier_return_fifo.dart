import '../identity/courier.dart';
import '../identity/courier_status.dart';

/// AP-6 Sprint 2 — the cashier dispatch dialog's "who's next" ordering: a
/// plain, stateless sort of a branch's currently-[CourierStatus.available]
/// couriers by [Courier.returnedAt], oldest first ("first back to the shop,
/// first out again").
///
/// **Deliberately separate from `courier_dispatch_queue_builder.dart`**
/// (`CourierDispatchQueueBuilder`, `domain/dispatch/`) — that builder
/// projects an append-only [CourierDispatchQueueEvent] log into queue
/// positions, a heavier, more auditable mechanism (BR-COURIER-045/046/047)
/// this sprint doesn't build or depend on. This utility only ever reads the
/// plain [Courier.returnedAt] field already on the roster entry itself.
abstract final class CourierReturnFifo {
  CourierReturnFifo._();

  /// Returns [couriers] filtered to [CourierStatus.available] and sorted by
  /// [Courier.returnedAt] ascending — a courier that has never returned
  /// this session (`returnedAt == null`) sorts last (never recommended
  /// ahead of a courier with a real, known return time). Ties (identical
  /// [returnedAt]) keep their relative input order (a stable sort), never
  /// re-ordered arbitrarily.
  static List<Courier> sortAvailableByReturnTime(List<Courier> couriers) {
    final available =
        couriers.where((c) => c.dispatchStatus == CourierStatus.available).toList();
    available.sort((a, b) {
      final aReturnedAt = a.returnedAt;
      final bReturnedAt = b.returnedAt;
      if (aReturnedAt == null && bReturnedAt == null) return 0;
      if (aReturnedAt == null) return 1;
      if (bReturnedAt == null) return -1;
      return aReturnedAt.compareTo(bReturnedAt);
    });
    return available;
  }
}
