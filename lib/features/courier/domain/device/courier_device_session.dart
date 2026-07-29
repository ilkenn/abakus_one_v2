/// Lifecycle status of a [CourierDeviceSession].
enum CourierDeviceSessionStatus { active, ended }

/// One connected period of a [CourierDevice] — session start/end plus the
/// heartbeat contract `CourierConnectionMonitor` reads, mirroring
/// `KitchenDisplaySession`'s shape (Phase 4) as a separate, parallel type.
/// Append-only via [revision].
class CourierDeviceSession {
  const CourierDeviceSession({
    required this.id,
    required this.deviceId,
    required this.courierId,
    required this.status,
    required this.startedAt,
    this.endedAt,
    required this.lastHeartbeatAt,
    required this.revision,
  });

  final String id;
  final String deviceId;
  final String courierId;
  final CourierDeviceSessionStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime lastHeartbeatAt;
  final int revision;

  bool get isActive => status == CourierDeviceSessionStatus.active;

  CourierDeviceSession copyWith({
    CourierDeviceSessionStatus? status,
    DateTime? endedAt,
    DateTime? lastHeartbeatAt,
    int? revision,
  }) {
    return CourierDeviceSession(
      id: id,
      deviceId: deviceId,
      courierId: courierId,
      status: status ?? this.status,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      lastHeartbeatAt: lastHeartbeatAt ?? this.lastHeartbeatAt,
      revision: revision ?? this.revision,
    );
  }
}
