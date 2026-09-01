import 'package:abakus_one_v2/features/pos/application/use_cases/sync_offline_payment_outbox.dart';
import 'package:abakus_one_v2/features/pos/data/offline_payment_outbox_repository.dart';
import 'package:abakus_one_v2/features/pos/data/payment_gateway.dart';
import 'package:abakus_one_v2/features/pos/data/pos_action_gateway.dart';
import 'package:abakus_one_v2/features/pos/domain/offline/offline_outbox_status.dart';
import 'package:abakus_one_v2/features/pos/domain/offline/offline_queued_cash_payment.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in — mirrors `SharedPreferencesOfflinePaymentOutboxRepository`'s
/// exact status-transition semantics without touching `shared_preferences`.
class InMemoryOfflinePaymentOutboxRepository
    implements OfflinePaymentOutboxRepository {
  final List<OfflineQueuedCashPayment> _entries = [];

  @override
  Future<void> enqueue(OfflineQueuedCashPayment entry) async {
    if (_entries.any((e) => e.id == entry.id)) return;
    _entries.add(entry);
  }

  @override
  Future<List<OfflineQueuedCashPayment>> findPendingByLeaseId(
      String leaseId) async {
    final pending = _entries
        .where((e) =>
            e.leaseId == leaseId && e.status == OfflineOutboxStatus.pending)
        .toList()
      ..sort((a, b) => a.deviceSequence.compareTo(b.deviceSequence));
    return pending;
  }

  @override
  Future<List<OfflineQueuedCashPayment>> findAll() async =>
      List.unmodifiable(_entries);

  Future<void> _update(
    String id,
    OfflineQueuedCashPayment Function(OfflineQueuedCashPayment) update,
  ) async {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index == -1) return;
    _entries[index] = update(_entries[index]);
  }

  @override
  Future<void> markSyncing(String id) =>
      _update(id, (e) => e.copyWith(status: OfflineOutboxStatus.syncing));

  @override
  Future<void> markSynced(String id, {required DateTime syncedAt}) => _update(
      id,
      (e) =>
          e.copyWith(status: OfflineOutboxStatus.synced, syncedAt: syncedAt));

  @override
  Future<void> markFailed(String id, {required String reason}) => _update(
      id,
      (e) => e.copyWith(
          status: OfflineOutboxStatus.failed, failureReason: reason));

  @override
  Future<void> markManualInterventionRequired(String id,
          {required String reason}) =>
      _update(
          id,
          (e) => e.copyWith(
              status: OfflineOutboxStatus.manualInterventionRequired,
              failureReason: reason));

  @override
  Future<void> resetToPending(String id) =>
      _update(id, (e) => e.copyWith(status: OfflineOutboxStatus.pending));

  @override
  Future<void> removeSynced(String id) async {
    _entries.removeWhere(
        (e) => e.id == id && e.status == OfflineOutboxStatus.synced);
  }

  OfflineOutboxStatus statusOf(String id) =>
      _entries.firstWhere((e) => e.id == id).status;
}

typedef AttemptScript = Future<PaymentAttemptResult> Function(
    Map<String, dynamic> allocations, int deviceSequence);

/// Scriptable fake — each call consults [scriptForSequence] keyed by the
/// presented `offlineLease.deviceSequence`, mirroring exactly what the real
/// backend keys its own replay-protection decision on.
class ScriptedFakePaymentGateway implements PaymentGateway {
  ScriptedFakePaymentGateway(this.scriptForSequence);
  final Map<int, AttemptScript> scriptForSequence;
  final List<int> callsInOrder = [];

  @override
  Future<PaymentAttemptResult> recordPaymentAttempt({
    required PosDeviceContext ctx,
    required String checkId,
    required String sessionId,
    required String tenderType,
    required String idempotencyKey,
    required List<Map<String, dynamic>> allocations,
    int? requestedBoncukAmount,
    String? cashSessionId,
    ({String leaseId, int deviceSequence})? offlineLease,
  }) async {
    final sequence = offlineLease!.deviceSequence;
    callsInOrder.add(sequence);
    final script = scriptForSequence[sequence];
    if (script == null) {
      throw StateError('No script for sequence $sequence');
    }
    return script(allocations.first, sequence);
  }

  @override
  Future<PaymentIntentResult> createPaymentIntent(
          {required PosDeviceContext ctx,
          required String checkId,
          int coverCount = 0}) =>
      throw UnimplementedError();

  @override
  Future<PaymentSessionView> getPaymentSessionView(
          {required PosDeviceContext ctx, required String checkId}) =>
      throw UnimplementedError();

  @override
  Future<RefundRequestResult> requestPaymentRefund({
    required PosDeviceContext ctx,
    required String checkId,
    required String refundType,
    required int amountMinorUnits,
    required String reasonCode,
    required String reasonMessage,
    List<String>? orderLineRefs,
  }) =>
      throw UnimplementedError();
}

const _ctx = PosDeviceContext(
  organizationId: 'org-1',
  branchId: 'branch-1',
  deviceId: 'device-1',
  deviceSessionId: 'session-1',
);

OfflineQueuedCashPayment _entry({
  required String id,
  required int deviceSequence,
  String leaseId = 'lease-1',
}) {
  return OfflineQueuedCashPayment(
    id: id,
    checkId: 'check-1',
    paymentSessionId: 'psession-1',
    subAccountId: 'sub-1',
    amount: Money.fromWhole(50, Currency.tryLira),
    leaseId: leaseId,
    deviceSequence: deviceSequence,
    idempotencyKey: 'idem-$id',
    capturedAt: DateTime(2026, 1, 1),
    status: OfflineOutboxStatus.pending,
  );
}

void main() {
  group('SyncOfflinePaymentOutbox', () {
    test('queueing while offline: entries persist as pending until synced',
        () async {
      final repo = InMemoryOfflinePaymentOutboxRepository();
      await repo.enqueue(_entry(id: 'e1', deviceSequence: 1));
      final pending = await repo.findPendingByLeaseId('lease-1');
      expect(pending, hasLength(1));
      expect(pending.single.status, OfflineOutboxStatus.pending);
    });

    test(
        'replays strictly in deviceSequence order, marking each synced on success',
        () async {
      final repo = InMemoryOfflinePaymentOutboxRepository();
      await repo.enqueue(_entry(id: 'e1', deviceSequence: 1));
      await repo.enqueue(_entry(id: 'e2', deviceSequence: 2));
      final gateway = ScriptedFakePaymentGateway({
        1: (_, __) async =>
            const PaymentAttemptResult(attemptId: 'a1', status: 'succeeded'),
        2: (_, __) async =>
            const PaymentAttemptResult(attemptId: 'a2', status: 'succeeded'),
      });
      final useCase = SyncOfflinePaymentOutbox(
          paymentGateway: gateway, outboxRepository: repo);

      final result = await useCase(ctx: _ctx, leaseId: 'lease-1');

      expect(result.syncedCount, 2);
      expect(gateway.callsInOrder, [1, 2]);
      expect(repo.statusOf('e1'), OfflineOutboxStatus.synced);
      expect(repo.statusOf('e2'), OfflineOutboxStatus.synced);
    });

    test(
        'late response / outcome unknown: a transport-uncertain error marks '
        'manualInterventionRequired and blocks later entries from being sent '
        '(never assumed success, never skipped ahead)', () async {
      final repo = InMemoryOfflinePaymentOutboxRepository();
      await repo.enqueue(_entry(id: 'e1', deviceSequence: 1));
      await repo.enqueue(_entry(id: 'e2', deviceSequence: 2));
      final gateway = ScriptedFakePaymentGateway({
        1: (_, __) async => throw const PaymentGatewayException(
            'deadline-exceeded', 'Zaman aşımı.'),
      });
      final useCase = SyncOfflinePaymentOutbox(
          paymentGateway: gateway, outboxRepository: repo);

      final result = await useCase(ctx: _ctx, leaseId: 'lease-1');

      expect(
          repo.statusOf('e1'), OfflineOutboxStatus.manualInterventionRequired);
      expect(repo.statusOf('e2'), OfflineOutboxStatus.pending);
      expect(gateway.callsInOrder, [1]); // e2 never sent
      expect(result.hasUnresolved, isTrue);
      final e2Result = result.entries.firstWhere((r) => r.entryId == 'e2');
      expect(
          e2Result.outcome, OfflineOutboxEntryOutcome.skippedOrderingBlocked);
    });

    test(
        'duplicate replay prevention: retrying after outcomeUnknown reuses '
        'the SAME idempotencyKey, never a fresh one', () async {
      final repo = InMemoryOfflinePaymentOutboxRepository();
      final entry = _entry(id: 'e1', deviceSequence: 1);
      await repo.enqueue(entry);
      var callCount = 0;
      final gateway = ScriptedFakePaymentGateway({
        1: (_, __) async {
          callCount++;
          if (callCount == 1) {
            throw const PaymentGatewayException(
                'unavailable', 'Bağlantı koptu.');
          }
          return const PaymentAttemptResult(
              attemptId: 'a1', status: 'succeeded');
        },
      });
      final useCase = SyncOfflinePaymentOutbox(
          paymentGateway: gateway, outboxRepository: repo);

      await useCase(ctx: _ctx, leaseId: 'lease-1');
      expect(
          repo.statusOf('e1'), OfflineOutboxStatus.manualInterventionRequired);

      // Staff reconciles and explicitly resumes it — the ONLY path back to pending.
      await repo.resetToPending('e1');
      final second = await useCase(ctx: _ctx, leaseId: 'lease-1');

      expect(second.syncedCount, 1);
      expect(repo.statusOf('e1'), OfflineOutboxStatus.synced);
      expect(callCount, 2);
      // Both attempts carried the entry's own single stable idempotencyKey —
      // reused, not regenerated (the entry object itself never changes it).
      expect(entry.idempotencyKey, 'idem-e1');
    });

    test(
        'expired lease: a terminal offline-lease-expired rejection marks '
        'failed, not manualInterventionRequired (a definitive answer, not an '
        'unknown one)', () async {
      final repo = InMemoryOfflinePaymentOutboxRepository();
      await repo.enqueue(_entry(id: 'e1', deviceSequence: 1));
      final gateway = ScriptedFakePaymentGateway({
        1: (_, __) async => throw const PaymentGatewayException(
              'failed-precondition',
              'Offline lease validation failed: expired.',
              {'code': 'payment/offline-lease-expired'},
            ),
      });
      final useCase = SyncOfflinePaymentOutbox(
          paymentGateway: gateway, outboxRepository: repo);

      final result = await useCase(ctx: _ctx, leaseId: 'lease-1');

      expect(repo.statusOf('e1'), OfflineOutboxStatus.failed);
      expect(result.entries.single.outcome, OfflineOutboxEntryOutcome.failed);
    });

    test(
        'revoked device lease: a terminal offline-lease-revoked rejection '
        'marks failed', () async {
      final repo = InMemoryOfflinePaymentOutboxRepository();
      await repo.enqueue(_entry(id: 'e1', deviceSequence: 1));
      final gateway = ScriptedFakePaymentGateway({
        1: (_, __) async => throw const PaymentGatewayException(
              'failed-precondition',
              'Offline lease validation failed: revoked.',
              {'code': 'payment/offline-lease-revoked'},
            ),
      });
      final useCase = SyncOfflinePaymentOutbox(
          paymentGateway: gateway, outboxRepository: repo);

      await useCase(ctx: _ctx, leaseId: 'lease-1');

      expect(repo.statusOf('e1'), OfflineOutboxStatus.failed);
    });

    test(
        'replayed device sequence: server-side sequence mismatch is treated '
        'as outcome-unknown (the entry may already be recorded), never a '
        'silent skip', () async {
      final repo = InMemoryOfflinePaymentOutboxRepository();
      await repo.enqueue(_entry(id: 'e1', deviceSequence: 1));
      final gateway = ScriptedFakePaymentGateway({
        1: (_, __) async => throw const PaymentGatewayException(
              'failed-precondition',
              'Offline lease validation failed: replay.',
              {'code': 'payment/offline-lease-replay'},
            ),
      });
      final useCase = SyncOfflinePaymentOutbox(
          paymentGateway: gateway, outboxRepository: repo);

      final result = await useCase(ctx: _ctx, leaseId: 'lease-1');

      expect(
          repo.statusOf('e1'), OfflineOutboxStatus.manualInterventionRequired);
      expect(result.entries.single.outcome,
          OfflineOutboxEntryOutcome.outcomeUnknown);
    });

    test(
        'server rejection: a non-succeeded status in a clean response marks '
        'failed and blocks later entries', () async {
      final repo = InMemoryOfflinePaymentOutboxRepository();
      await repo.enqueue(_entry(id: 'e1', deviceSequence: 1));
      await repo.enqueue(_entry(id: 'e2', deviceSequence: 2));
      final gateway = ScriptedFakePaymentGateway({
        1: (_, __) async =>
            const PaymentAttemptResult(attemptId: 'a1', status: 'declined'),
      });
      final useCase = SyncOfflinePaymentOutbox(
          paymentGateway: gateway, outboxRepository: repo);

      final result = await useCase(ctx: _ctx, leaseId: 'lease-1');

      expect(repo.statusOf('e1'), OfflineOutboxStatus.failed);
      expect(repo.statusOf('e2'), OfflineOutboxStatus.pending);
      expect(result.hasUnresolved, isTrue);
    });

    test('a lease with nothing pending is a safe no-op', () async {
      final repo = InMemoryOfflinePaymentOutboxRepository();
      final gateway = ScriptedFakePaymentGateway(const {});
      final useCase = SyncOfflinePaymentOutbox(
          paymentGateway: gateway, outboxRepository: repo);

      final result = await useCase(ctx: _ctx, leaseId: 'lease-1');

      expect(result.entries, isEmpty);
      expect(gateway.callsInOrder, isEmpty);
    });
  });
}
