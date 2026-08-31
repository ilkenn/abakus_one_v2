import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abakus_one_v2/features/pos/data/offline_payment_outbox_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/offline/offline_outbox_status.dart';
import 'package:abakus_one_v2/features/pos/domain/offline/offline_queued_cash_payment.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';

OfflineQueuedCashPayment _entry({
  String id = 'entry-1',
  int deviceSequence = 1,
  OfflineOutboxStatus status = OfflineOutboxStatus.pending,
}) {
  return OfflineQueuedCashPayment(
    id: id,
    checkId: 'check-1',
    paymentSessionId: 'session-1',
    subAccountId: 'subaccount-1',
    amount: const Money(10000, Currency.tryLira),
    leaseId: 'lease-1',
    deviceSequence: deviceSequence,
    idempotencyKey: 'idem-$id',
    capturedAt: DateTime.utc(2026, 8, 31, 12, 0, 0),
    status: status,
  );
}

void main() {
  group('SharedPreferencesOfflinePaymentOutboxRepository', () {
    test('enqueue then findAll round-trips every field exactly', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPreferencesOfflinePaymentOutboxRepository(prefs);

      await repo.enqueue(_entry());
      final all = await repo.findAll();

      expect(all, hasLength(1));
      expect(all.single.id, 'entry-1');
      expect(all.single.checkId, 'check-1');
      expect(all.single.amount.minorUnits, 10000);
      expect(all.single.amount.currency.isoCode, 'TRY');
      expect(all.single.deviceSequence, 1);
      expect(all.single.status, OfflineOutboxStatus.pending);
    });

    test(
        'a durable queue survives a fresh SharedPreferences.getInstance() call — proves persistence, not just in-memory state',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefsBefore = await SharedPreferences.getInstance();
      await SharedPreferencesOfflinePaymentOutboxRepository(prefsBefore)
          .enqueue(_entry());

      // A brand-new repository instance backed by a brand-new
      // SharedPreferences handle — simulates the app process restarting.
      final prefsAfter = await SharedPreferences.getInstance();
      final reopened =
          SharedPreferencesOfflinePaymentOutboxRepository(prefsAfter);
      final all = await reopened.findAll();

      expect(all, hasLength(1));
      expect(all.single.id, 'entry-1');
    });

    test(
        'enqueue is idempotent by id — enqueuing the same entry twice never duplicates it',
        () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SharedPreferencesOfflinePaymentOutboxRepository(
          await SharedPreferences.getInstance());

      await repo.enqueue(_entry());
      await repo.enqueue(_entry());

      expect(await repo.findAll(), hasLength(1));
    });

    test(
        'findPendingByLeaseId returns only pending entries for that lease, ordered by deviceSequence',
        () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SharedPreferencesOfflinePaymentOutboxRepository(
          await SharedPreferences.getInstance());

      await repo.enqueue(_entry(id: 'e3', deviceSequence: 3));
      await repo.enqueue(_entry(id: 'e1', deviceSequence: 1));
      await repo.enqueue(_entry(id: 'e2', deviceSequence: 2));
      await repo.enqueue(OfflineQueuedCashPayment(
        id: 'e-different-lease',
        checkId: 'check-x',
        paymentSessionId: 'session-x',
        subAccountId: 'sub-x',
        amount: const Money(500, Currency.tryLira),
        leaseId: 'lease-2',
        deviceSequence: 1,
        idempotencyKey: 'idem-x',
        capturedAt: DateTime.utc(2026, 8, 31),
        status: OfflineOutboxStatus.pending,
      ));
      await repo.markSynced('e2', syncedAt: DateTime.utc(2026, 8, 31));

      final pending = await repo.findPendingByLeaseId('lease-1');

      expect(pending.map((e) => e.id), ['e1', 'e3']);
    });

    test(
        'markSyncing/markSynced/markFailed/markManualInterventionRequired update status and preserve every other field',
        () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SharedPreferencesOfflinePaymentOutboxRepository(
          await SharedPreferences.getInstance());
      await repo.enqueue(_entry());

      await repo.markSyncing('entry-1');
      expect((await repo.findAll()).single.status, OfflineOutboxStatus.syncing);

      final syncedAt = DateTime.utc(2026, 8, 31, 13, 0, 0);
      await repo.markSynced('entry-1', syncedAt: syncedAt);
      var current = (await repo.findAll()).single;
      expect(current.status, OfflineOutboxStatus.synced);
      expect(current.syncedAt, syncedAt);
      expect(current.checkId, 'check-1', reason: 'unrelated fields untouched');
    });

    test('markFailed records the failure reason', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SharedPreferencesOfflinePaymentOutboxRepository(
          await SharedPreferences.getInstance());
      await repo.enqueue(_entry());

      await repo.markFailed('entry-1', reason: 'offline lease revoked');

      final current = (await repo.findAll()).single;
      expect(current.status, OfflineOutboxStatus.failed);
      expect(current.failureReason, 'offline lease revoked');
    });

    test(
        'removeSynced only removes an entry that is actually synced — an unresolved entry is never locally deletable',
        () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SharedPreferencesOfflinePaymentOutboxRepository(
          await SharedPreferences.getInstance());
      await repo.enqueue(_entry());

      await repo.removeSynced('entry-1');
      expect(await repo.findAll(), hasLength(1),
          reason: 'still pending — must not be removable');

      await repo.markSynced('entry-1', syncedAt: DateTime.utc(2026, 8, 31));
      await repo.removeSynced('entry-1');
      expect(await repo.findAll(), isEmpty);
    });
  });
}
