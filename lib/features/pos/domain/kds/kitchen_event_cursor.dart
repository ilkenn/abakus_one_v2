/// One device's replay position within a branch's kitchen event log —
/// what `KitchenSynchronizationService` reads on reconnect to know which
/// [KitchenEvent]s (by `sequence`) still need to be delivered to that
/// device, and advances after each successful sync batch.
///
/// **Not authoritative kitchen state** — losing a cursor only means a
/// device resynchronizes from the start of the branch's retained event
/// log, never a loss of the underlying [KitchenWorkItem]/[KitchenEvent]
/// data itself.
class KitchenEventCursor {
  const KitchenEventCursor({
    required this.deviceId,
    required this.branchId,
    required this.lastProcessedSequence,
    required this.updatedAt,
  });

  final String deviceId;
  final String branchId;

  /// The highest `KitchenEvent.sequence` this device has successfully
  /// processed — `0` means nothing yet (replay from the start).
  final int lastProcessedSequence;

  final DateTime updatedAt;

  KitchenEventCursor copyWith({
    int? lastProcessedSequence,
    DateTime? updatedAt,
  }) {
    return KitchenEventCursor(
      deviceId: deviceId,
      branchId: branchId,
      lastProcessedSequence:
          lastProcessedSequence ?? this.lastProcessedSequence,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
