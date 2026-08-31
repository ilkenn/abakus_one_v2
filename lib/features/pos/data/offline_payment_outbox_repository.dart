import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/offline/offline_outbox_status.dart';
import '../domain/offline/offline_queued_cash_payment.dart';

/// The device-local, DURABLE buffer of [OfflineQueuedCashPayment]s captured
/// while offline — AP-4 Wave C. Distinct from the server's own
/// `offlineLeases`/`fiscalOperationJournal` (the canonical, synced record):
/// this repository represents what one device is still holding onto, not
/// yet acknowledged by the backend. Mirrors
/// `OfflineLocationQueueRepository`'s own interface shape
/// (`lib/features/courier/data/offline_location_queue_repository.dart`) —
/// that repository is itself still in-memory-only (its own doc comment
/// says so), so it is a shape precedent, not a persistence one; this
/// repository's real implementation below is what actually satisfies the
/// governing instruction's "survives app termination/restart" requirement.
abstract interface class OfflinePaymentOutboxRepository {
  /// Idempotent by [OfflineQueuedCashPayment.id] — enqueuing the same entry
  /// twice (e.g. a UI double-tap before the first enqueue was confirmed)
  /// never creates a duplicate queue entry.
  Future<void> enqueue(OfflineQueuedCashPayment entry);

  /// Ordered oldest-first by [OfflineQueuedCashPayment.deviceSequence] —
  /// a sync must always replay in the exact order the device claimed each
  /// sequence number, matching the server's own strict-sequence
  /// replay-protection (`fiscalDomain.ts`'s `validateOfflineLeaseForOperation`).
  Future<List<OfflineQueuedCashPayment>> findPendingByLeaseId(String leaseId);

  /// Every entry regardless of status — for a reconciliation/history view.
  Future<List<OfflineQueuedCashPayment>> findAll();

  Future<void> markSyncing(String id);
  Future<void> markSynced(String id, {required DateTime syncedAt});
  Future<void> markFailed(String id, {required String reason});
  Future<void> markManualInterventionRequired(String id,
      {required String reason});

  /// A user may never locally delete an UNRESOLVED financial operation
  /// (the governing instruction's own locked rule) — this only removes an
  /// already-[OfflineOutboxStatus.synced] entry, once it is no longer
  /// needed locally. Deliberately has no "force delete" variant.
  Future<void> removeSynced(String id);
}

/// Real, durable implementation backed by `shared_preferences` — already a
/// pinned dependency (`pubspec.yaml`), so this adds no new one. The whole
/// queue is stored as one JSON array under a single key: this queue is
/// always small (bounded by a lease's own `maxTransactionCount`, hard-
/// capped at 50 server-side — `fiscalEngine.ts`), so a single read/write
/// per mutation is the right trade-off over a real embedded database,
/// which this codebase has no precedent for and would be a new-dependency
/// decision of its own.
class SharedPreferencesOfflinePaymentOutboxRepository
    implements OfflinePaymentOutboxRepository {
  SharedPreferencesOfflinePaymentOutboxRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _storageKey = 'pos_offline_payment_outbox_v1';

  List<OfflineQueuedCashPayment> _readAll() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<Object?>;
    return decoded
        .map(
            (e) => OfflineQueuedCashPayment.fromJson(e as Map<String, Object?>))
        .toList();
  }

  Future<void> _writeAll(List<OfflineQueuedCashPayment> entries) async {
    final encoded = jsonEncode(entries.map((e) => e.toJson()).toList());
    await _prefs.setString(_storageKey, encoded);
  }

  @override
  Future<void> enqueue(OfflineQueuedCashPayment entry) async {
    final all = _readAll();
    if (all.any((e) => e.id == entry.id)) return;
    all.add(entry);
    await _writeAll(all);
  }

  @override
  Future<List<OfflineQueuedCashPayment>> findPendingByLeaseId(
      String leaseId) async {
    final pending = _readAll()
        .where((e) =>
            e.leaseId == leaseId && e.status == OfflineOutboxStatus.pending)
        .toList()
      ..sort((a, b) => a.deviceSequence.compareTo(b.deviceSequence));
    return List.unmodifiable(pending);
  }

  @override
  Future<List<OfflineQueuedCashPayment>> findAll() async {
    final all = _readAll()
      ..sort((a, b) => a.deviceSequence.compareTo(b.deviceSequence));
    return List.unmodifiable(all);
  }

  Future<void> _updateOne(
    String id,
    OfflineQueuedCashPayment Function(OfflineQueuedCashPayment) update,
  ) async {
    final all = _readAll();
    final index = all.indexWhere((e) => e.id == id);
    if (index == -1) return;
    all[index] = update(all[index]);
    await _writeAll(all);
  }

  @override
  Future<void> markSyncing(String id) =>
      _updateOne(id, (e) => e.copyWith(status: OfflineOutboxStatus.syncing));

  @override
  Future<void> markSynced(String id, {required DateTime syncedAt}) =>
      _updateOne(
        id,
        (e) =>
            e.copyWith(status: OfflineOutboxStatus.synced, syncedAt: syncedAt),
      );

  @override
  Future<void> markFailed(String id, {required String reason}) => _updateOne(
        id,
        (e) => e.copyWith(
            status: OfflineOutboxStatus.failed, failureReason: reason),
      );

  @override
  Future<void> markManualInterventionRequired(String id,
          {required String reason}) =>
      _updateOne(
        id,
        (e) => e.copyWith(
          status: OfflineOutboxStatus.manualInterventionRequired,
          failureReason: reason,
        ),
      );

  @override
  Future<void> removeSynced(String id) async {
    final all = _readAll();
    final target = all.where((e) => e.id == id);
    if (target.isEmpty || target.first.status != OfflineOutboxStatus.synced) {
      return;
    }
    all.removeWhere((e) => e.id == id);
    await _writeAll(all);
  }
}
