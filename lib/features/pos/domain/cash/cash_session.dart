import 'cash_closing.dart';
import 'cash_opening.dart';
import 'cash_session_status.dart';

/// One drawer's cash-handling session, from opening to closing — the
/// aggregate every `CashMovement`/`CashCount`/`CashReconciliation` is
/// scoped to.
///
/// **Append-only**: never mutated in place — every status change produces
/// a new instance with the same [id] and an incremented [revision];
/// `CashSessionRepository.save` always appends (mirrors `PaymentSession`/
/// `OrderClosure`'s existing shape).
///
/// Only one [CashSessionStatus.active]-or-non-[CashSessionStatus.closed]
/// session may exist per drawer at a time — enforced by
/// `OpenCashDrawer`/`CashSessionRepository.findActiveByDrawerId`, not by
/// this class itself (this class has no way to see other sessions).
class CashSession {
  const CashSession({
    required this.id,
    required this.drawerId,
    required this.branchId,
    required this.status,
    required this.opening,
    this.closing,
    required this.revision,
  });

  /// Stable across every revision — what `CashSessionRepository` queries
  /// by.
  final String id;

  final String drawerId;
  final String branchId;

  final CashSessionStatus status;
  final CashOpening opening;

  /// `null` until [status] reaches [CashSessionStatus.closed].
  final CashClosing? closing;

  /// Optimistic-concurrency counter — starts at 1.
  final int revision;

  bool get isActive => status != CashSessionStatus.closed;

  CashSession copyWith({
    CashSessionStatus? status,
    CashClosing? closing,
    int? revision,
  }) {
    return CashSession(
      id: id,
      drawerId: drawerId,
      branchId: branchId,
      status: status ?? this.status,
      opening: opening,
      closing: closing ?? this.closing,
      revision: revision ?? this.revision,
    );
  }
}
