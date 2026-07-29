/// Lifecycle status of a [KitchenDisplaySession].
enum KitchenDisplaySessionStatus { active, ended }

/// One connected period of a [KitchenDisplayDevice] — session start/end
/// plus the heartbeat contract Phase 4G requires for stale-device
/// detection. Mirrors `CashSession`'s append-only-via-revision shape.
///
/// **Append-only**: never mutated in place — every heartbeat/status change
/// produces a new instance with the same [id] and an incremented
/// [revision].
class KitchenDisplaySession {
  const KitchenDisplaySession({
    required this.id,
    required this.deviceId,
    required this.branchId,
    required this.status,
    required this.startedAt,
    this.endedAt,
    required this.lastHeartbeatAt,
    required this.revision,
  });

  final String id;
  final String deviceId;
  final String branchId;
  final KitchenDisplaySessionStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime lastHeartbeatAt;
  final int revision;

  bool get isActive => status == KitchenDisplaySessionStatus.active;

  KitchenDisplaySession copyWith({
    KitchenDisplaySessionStatus? status,
    DateTime? endedAt,
    DateTime? lastHeartbeatAt,
    int? revision,
  }) {
    return KitchenDisplaySession(
      id: id,
      deviceId: deviceId,
      branchId: branchId,
      status: status ?? this.status,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      lastHeartbeatAt: lastHeartbeatAt ?? this.lastHeartbeatAt,
      revision: revision ?? this.revision,
    );
  }
}
