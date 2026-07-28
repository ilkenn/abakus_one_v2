import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/models/exchange_rate_snapshot.dart';
import '../../../../shared/models/money.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../../payment/domain/models/payment_method.dart';
import '../../../payment/presentation/services/payment_service.dart';
import '../../application/errors/payment_application_error.dart';
import '../../application/use_cases/add_payment_split.dart';
import '../../application/use_cases/cancel_payment_session.dart';
import '../../application/use_cases/complete_payment_session.dart';
import '../../application/use_cases/remove_payment_split.dart';
import '../../application/use_cases/start_payment_session.dart';
import '../../domain/authorization/approval_result.dart';
import '../../domain/models/payment_session.dart';
import 'payment_session_dependencies_provider.dart';
import 'payment_split_id_generator_provider.dart';

/// Owns the active [PaymentSession] end to end — mirrors
/// `PosOrderSessionController`'s shape exactly (Phase 3 Sprint 3B
/// convention, carried into Sprint 3C).
///
/// [session] is `null` while idle (no payment collection started yet).
/// [isCompleting] is a controller-only transient flag: `CompletePaymentSession`
/// never persists a `completing` status onto the domain object itself (a
/// failed attempt leaves [PaymentSession.status] exactly as it was) — this
/// flag is what lets the UI show a "completing" state during the async
/// provider round trip without inventing a matching domain status value
/// nothing ever actually stores.
class PaymentSessionState {
  const PaymentSessionState({
    this.session,
    this.isCompleting = false,
    this.error,
  });

  final PaymentSession? session;
  final bool isCompleting;
  final PaymentApplicationError? error;

  bool get isIdle => session == null;

  PaymentSessionState copyWith({
    PaymentSession? session,
    bool clearSession = false,
    bool? isCompleting,
    PaymentApplicationError? error,
    bool clearError = false,
  }) {
    return PaymentSessionState(
      session: clearSession ? null : (session ?? this.session),
      isCompleting: isCompleting ?? this.isCompleting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class PaymentSessionController extends Notifier<PaymentSessionState> {
  @override
  PaymentSessionState build() => const PaymentSessionState();

  void startSession({
    required String sessionId,
    required OrderId orderId,
    required Money totalAmount,
  }) {
    if (state.isCompleting) return;
    final session = StartPaymentSession(clock: ref.read(clockProvider)).call(
      sessionId: sessionId,
      orderId: orderId,
      totalAmount: totalAmount,
    );
    state = PaymentSessionState(session: session);
    _persist(session);
  }

  Future<void> addSplit({
    required PaymentMethod method,
    required Money amount,
    String? transactionReference,
    String? authorizationCode,
    String? terminalId,
  }) async {
    final session = state.session;
    if (session == null || state.isCompleting) return;
    await _applyMutation(
      () => AddPaymentSplit(
        splitIdGenerator: ref.read(paymentSplitIdGeneratorProvider),
      )(
        session: session,
        method: method,
        amount: amount,
        transactionReference: transactionReference,
        authorizationCode: authorizationCode,
        terminalId: terminalId,
      ),
    );
  }

  Future<void> addForeignCurrencySplit({
    required PaymentMethod method,
    required Money amount,
    required ExchangeRateSnapshot exchangeRate,
  }) async {
    final session = state.session;
    if (session == null || state.isCompleting) return;
    await _applyMutation(
      () => AddPaymentSplit(
        splitIdGenerator: ref.read(paymentSplitIdGeneratorProvider),
      ).callForeignCurrency(
        session: session,
        method: method,
        amount: amount,
        exchangeRate: exchangeRate,
      ),
    );
  }

  Future<void> removeSplit(String splitId) async {
    final session = state.session;
    if (session == null || state.isCompleting) return;
    await _applyMutation(
      () => const RemovePaymentSplit()(session: session, splitId: splitId),
    );
  }

  /// Completes the session. Duplicate-completion prevention lives here,
  /// not inside `CompletePaymentSession` — [state].isCompleting is already
  /// the single source of truth for "is a completion attempt in flight,"
  /// mirroring `PosOrderSessionController.submit`'s exact precedent.
  Future<void> complete({Map<String, ApprovalResult> approvals = const {}}) async {
    final session = state.session;
    if (session == null) {
      state = state.copyWith(error: const PaymentNoActiveSessionError(), clearError: false);
      return;
    }
    if (state.isCompleting) return;

    state = state.copyWith(isCompleting: true, clearError: true);

    final useCase = CompletePaymentSession(paymentService: PaymentService());
    try {
      final completed = await useCase(
        session: session,
        expectedRevision: session.revision,
        approvals: approvals,
      );
      state = PaymentSessionState(session: completed);
      await _persist(completed);
    } on BusinessRuleViolation catch (violation) {
      state = state.copyWith(
        isCompleting: false,
        session: session,
        error: PaymentValidationError(violation),
      );
    } catch (error) {
      state = state.copyWith(
        isCompleting: false,
        session: session,
        error: PaymentRepositoryError(cause: error),
      );
    }
  }

  Future<void> cancel() async {
    final session = state.session;
    if (session == null || state.isCompleting) return;
    await _applyMutation(
      () => const CancelPaymentSession()(
        session: session,
        expectedRevision: session.revision,
      ),
    );
  }

  Future<void> _applyMutation(PaymentSession Function() mutate) async {
    try {
      final updated = mutate();
      state = state.copyWith(session: updated, clearError: true);
      await _persist(updated);
    } on BusinessRuleViolation catch (violation) {
      state = state.copyWith(error: PaymentValidationError(violation));
    }
  }

  Future<void> _persist(PaymentSession session) async {
    try {
      await ref.read(paymentSessionRepositoryProvider).save(session);
    } catch (error) {
      state = state.copyWith(
        session: session,
        error: PaymentRepositoryError(cause: error),
      );
    }
  }
}

final paymentSessionProvider =
    NotifierProvider<PaymentSessionController, PaymentSessionState>(() {
  return PaymentSessionController();
});
