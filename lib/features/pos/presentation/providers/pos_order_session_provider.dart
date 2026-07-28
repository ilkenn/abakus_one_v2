import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../menu/domain/models/menu_product.dart';
import '../../../menu/domain/models/selected_modifier.dart';
import '../../../orders/domain/discounts/discount.dart';
import '../../../orders/domain/models/order.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../../orders/presentation/providers/order_identity_provider.dart';
import '../../application/errors/pos_application_error.dart';
import '../../application/use_cases/add_product_to_pos_order.dart';
import '../../application/use_cases/apply_pos_discount.dart';
import '../../application/use_cases/calculate_pos_order_totals.dart';
import '../../application/use_cases/cancel_pos_order_session.dart';
import '../../application/use_cases/remove_pos_order_line.dart';
import '../../application/use_cases/start_pos_order.dart';
import '../../application/use_cases/submit_pos_order.dart';
import '../../application/use_cases/update_pos_order_line.dart';
import '../../application/use_cases/update_pos_order_notes.dart';
import '../../domain/models/pos_order_session.dart';
import 'pos_dependencies_provider.dart';

enum PosOrderSessionStatus { idle, editing, submitting, submitted, failure }

/// The POS cashier flow's single state class — approved architecture
/// decision, Phase 3 Sprint 3B: one immutable class with a
/// [PosOrderSessionStatus] field, not a sealed state union (matches this
/// codebase's existing `AuthState`/`OtpState` convention rather than
/// introducing a new one).
class PosOrderSessionState {
  const PosOrderSessionState({
    this.status = PosOrderSessionStatus.idle,
    this.session,
    this.submittedOrder,
    this.error,
  });

  final PosOrderSessionStatus status;

  /// The in-progress session — present while `editing`/`submitting`, and
  /// (per the approved "preserve session on errors" requirement) still
  /// present while `failure`, so the cashier's work is never lost.
  /// `null` while `idle` and after a successful `submitted` transition
  /// (see [submittedOrder]).
  final PosOrderSession? session;

  /// The frozen result of a successful submission. Only ever non-null
  /// while `status` is `submitted`.
  final Order? submittedOrder;

  /// Only ever non-null while `status` is `failure`.
  final PosApplicationError? error;

  PosOrderSessionState copyWith({
    PosOrderSessionStatus? status,
    PosOrderSession? session,
    bool clearSession = false,
    Order? submittedOrder,
    bool clearSubmittedOrder = false,
    PosApplicationError? error,
    bool clearError = false,
  }) {
    return PosOrderSessionState(
      status: status ?? this.status,
      session: clearSession ? null : (session ?? this.session),
      submittedOrder:
          clearSubmittedOrder ? null : (submittedOrder ?? this.submittedOrder),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Owns the active POS order session end to end — the one place the
/// cashier UI's actions become calls into the application-layer use
/// cases. No business calculation happens in the UI; every mutation here
/// delegates to a use case and only ever updates [state] with the result.
class PosOrderSessionController extends Notifier<PosOrderSessionState> {
  @override
  PosOrderSessionState build() => const PosOrderSessionState();

  bool get _isBusy => state.status == PosOrderSessionStatus.submitting;

  void startSession({
    required String sessionId,
    required String branchId,
    required String openedByStaffId,
    required OrderChannel channel,
    String? tableId,
    String? tableSessionId,
  }) {
    if (_isBusy) return;
    final session = StartPosOrder(clock: ref.read(clockProvider)).call(
      sessionId: sessionId,
      branchId: branchId,
      openedByStaffId: openedByStaffId,
      channel: channel,
      tableId: tableId,
      tableSessionId: tableSessionId,
    );
    state = PosOrderSessionState(
      status: PosOrderSessionStatus.editing,
      session: session,
    );
    _saveDraft(session);
  }

  Future<void> addProduct({
    required MenuProduct product,
    List<SelectedModifier> selectedModifiers = const [],
    int quantity = 1,
    String note = '',
  }) async {
    final session = state.session;
    if (session == null || _isBusy) return;
    await _applyMutation(
      () => AddProductToPosOrder(clock: ref.read(clockProvider)).call(
        session: session,
        product: product,
        selectedModifiers: selectedModifiers,
        quantity: quantity,
        note: note,
      ),
    );
  }

  Future<void> updateLine({
    required int lineIndex,
    int? quantity,
    String? note,
  }) async {
    final session = state.session;
    if (session == null || _isBusy) return;
    await _applyMutation(
      () => UpdatePosOrderLine(clock: ref.read(clockProvider)).call(
        session: session,
        lineIndex: lineIndex,
        quantity: quantity,
        note: note,
      ),
    );
  }

  Future<void> removeLine(int lineIndex) async {
    final session = state.session;
    if (session == null || _isBusy) return;
    await _applyMutation(
      () => RemovePosOrderLine(clock: ref.read(clockProvider)).call(
        session: session,
        lineIndex: lineIndex,
      ),
    );
  }

  Future<void> applyDiscount(Discount? discount) async {
    final session = state.session;
    if (session == null || _isBusy) return;
    await _applyMutation(
      () => ApplyPosDiscount(clock: ref.read(clockProvider)).call(
        session: session,
        discount: discount,
      ),
    );
  }

  Future<void> updateNotes({String? customerNote, String? kitchenNote}) async {
    final session = state.session;
    if (session == null || _isBusy) return;
    await _applyMutation(
      () => UpdatePosOrderNotes(clock: ref.read(clockProvider)).call(
        session: session,
        customerNote: customerNote,
        kitchenNote: kitchenNote,
      ),
    );
  }

  /// Forces a totals recalculation without any other change — the other
  /// mutation methods already do this as their final step, so this exists
  /// mainly for symmetry with the approved use-case list and for a UI
  /// action that wants to refresh pricing without editing anything else.
  void recalculateTotals() {
    final session = state.session;
    if (session == null || _isBusy) return;
    final pricing = const CalculatePosOrderTotals()(session);
    final updated = session.copyWith(pricing: pricing);
    state = state.copyWith(
      status: PosOrderSessionStatus.editing,
      session: updated,
    );
  }

  /// Submits the current session. Duplicate-submission prevention is
  /// enforced here, not inside `SubmitPosOrder` itself — [state]`.status`
  /// is already the single source of truth for "is a submission in
  /// flight," so a second call while `submitting` is simply ignored.
  Future<void> submit({required String restaurantId}) async {
    final session = state.session;
    if (session == null) {
      state = state.copyWith(
        status: PosOrderSessionStatus.failure,
        clearSession: true,
        error: const PosNoActiveSessionError(),
      );
      return;
    }
    if (_isBusy) return;
    if (session.lines.isEmpty) {
      state = state.copyWith(
        status: PosOrderSessionStatus.failure,
        session: session,
        error: const PosSubmissionRejectedError(
          reason: 'Session has no lines',
        ),
      );
      return;
    }

    state = state.copyWith(
      status: PosOrderSessionStatus.submitting,
      session: session,
      clearError: true,
    );

    final useCase = SubmitPosOrder(
      clock: ref.read(clockProvider),
      identityProvider: ref.read(orderIdentityProvider),
      repository: ref.read(posOrderRepositoryProvider),
      restaurantId: restaurantId,
    );

    try {
      final order = await useCase.call(session);
      // Approved requirement: clear the session on success, but retain
      // submittedOrder — the two never coexist in the resulting state.
      state = PosOrderSessionState(
        status: PosOrderSessionStatus.submitted,
        submittedOrder: order,
      );
    } on BusinessRuleViolation catch (violation) {
      // Preserve the complete editing session so the cashier can fix and
      // retry — never lost on a failed submission.
      state = state.copyWith(
        status: PosOrderSessionStatus.failure,
        session: session,
        error: PosValidationError(violation),
      );
    } catch (error) {
      state = state.copyWith(
        status: PosOrderSessionStatus.failure,
        session: session,
        error: PosRepositoryError(cause: error),
      );
    }
  }

  /// Discards the active session (draft included) and returns to `idle`.
  Future<void> cancelSession() async {
    if (_isBusy) return;
    final session = state.session;
    if (session != null) {
      try {
        await CancelPosOrderSession(
          repository: ref.read(posOrderRepositoryProvider),
        ).call(session.sessionId);
      } catch (_) {
        // Cancelling is a local, user-initiated "give up on this session"
        // action — a failure to also clear the persisted draft must never
        // block the UI from returning to idle; the stale draft is
        // harmless (the same sessionId is never reused).
      }
    }
    state = const PosOrderSessionState();
  }

  Future<void> _applyMutation(PosOrderSession Function() mutate) async {
    try {
      final updated = mutate();
      state = state.copyWith(
        status: PosOrderSessionStatus.editing,
        session: updated,
        clearError: true,
      );
      await _saveDraft(updated);
    } on BusinessRuleViolation catch (violation) {
      state = state.copyWith(
        status: PosOrderSessionStatus.failure,
        error: PosValidationError(violation),
      );
    }
  }

  Future<void> _saveDraft(PosOrderSession session) async {
    try {
      await ref
          .read(posOrderRepositoryProvider)
          .saveDraft(session.sessionId, session);
    } catch (error) {
      state = state.copyWith(
        status: PosOrderSessionStatus.failure,
        session: session,
        error: PosRepositoryError(cause: error),
      );
    }
  }
}

final posOrderSessionProvider =
    NotifierProvider<PosOrderSessionController, PosOrderSessionState>(() {
  return PosOrderSessionController();
});
