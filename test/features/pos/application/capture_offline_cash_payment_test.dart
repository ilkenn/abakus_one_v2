import 'package:abakus_one_v2/features/pos/application/use_cases/capture_offline_cash_payment.dart';
import 'package:abakus_one_v2/features/pos/data/offline_lease_store.dart';
import 'package:abakus_one_v2/features/pos/data/offline_payment_outbox_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/offline/held_offline_lease.dart';
import 'package:abakus_one_v2/features/pos/domain/offline/offline_outbox_status.dart';
import 'package:abakus_one_v2/features/pos/domain/offline/offline_queued_cash_payment.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

class InMemoryOfflineLeaseStore implements OfflineLeaseStore {
  HeldOfflineLease? _lease;
  final Map<String, int> _sequences = {};

  @override
  Future<HeldOfflineLease?> currentLease() async => _lease;

  @override
  Future<void> saveLease(HeldOfflineLease lease) async => _lease = lease;

  @override
  Future<int> claimNextDeviceSequence(String leaseId) async {
    final next = (_sequences[leaseId] ?? 0) + 1;
    _sequences[leaseId] = next;
    return next;
  }

  @override
  Future<void> recordLocalUsage(String leaseId) async {
    if (_lease == null || _lease!.leaseId != leaseId) return;
    _lease = _lease!
        .copyWith(transactionsUsedLocally: _lease!.transactionsUsedLocally + 1);
  }

  @override
  Future<void> clearLease() async => _lease = null;
}

class InMemoryOfflinePaymentOutboxRepository
    implements OfflinePaymentOutboxRepository {
  final List<OfflineQueuedCashPayment> entries = [];

  @override
  Future<void> enqueue(OfflineQueuedCashPayment entry) async {
    if (entries.any((e) => e.id == entry.id)) return;
    entries.add(entry);
  }

  @override
  Future<List<OfflineQueuedCashPayment>> findPendingByLeaseId(
      String leaseId) async {
    return entries
        .where((e) =>
            e.leaseId == leaseId && e.status == OfflineOutboxStatus.pending)
        .toList()
      ..sort((a, b) => a.deviceSequence.compareTo(b.deviceSequence));
  }

  @override
  Future<List<OfflineQueuedCashPayment>> findAll() async =>
      List.unmodifiable(entries);

  @override
  Future<void> markSyncing(String id) async {}
  @override
  Future<void> markSynced(String id, {required DateTime syncedAt}) async {}
  @override
  Future<void> markFailed(String id, {required String reason}) async {}
  @override
  Future<void> markManualInterventionRequired(String id,
      {required String reason}) async {}
  @override
  Future<void> resetToPending(String id) async {}
  @override
  Future<void> removeSynced(String id) async {}
}

HeldOfflineLease _validLease({
  int maxTransactionCount = 10,
  int maxTransactionValueMinorUnits = 500000,
  List<String> allowedTenderTypes = const ['cash'],
  int transactionsUsedLocally = 0,
  DateTime? expiresAt,
}) {
  return HeldOfflineLease(
    leaseId: 'lease-1',
    expiresAt: expiresAt ?? DateTime.now().add(const Duration(hours: 4)),
    allowedTenderTypes: allowedTenderTypes,
    maxTransactionCount: maxTransactionCount,
    maxTransactionValueMinorUnits: maxTransactionValueMinorUnits,
    catalogVersion: DateTime.now().toIso8601String(),
    transactionsUsedLocally: transactionsUsedLocally,
  );
}

void main() {
  group('CaptureOfflineCashPayment', () {
    test('refuses when no lease is held', () async {
      final leaseStore = InMemoryOfflineLeaseStore();
      final outbox = InMemoryOfflinePaymentOutboxRepository();
      final useCase = CaptureOfflineCashPayment(
          leaseStore: leaseStore, outboxRepository: outbox);

      final result = await useCase(
        checkId: 'check-1',
        paymentSessionId: 'session-1',
        subAccountId: 'sub-1',
        amount: Money.fromWhole(50, Currency.tryLira),
      );

      expect(result, isA<OfflineCashPaymentRefused>());
      expect(outbox.entries, isEmpty);
    });

    test('refuses when the held lease is expired', () async {
      final leaseStore = InMemoryOfflineLeaseStore();
      await leaseStore.saveLease(_validLease(
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1))));
      final outbox = InMemoryOfflinePaymentOutboxRepository();
      final useCase = CaptureOfflineCashPayment(
          leaseStore: leaseStore, outboxRepository: outbox);

      final result = await useCase(
        checkId: 'check-1',
        paymentSessionId: 'session-1',
        subAccountId: 'sub-1',
        amount: Money.fromWhole(50, Currency.tryLira),
      );

      expect(result, isA<OfflineCashPaymentRefused>());
      expect(outbox.entries, isEmpty);
    });

    test('refuses when the lease transaction-count ceiling is exhausted',
        () async {
      final leaseStore = InMemoryOfflineLeaseStore();
      await leaseStore.saveLease(
          _validLease(maxTransactionCount: 2, transactionsUsedLocally: 2));
      final outbox = InMemoryOfflinePaymentOutboxRepository();
      final useCase = CaptureOfflineCashPayment(
          leaseStore: leaseStore, outboxRepository: outbox);

      final result = await useCase(
        checkId: 'check-1',
        paymentSessionId: 'session-1',
        subAccountId: 'sub-1',
        amount: Money.fromWhole(50, Currency.tryLira),
      );

      expect(result, isA<OfflineCashPaymentRefused>());
      expect(outbox.entries, isEmpty);
    });

    test('refuses when the lease does not allow the cash tender', () async {
      final leaseStore = InMemoryOfflineLeaseStore();
      await leaseStore.saveLease(_validLease(allowedTenderTypes: const []));
      final outbox = InMemoryOfflinePaymentOutboxRepository();
      final useCase = CaptureOfflineCashPayment(
          leaseStore: leaseStore, outboxRepository: outbox);

      final result = await useCase(
        checkId: 'check-1',
        paymentSessionId: 'session-1',
        subAccountId: 'sub-1',
        amount: Money.fromWhole(50, Currency.tryLira),
      );

      expect(result, isA<OfflineCashPaymentRefused>());
      expect(outbox.entries, isEmpty);
    });

    test('refuses when the amount exceeds the lease per-transaction ceiling',
        () async {
      final leaseStore = InMemoryOfflineLeaseStore();
      await leaseStore
          .saveLease(_validLease(maxTransactionValueMinorUnits: 1000));
      final outbox = InMemoryOfflinePaymentOutboxRepository();
      final useCase = CaptureOfflineCashPayment(
          leaseStore: leaseStore, outboxRepository: outbox);

      final result = await useCase(
        checkId: 'check-1',
        paymentSessionId: 'session-1',
        subAccountId: 'sub-1',
        amount: Money.fromWhole(50, Currency.tryLira),
      );

      expect(result, isA<OfflineCashPaymentRefused>());
      expect(outbox.entries, isEmpty);
    });

    test(
        'captures successfully: enqueues durably, claims a monotonic '
        'sequence, and advances local usage', () async {
      final leaseStore = InMemoryOfflineLeaseStore();
      await leaseStore.saveLease(_validLease());
      final outbox = InMemoryOfflinePaymentOutboxRepository();
      final useCase = CaptureOfflineCashPayment(
          leaseStore: leaseStore, outboxRepository: outbox);

      final result = await useCase(
        checkId: 'check-1',
        paymentSessionId: 'session-1',
        subAccountId: 'sub-1',
        amount: Money.fromWhole(50, Currency.tryLira),
      );

      expect(result, isA<OfflineCashPaymentCaptured>());
      expect(outbox.entries, hasLength(1));
      expect(outbox.entries.single.deviceSequence, 1);
      expect(outbox.entries.single.status, OfflineOutboxStatus.pending);
      final lease = await leaseStore.currentLease();
      expect(lease!.transactionsUsedLocally, 1);
    });

    test('each capture claims the next monotonic sequence, never reused',
        () async {
      final leaseStore = InMemoryOfflineLeaseStore();
      await leaseStore.saveLease(_validLease(maxTransactionCount: 5));
      final outbox = InMemoryOfflinePaymentOutboxRepository();
      final useCase = CaptureOfflineCashPayment(
          leaseStore: leaseStore, outboxRepository: outbox);

      await useCase(
        checkId: 'check-1',
        paymentSessionId: 'session-1',
        subAccountId: 'sub-1',
        amount: Money.fromWhole(10, Currency.tryLira),
      );
      await useCase(
        checkId: 'check-2',
        paymentSessionId: 'session-2',
        subAccountId: 'sub-2',
        amount: Money.fromWhole(10, Currency.tryLira),
      );

      final sequences = outbox.entries.map((e) => e.deviceSequence).toList()
        ..sort();
      expect(sequences, [1, 2]);
    });

    test(
        'the idempotency key is generated deterministically before the '
        'durable write, from (checkId, leaseId, deviceSequence)', () async {
      final leaseStore = InMemoryOfflineLeaseStore();
      await leaseStore.saveLease(_validLease());
      final outbox = InMemoryOfflinePaymentOutboxRepository();
      final useCase = CaptureOfflineCashPayment(
          leaseStore: leaseStore, outboxRepository: outbox);

      await useCase(
        checkId: 'check-9',
        paymentSessionId: 'session-9',
        subAccountId: 'sub-9',
        amount: Money.fromWhole(10, Currency.tryLira),
      );

      final entry = outbox.entries.single;
      expect(entry.idempotencyKey, 'offline-check-9-lease-1-1');
      expect(entry.id, entry.idempotencyKey);
    });
  });
}
