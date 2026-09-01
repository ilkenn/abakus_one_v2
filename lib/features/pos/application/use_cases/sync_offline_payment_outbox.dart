import '../../data/offline_payment_outbox_repository.dart';
import '../../data/payment_gateway.dart';
import '../../data/pos_action_gateway.dart';
import '../../domain/offline/offline_outbox_status.dart';
import '../../domain/offline/offline_queued_cash_payment.dart';

/// One queued entry's outcome from a single [SyncOfflinePaymentOutbox] pass.
enum OfflineOutboxEntryOutcome {
  synced,
  failed,
  outcomeUnknown,

  /// Never attempted this pass — an earlier entry in the SAME lease
  /// stopped the replay (strict device-sequence ordering), so this entry's
  /// own sequence number is not yet safe to present to the server.
  skippedOrderingBlocked,
}

class OfflineOutboxSyncEntryResult {
  const OfflineOutboxSyncEntryResult({
    required this.entryId,
    required this.outcome,
    this.detail,
  });
  final String entryId;
  final OfflineOutboxEntryOutcome outcome;
  final String? detail;
}

class OfflineOutboxSyncResult {
  const OfflineOutboxSyncResult({required this.entries});
  final List<OfflineOutboxSyncEntryResult> entries;

  int get syncedCount => entries
      .where((e) => e.outcome == OfflineOutboxEntryOutcome.synced)
      .length;
  bool get hasUnresolved => entries.any((e) =>
      e.outcome == OfflineOutboxEntryOutcome.outcomeUnknown ||
      e.outcome == OfflineOutboxEntryOutcome.failed);
}

/// Codes surfaced by `paymentEngine.ts`'s `validateOfflineLeaseForOperation`
/// gate (`failed-precondition`, `details.code == "payment/offline-lease-*"`)
/// — never re-derived client-side, read verbatim off the thrown exception.
const _kLeaseTerminalCodes = {
  'payment/offline-lease-revoked',
  'payment/offline-lease-expired',
  'payment/offline-lease-tender-not-allowed',
};

/// Transport-level uncertainty — mirrors `pos_checkout_screen.dart`'s own
/// `_isTransportUncertain` reasoning exactly: these codes mean the server
/// may or may not have actually processed the request, so the outcome must
/// never be assumed either way.
bool _isTransportUncertain(String code) {
  return code == 'deadline-exceeded' ||
      code == 'unavailable' ||
      code == 'internal' ||
      code == 'cancelled' ||
      code == 'unknown';
}

/// AP-4 Wave D — drains one device's durable offline cash-payment queue
/// (`OfflinePaymentOutboxRepository`, built in Wave C) through the real
/// `PaymentGateway.recordPaymentAttempt`, strictly in
/// [OfflineQueuedCashPayment.deviceSequence] order, one lease at a time.
///
/// **Strict ordering is the whole safety model.** The server rejects any
/// presented `deviceSequence` that isn't exactly
/// `lease.lastSeenDeviceSequence + 1` (`fiscalDomain.ts`'s
/// `validateOfflineLeaseForOperation`) — so the moment one entry's outcome
/// becomes anything other than a confirmed success, this use case STOPS
/// replaying that lease's remaining entries for the rest of THIS call
/// (`skippedOrderingBlocked`) rather than skipping ahead, which would
/// either desync the sequence counter or silently reorder financial
/// effects. A later call (after reconnection, or after staff resolves the
/// blocking entry via [OfflinePaymentOutboxRepository.resetToPending])
/// picks up again from wherever the queue's own persisted state left off.
///
/// **Idempotent by construction.** Every entry carries its own stable
/// [OfflineQueuedCashPayment.idempotencyKey], generated once at capture
/// time and never regenerated — replaying the same entry after a dropped
/// response (`outcomeUnknown`) reuses that exact key, so the server's own
/// existing idempotency-key short-circuit (the same mechanism every other
/// tender type in this codebase already relies on) is what actually
/// prevents a duplicate charge, not any cleverness in this class.
class SyncOfflinePaymentOutbox {
  const SyncOfflinePaymentOutbox({
    required PaymentGateway paymentGateway,
    required OfflinePaymentOutboxRepository outboxRepository,
  })  : _paymentGateway = paymentGateway,
        _outboxRepository = outboxRepository;

  final PaymentGateway _paymentGateway;
  final OfflinePaymentOutboxRepository _outboxRepository;

  /// Replays every still-[OfflineOutboxStatus.pending] entry for [leaseId],
  /// oldest [OfflineQueuedCashPayment.deviceSequence] first. Safe to call
  /// repeatedly (on reconnect, on a bounded retry timer, or from a manual
  /// "Şimdi Senkronize Et" action) — a lease with nothing pending, or one
  /// already blocked on an unresolved entry, is simply a no-op pass.
  Future<OfflineOutboxSyncResult> call({
    required PosDeviceContext ctx,
    required String leaseId,
  }) async {
    final pending = await _outboxRepository.findPendingByLeaseId(leaseId);
    final results = <OfflineOutboxSyncEntryResult>[];
    var blocked = false;

    for (final entry in pending) {
      if (blocked) {
        results.add(OfflineOutboxSyncEntryResult(
          entryId: entry.id,
          outcome: OfflineOutboxEntryOutcome.skippedOrderingBlocked,
        ));
        continue;
      }

      await _outboxRepository.markSyncing(entry.id);
      try {
        final result = await _paymentGateway.recordPaymentAttempt(
          ctx: ctx,
          checkId: entry.checkId,
          sessionId: entry.paymentSessionId,
          tenderType: 'cash',
          idempotencyKey: entry.idempotencyKey,
          allocations: [
            {
              'subAccountId': entry.subAccountId,
              'amountMinorUnits': entry.amount.minorUnits,
            },
          ],
          offlineLease: (
            leaseId: entry.leaseId,
            deviceSequence: entry.deviceSequence,
          ),
        );
        if (result.status == 'succeeded') {
          await _outboxRepository.markSynced(entry.id,
              syncedAt: DateTime.now());
          results.add(OfflineOutboxSyncEntryResult(
            entryId: entry.id,
            outcome: OfflineOutboxEntryOutcome.synced,
          ));
        } else {
          // Cash tenders have no provider-decline concept — any non-success
          // status here is an unexpected server-side rejection, never
          // silently treated as success.
          await _outboxRepository.markFailed(entry.id,
              reason:
                  'Sunucu beklenmeyen bir durum döndürdü: ${result.status}.');
          results.add(OfflineOutboxSyncEntryResult(
            entryId: entry.id,
            outcome: OfflineOutboxEntryOutcome.failed,
            detail: result.status,
          ));
          blocked = true;
        }
      } on PaymentGatewayException catch (error) {
        final leaseCode = error.details?['code'] as String?;
        if (leaseCode != null && _kLeaseTerminalCodes.contains(leaseCode)) {
          await _outboxRepository.markFailed(entry.id,
              reason: 'Offline yetki geçersiz: $leaseCode.');
          results.add(OfflineOutboxSyncEntryResult(
            entryId: entry.id,
            outcome: OfflineOutboxEntryOutcome.failed,
            detail: leaseCode,
          ));
        } else if (leaseCode == 'payment/offline-lease-replay' ||
            _isTransportUncertain(error.code)) {
          // A sequence-replay rejection means the server may already have
          // processed this exact entry (its counter moved past what we
          // expected) — exactly as uncertain as a dropped response.
          // Reconciliation (reading the canonical payment session/attempts
          // back) must resolve this before any retry, never an assumption
          // either way.
          await _outboxRepository.markManualInterventionRequired(entry.id,
              reason: leaseCode == 'payment/offline-lease-replay'
                  ? 'Sunucu farklı bir sıra numarası bekliyor — bu işlem daha önce işlenmiş olabilir, mutabakat gerekli.'
                  : 'Sunucu yanıtı alınamadı — sonuç bilinmiyor, mutabakat gerekli.');
          results.add(OfflineOutboxSyncEntryResult(
            entryId: entry.id,
            outcome: OfflineOutboxEntryOutcome.outcomeUnknown,
            detail: error.code,
          ));
        } else {
          await _outboxRepository.markFailed(entry.id, reason: error.message);
          results.add(OfflineOutboxSyncEntryResult(
            entryId: entry.id,
            outcome: OfflineOutboxEntryOutcome.failed,
            detail: error.code,
          ));
        }
        blocked = true;
      }
    }

    return OfflineOutboxSyncResult(entries: results);
  }
}
