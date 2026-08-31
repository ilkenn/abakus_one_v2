import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import 'offline_outbox_status.dart';

/// One cash sale captured locally while the device was offline, authorized
/// by a real, server-issued offline lease
/// (`functions/src/fiscalDomain.ts`'s `OfflineLease`). Durable — persisted
/// via `OfflinePaymentOutboxRepository`, survives app termination/restart.
///
/// Replayed, strictly in [deviceSequence] order, through the SAME
/// `recordPaymentAttempt` Cloud Function every online cash tender already
/// goes through (`functions/src/paymentEngine.ts`'s own `offlineLease`
/// parameter) — never a parallel sync endpoint. The actual HTTP call that
/// replays a queued entry is Wave D's own API-client wiring (the Flutter
/// app has no callable client for ANY AP-4 backend function yet); this
/// class and its repository are the real, tested, durable QUEUE the
/// eventual sync use case will read from — not a stub.
class OfflineQueuedCashPayment {
  const OfflineQueuedCashPayment({
    required this.id,
    required this.checkId,
    required this.paymentSessionId,
    required this.subAccountId,
    required this.amount,
    required this.leaseId,
    required this.deviceSequence,
    required this.idempotencyKey,
    required this.capturedAt,
    required this.status,
    this.failureReason,
    this.syncedAt,
  });

  /// Locally generated, stable across retries — the dedupe key [enqueue]
  /// uses so a repeated capture (e.g. a UI double-tap before the first
  /// enqueue was confirmed) never creates a duplicate queue entry.
  final String id;

  final String checkId;
  final String paymentSessionId;
  final String subAccountId;
  final Money amount;
  final String leaseId;

  /// The lease's own monotonic sequence number this entry claimed at
  /// capture time — the server rejects a replay whose sequence isn't
  /// exactly `lease.lastSeenDeviceSequence + 1` (replay protection,
  /// `fiscalDomain.ts`'s `validateOfflineLeaseForOperation`).
  final int deviceSequence;

  /// Client-generated, unique per entry — the SAME idempotency guarantee
  /// `recordPaymentAttempt` already gives every other tender; a sync retry
  /// after a dropped response replays this exact key, never a fresh one.
  final String idempotencyKey;

  final DateTime capturedAt;
  final OfflineOutboxStatus status;
  final String? failureReason;
  final DateTime? syncedAt;

  OfflineQueuedCashPayment copyWith({
    OfflineOutboxStatus? status,
    String? failureReason,
    DateTime? syncedAt,
  }) {
    return OfflineQueuedCashPayment(
      id: id,
      checkId: checkId,
      paymentSessionId: paymentSessionId,
      subAccountId: subAccountId,
      amount: amount,
      leaseId: leaseId,
      deviceSequence: deviceSequence,
      idempotencyKey: idempotencyKey,
      capturedAt: capturedAt,
      status: status ?? this.status,
      failureReason: failureReason ?? this.failureReason,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'checkId': checkId,
        'paymentSessionId': paymentSessionId,
        'subAccountId': subAccountId,
        'amountMinorUnits': amount.minorUnits,
        'currencyCode': amount.currency.isoCode,
        'leaseId': leaseId,
        'deviceSequence': deviceSequence,
        'idempotencyKey': idempotencyKey,
        'capturedAt': capturedAt.toIso8601String(),
        'status': status.name,
        'failureReason': failureReason,
        'syncedAt': syncedAt?.toIso8601String(),
      };

  factory OfflineQueuedCashPayment.fromJson(Map<String, Object?> json) {
    final currencyCode = json['currencyCode'] as String;
    final currency = Currency.all.firstWhere(
      (c) => c.isoCode == currencyCode,
      orElse: () => Currency.tryLira,
    );
    final syncedAtRaw = json['syncedAt'] as String?;
    return OfflineQueuedCashPayment(
      id: json['id'] as String,
      checkId: json['checkId'] as String,
      paymentSessionId: json['paymentSessionId'] as String,
      subAccountId: json['subAccountId'] as String,
      amount: Money(json['amountMinorUnits'] as int, currency),
      leaseId: json['leaseId'] as String,
      deviceSequence: json['deviceSequence'] as int,
      idempotencyKey: json['idempotencyKey'] as String,
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      status: OfflineOutboxStatus.values.byName(json['status'] as String),
      failureReason: json['failureReason'] as String?,
      syncedAt: syncedAtRaw != null ? DateTime.parse(syncedAtRaw) : null,
    );
  }
}
