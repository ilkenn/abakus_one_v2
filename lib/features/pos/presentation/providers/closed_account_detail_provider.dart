import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../orders/domain/models/order.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../../orders/domain/receipt/receipt.dart';
import '../../application/use_cases/reopen_closed_order.dart';
import '../../application/use_cases/request_duplicate_receipt.dart';
import '../../domain/audit/closure_audit_entry.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/models/order_closure.dart';
import '../../domain/receipts/receipt_print_result.dart';
import 'order_closure_dependencies_provider.dart';

/// State for [ClosedAccountDetailScreen] — mirrors every other POS
/// controller's one-immutable-class-with-a-status-field shape (Phase 3
/// Sprint 3B convention, carried through this sprint).
class ClosedAccountDetailState {
  const ClosedAccountDetailState({
    this.closure,
    this.auditEntries = const [],
    this.isBusy = false,
    this.error,
  });

  final OrderClosure? closure;
  final List<ClosureAuditEntry> auditEntries;
  final bool isBusy;
  final String? error;

  ClosedAccountDetailState copyWith({
    OrderClosure? closure,
    List<ClosureAuditEntry>? auditEntries,
    bool? isBusy,
    String? error,
    bool clearError = false,
  }) {
    return ClosedAccountDetailState(
      closure: closure ?? this.closure,
      auditEntries: auditEntries ?? this.auditEntries,
      isBusy: isBusy ?? this.isBusy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Owns loading and mutating one [OrderClosure]'s detail view — the one
/// place `ClosedAccountDetailScreen`'s actions become calls into the
/// application-layer use cases, per this codebase's standing "never call
/// a use case/repository directly from a widget" rule.
class ClosedAccountDetailController extends Notifier<ClosedAccountDetailState> {
  @override
  ClosedAccountDetailState build() => const ClosedAccountDetailState();

  Future<void> load(
      {required String closureId, required OrderId orderId}) async {
    final closure = await ref
        .read(orderClosureRepositoryProvider)
        .findByClosureId(closureId);
    final entries = await ref
        .read(closureAuditEntryRepositoryProvider)
        .findByOrderId(orderId);
    state = state.copyWith(closure: closure, auditEntries: entries);
  }

  Future<void> reopen({
    required PosAuthorizationPolicy authorizationPolicy,
    required String reason,
    required String performedByStaffId,
  }) async {
    final closure = state.closure;
    if (closure == null || state.isBusy) return;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final updated = await ReopenClosedOrder(
        clock: ref.read(clockProvider),
        authorizationPolicy: authorizationPolicy,
        auditRepository: ref.read(closureAuditEntryRepositoryProvider),
      )(
        closure: closure,
        expectedRevision: closure.revision,
        reason: reason,
        performedByStaffId: performedByStaffId,
      );
      await ref.read(orderClosureRepositoryProvider).save(updated);
      final entries = await ref
          .read(closureAuditEntryRepositoryProvider)
          .findByOrderId(closure.orderId);
      state = state.copyWith(
          closure: updated, auditEntries: entries, isBusy: false);
    } on BusinessRuleViolation catch (violation) {
      state = state.copyWith(isBusy: false, error: violation.description);
    }
  }

  Future<ReceiptPrintResult?> requestDuplicateReceipt({
    required PosAuthorizationPolicy authorizationPolicy,
    required Order order,
    required String requestedByStaffId,
    required String requestId,
  }) async {
    if (state.isBusy) return null;
    state = state.copyWith(isBusy: true, clearError: true);
    final clock = ref.read(clockProvider);
    final receipt = Receipt(
      receiptNumber: '${order.id.value}-duplicate-$requestId',
      orderId: order.id,
      orderNumber: order.orderNumber,
      issuedAt: clock.now(),
      summary: order.pricing,
    );
    try {
      final result = await RequestDuplicateReceipt(
        clock: clock,
        authorizationPolicy: authorizationPolicy,
        auditRepository: ref.read(closureAuditEntryRepositoryProvider),
        printProvider: ref.read(receiptPrintProviderProvider),
      )(
        orderId: order.id,
        receipt: receipt,
        requestedByStaffId: requestedByStaffId,
        requestId: requestId,
      );
      final entries = await ref
          .read(closureAuditEntryRepositoryProvider)
          .findByOrderId(order.id);
      state = state.copyWith(auditEntries: entries, isBusy: false);
      return result;
    } on BusinessRuleViolation catch (violation) {
      state = state.copyWith(isBusy: false, error: violation.description);
      return null;
    }
  }
}

final closedAccountDetailProvider =
    NotifierProvider<ClosedAccountDetailController, ClosedAccountDetailState>(
        () {
  return ClosedAccountDetailController();
});
