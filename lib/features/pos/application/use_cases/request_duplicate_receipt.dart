import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../orders/domain/models/order_actor.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../../orders/domain/receipt/receipt.dart';
import '../../data/closure_audit_entry_repository.dart';
import '../../domain/audit/closure_audit_entry.dart';
import '../../domain/audit/closure_audit_event_type.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/authorization/pos_authorized_action.dart';
import '../../domain/receipts/receipt_print_provider.dart';
import '../../domain/receipts/receipt_print_result.dart';

/// Requests a duplicate/reprinted [Receipt] for an already-closed order —
/// the "duplicate receipt" foundation (`docs/decisions.md` ADR-012): no
/// real printing happens this sprint ([ReceiptPrintProvider] has no real
/// implementation), but the action itself, its audit trail, and the seam
/// a future print provider plugs into all exist and are exercised.
///
/// Always appends a [ClosureAuditEntry]
/// ([ClosureAuditEventType.duplicateReceiptRequested]) — regardless of
/// whether the underlying print attempt actually succeeds, since the
/// *request* itself is the auditable event (a cashier asked for a
/// reprint), independent of whether a printer was available to fulfill it.
class RequestDuplicateReceipt {
  const RequestDuplicateReceipt({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required ClosureAuditEntryRepository auditRepository,
    required ReceiptPrintProvider printProvider,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _auditRepository = auditRepository,
        _printProvider = printProvider;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final ClosureAuditEntryRepository _auditRepository;
  final ReceiptPrintProvider _printProvider;

  /// [requestId] is externally supplied — like every other correlation id
  /// in this codebase, never generated from a timestamp/random value here.
  /// It disambiguates repeated duplicate-receipt requests for the same
  /// [receipt] in the audit trail.
  ///
  /// Requires [PosAuthorizedAction.reprintOrDuplicateReceipt] — added
  /// Phase 3 Sprint 3D to close a gap this use case originally shipped
  /// with (Sprint 3C) before that action existed. Throws
  /// [AuthorizationDeniedViolation] if denied; no audit entry or print
  /// attempt happens in that case.
  Future<ReceiptPrintResult> call({
    required OrderId orderId,
    required Receipt receipt,
    required String requestedByStaffId,
    required String requestId,
  }) async {
    final authResult = await _authorizationPolicy.authorize(
      action: PosAuthorizedAction.reprintOrDuplicateReceipt,
      actorStaffId: requestedByStaffId,
      context: {'orderId': orderId.value},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(
        actionName: PosAuthorizedAction.reprintOrDuplicateReceipt.name,
      );
    }

    final result = await _printProvider.print(receipt);
    final now = _clock.now();

    await _auditRepository.appendEvent(
      orderId,
      ClosureAuditEntry(
        id: '${receipt.receiptNumber}-duplicate-$requestId',
        type: ClosureAuditEventType.duplicateReceiptRequested,
        description: 'Duplicate receipt requested (${result.status.name})',
        actor: OrderActor.staff,
        timestamp: now,
        newValue: result.status.name,
      ),
    );

    return result;
  }
}
