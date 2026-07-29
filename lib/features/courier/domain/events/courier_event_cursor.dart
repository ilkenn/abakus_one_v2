/// One device's replay position within a branch's courier event log —
/// mirrors `KitchenEventCursor`'s shape as a deliberately separate type.
class CourierEventCursor {
  const CourierEventCursor({
    required this.deviceId,
    required this.branchId,
    required this.lastProcessedSequence,
    required this.updatedAt,
  });

  final String deviceId;
  final String branchId;
  final int lastProcessedSequence;
  final DateTime updatedAt;

  CourierEventCursor copyWith({
    int? lastProcessedSequence,
    DateTime? updatedAt,
  }) {
    return CourierEventCursor(
      deviceId: deviceId,
      branchId: branchId,
      lastProcessedSequence:
          lastProcessedSequence ?? this.lastProcessedSequence,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
