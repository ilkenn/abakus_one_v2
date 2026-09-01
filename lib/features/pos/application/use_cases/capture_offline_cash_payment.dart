import '../../data/offline_lease_store.dart';
import '../../data/offline_payment_outbox_repository.dart';
import '../../domain/offline/offline_outbox_status.dart';
import '../../domain/offline/offline_queued_cash_payment.dart';
import '../../../../shared/models/money.dart';

sealed class CaptureOfflineCashPaymentResult {
  const CaptureOfflineCashPaymentResult();
}

class OfflineCashPaymentCaptured extends CaptureOfflineCashPaymentResult {
  const OfflineCashPaymentCaptured(this.queuedEntryId);
  final String queuedEntryId;
}

/// A refusal is always definitive and immediate — the whole point of
/// checking the held lease client-side before ever touching the durable
/// queue is that a cashier finds out INSTANTLY that offline cash isn't
/// available, rather than discovering it only when a doomed sync
/// eventually fails.
class OfflineCashPaymentRefused extends CaptureOfflineCashPaymentResult {
  const OfflineCashPaymentRefused(this.reason);
  final String reason;
}

/// AP-4 Wave E — the actual "capture a cash sale while offline" decision
/// point the checkout screen calls into. Distinct from
/// [SyncOfflinePaymentOutbox] (which drains what's already queued) — this
/// is what puts something IN the queue in the first place.
///
/// Every check the governing instruction's Section 3 named is enforced
/// here, client-side, BEFORE anything is persisted:
/// - a valid, non-expired, non-exhausted held lease must exist;
/// - the lease must permit the `cash` tender (the only offline tender
///   this app ever allows, matching the locked offline policy);
/// - the amount must not exceed the lease's own per-transaction ceiling;
/// - the lease's remaining transaction-count ceiling must not be
///   exhausted.
/// Organization/branch/trusted-device/entitlement matching is inherent —
/// the lease was issued by [EnsureOfflineLease] against exactly this
/// device's own [PosDeviceContext], so there is no separate value to
/// mismatch against.
///
/// The idempotency key is generated deterministically from
/// (checkId, leaseId, deviceSequence) — stable, never regenerated, and
/// computed BEFORE the entry is ever written, so even a process crash
/// between key generation and the enqueue write below can only ever
/// produce a duplicate ENQUEUE attempt with the identical key (itself
/// deduplicated by [OfflinePaymentOutboxRepository.enqueue]'s own
/// idempotent-by-id contract, since `id` and `idempotencyKey` are derived
/// from the same stable inputs), never a duplicate financial effect.
class CaptureOfflineCashPayment {
  const CaptureOfflineCashPayment({
    required OfflineLeaseStore leaseStore,
    required OfflinePaymentOutboxRepository outboxRepository,
  })  : _leaseStore = leaseStore,
        _outboxRepository = outboxRepository;

  final OfflineLeaseStore _leaseStore;
  final OfflinePaymentOutboxRepository _outboxRepository;

  Future<CaptureOfflineCashPaymentResult> call({
    required String checkId,
    required String paymentSessionId,
    required String subAccountId,
    required Money amount,
  }) async {
    final lease = await _leaseStore.currentLease();
    if (lease == null) {
      return const OfflineCashPaymentRefused(
        'Bu cihaz için geçerli bir offline yetki bulunmuyor. Bağlantı '
        'geri gelene kadar nakit tahsilat yapılamaz.',
      );
    }
    if (lease.isExpired) {
      return const OfflineCashPaymentRefused(
        'Offline yetkinin süresi dolmuş. Bağlantı geri gelene kadar nakit '
        'tahsilat yapılamaz.',
      );
    }
    if (!lease.hasRemainingCapacity) {
      return const OfflineCashPaymentRefused(
        'Bu offline yetki için izin verilen işlem sayısı doldu.',
      );
    }
    if (!lease.allowsTenderType('cash')) {
      return const OfflineCashPaymentRefused(
        'Bu offline yetki nakit tahsilata izin vermiyor.',
      );
    }
    if (amount.minorUnits > lease.maxTransactionValueMinorUnits) {
      return const OfflineCashPaymentRefused(
        'Tutar, offline yetkinin izin verdiği işlem başı üst sınırı aşıyor.',
      );
    }

    final deviceSequence =
        await _leaseStore.claimNextDeviceSequence(lease.leaseId);
    final id = 'offline-$checkId-${lease.leaseId}-$deviceSequence';
    final idempotencyKey = id;

    await _outboxRepository.enqueue(OfflineQueuedCashPayment(
      id: id,
      checkId: checkId,
      paymentSessionId: paymentSessionId,
      subAccountId: subAccountId,
      amount: amount,
      leaseId: lease.leaseId,
      deviceSequence: deviceSequence,
      idempotencyKey: idempotencyKey,
      capturedAt: DateTime.now(),
      status: OfflineOutboxStatus.pending,
    ));
    await _leaseStore.recordLocalUsage(lease.leaseId);

    return OfflineCashPaymentCaptured(id);
  }
}
