import '../domain/communication/courier_message.dart';

/// Append-only storage for [CourierMessage] — Sprint 5C.
abstract interface class CourierMessageRepository {
  Future<void> append(CourierMessage message);
  Future<List<CourierMessage>> findByBranchId(String branchId);

  /// Every message addressed to [courierId] directly, plus every
  /// broadcast/emergency message sent branch-wide (`recipientCourierId ==
  /// null`) for [branchId] — the courier-facing inbox query.
  Future<List<CourierMessage>> findForCourier({
    required String courierId,
    required String branchId,
  });
}

class InMemoryCourierMessageRepository implements CourierMessageRepository {
  final List<CourierMessage> _messages = [];

  @override
  Future<void> append(CourierMessage message) async {
    _messages.add(message);
  }

  @override
  Future<List<CourierMessage>> findByBranchId(String branchId) async {
    return List.unmodifiable(_messages.where((m) => m.branchId == branchId));
  }

  @override
  Future<List<CourierMessage>> findForCourier({
    required String courierId,
    required String branchId,
  }) async {
    return List.unmodifiable(_messages.where((m) =>
        m.branchId == branchId &&
        (m.recipientCourierId == courierId || m.recipientCourierId == null)));
  }
}
