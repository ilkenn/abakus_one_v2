import 'package:abakus_one_v2/features/pos/data/payment_gateway.dart';
import 'package:abakus_one_v2/features/pos/data/pos_action_gateway.dart';
import 'package:abakus_one_v2/features/pos/data/pos_operational_view_gateway.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/pos_workspace_providers.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/pos_checkout_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for AP-4 Wave F's refund-UI-reachability fix
/// (`docs/decisions.md`'s "Flow #7" entry): once a [PaymentSessionView]
/// reaches `sessionStatus == "completed"`, [PosCheckoutScreen] used to
/// unconditionally render a bare success screen with no way to reach the
/// refund dialog at all — exactly the state `requestPaymentRefund` requires
/// the backing check to already be in. This is a fast, deterministic widget
/// test (no real emulator) — the `flutter drive` E2E flow
/// (`integration_test/pos_partial_refund_e2e_test.dart`) is the real-backend
/// proof; this file exists so a regression is caught in seconds, not only in
/// a multi-minute `flutter drive` run.
class _FakePaymentGateway implements PaymentGateway {
  _FakePaymentGateway(this.session);

  PaymentSessionView session;
  int refundCallCount = 0;
  ({
    String refundType,
    int amountMinorUnits,
    String reasonMessage
  })? lastRefundRequest;

  @override
  Future<PaymentIntentResult> createPaymentIntent({
    required PosDeviceContext ctx,
    required String checkId,
    int coverCount = 0,
  }) async =>
      const PaymentIntentResult(
        intentId: 'intent-1',
        sessionId: 'session-1',
        payableAmountMinorUnits: 4000,
      );

  @override
  Future<PaymentSessionView> getPaymentSessionView({
    required PosDeviceContext ctx,
    required String checkId,
  }) async =>
      session;

  @override
  Future<PaymentAttemptResult> recordPaymentAttempt({
    required PosDeviceContext ctx,
    required String checkId,
    required String sessionId,
    required String tenderType,
    required String idempotencyKey,
    required List<Map<String, dynamic>> allocations,
    int? requestedBoncukAmount,
    String? cashSessionId,
    ({String leaseId, int deviceSequence})? offlineLease,
  }) async =>
      const PaymentAttemptResult(attemptId: 'attempt-1', status: 'succeeded');

  @override
  Future<RefundRequestResult> requestPaymentRefund({
    required PosDeviceContext ctx,
    required String checkId,
    required String refundType,
    required int amountMinorUnits,
    required String reasonCode,
    required String reasonMessage,
    List<String>? orderLineRefs,
  }) async {
    refundCallCount += 1;
    lastRefundRequest = (
      refundType: refundType,
      amountMinorUnits: amountMinorUnits,
      reasonMessage: reasonMessage,
    );
    // Mirror the real screen's own post-action refresh: reflect the new
    // pending refund in the session the next getPaymentSessionView call
    // returns, exactly like the real backend would.
    session = PaymentSessionView(
      exists: session.exists,
      sessionId: session.sessionId,
      sessionStatus: session.sessionStatus,
      payableAmountMinorUnits: session.payableAmountMinorUnits,
      settledAmountMinorUnits: session.settledAmountMinorUnits,
      currencyCode: session.currencyCode,
      subAccountAllocations: session.subAccountAllocations,
      attempts: session.attempts,
      refunds: [
        ...session.refunds,
        RefundRequestSummary(
          refundId: 'refund-1',
          refundType: refundType,
          amountMinorUnits: amountMinorUnits,
          status: 'pendingApproval',
        ),
      ],
    );
    return const RefundRequestResult(
      refundId: 'refund-1',
      status: 'pendingApproval',
      approvalRequestId: 'approval-1',
    );
  }
}

const _ctx = PosDeviceContext(
  organizationId: 'org-1',
  branchId: 'branch-1',
  deviceId: 'device-1',
  deviceSessionId: 'session-1',
);

const _view = PosTableOperationalView(
  tableId: 'table-1',
  status: 'occupied',
  tableSessionId: 'tsess-1',
  subAccounts: [
    {'id': 'sub-1', 'displayName': 'Misafir 1'},
  ],
  checks: [],
  orders: [],
);

PaymentSessionView _completedSessionWithOneAttempt() {
  return const PaymentSessionView(
    exists: true,
    sessionId: 'session-1',
    sessionStatus: 'completed',
    payableAmountMinorUnits: 4000,
    settledAmountMinorUnits: 4000,
    currencyCode: 'TRY',
    attempts: [
      PaymentAttemptSummary(
        attemptId: 'attempt-1',
        tenderType: 'cash',
        status: 'succeeded',
        amountMinorUnits: 4000,
        declineReason: null,
      ),
    ],
    refunds: [],
  );
}

Future<_FakePaymentGateway> _pumpCompletedCheckout(
  WidgetTester tester, {
  PaymentSessionView? session,
}) async {
  final gateway =
      _FakePaymentGateway(session ?? _completedSessionWithOneAttempt());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        paymentGatewayProvider.overrideWithValue(gateway),
      ],
      child: const MaterialApp(
        home: PosCheckoutScreen(
          ctx: _ctx,
          checkId: 'check-1',
          view: _view,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return gateway;
}

void main() {
  group('PosCheckoutScreen — refund reachability after payment completes', () {
    testWidgets(
        'a completed session with a settled attempt shows the completed '
        'banner AND a working "İade Talep Et" refund entry point — the exact '
        'gap AP-4 Wave F found and fixed', (tester) async {
      await _pumpCompletedCheckout(tester);

      expect(find.text('Ödeme Tamamlandı'), findsOneWidget,
          reason: 'the completed banner must still render');
      expect(find.text('Masaya Dön'), findsOneWidget,
          reason: 'the primary exit action must be unaffected by the fix');
      expect(find.text('İade Talep Et'), findsOneWidget,
          reason: 'the refund entry point must be reachable once the '
              'session is completed — this is the regression this test '
              'guards against reintroducing');

      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('İade Talep Et'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNotNull,
          reason: 'the button must be enabled once a payment attempt exists');
    });

    testWidgets(
        'tapping "İade Talep Et" on the completed view opens a working '
        'refund dialog that genuinely calls requestPaymentRefund',
        (tester) async {
      final gateway = await _pumpCompletedCheckout(tester);

      await tester.tap(find.text('İade Talep Et'));
      await tester.pumpAndSettle();
      expect(find.text('İade Talep Et'), findsWidgets,
          reason:
              'the dialog title/button reuse the same label — dialog is open');

      await tester.tap(find.text('Kısmi İade'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Tutar'), '10,00');
      await tester.enterText(
          find.widgetWithText(TextField, 'İade Nedeni'), 'Test nedeni.');
      await tester.pump();
      await tester.tap(find.text('Talebi Gönder'));
      await tester.pumpAndSettle();

      expect(gateway.refundCallCount, 1,
          reason: 'the completed view\'s refund dialog must call the real '
              'gateway method, not a no-op');
      expect(gateway.lastRefundRequest?.refundType, 'partial');
      expect(gateway.lastRefundRequest?.amountMinorUnits, 1000);
      expect(find.text('Onay Bekliyor'), findsOneWidget,
          reason: 'after a successful request, the completed view must '
              'show the new refund in its own refunds list');
    });

    testWidgets(
        'a completed session with NO payment attempts keeps the refund '
        'button disabled (nothing to refund yet)', (tester) async {
      await _pumpCompletedCheckout(
        tester,
        session: const PaymentSessionView(
          exists: true,
          sessionId: 'session-1',
          sessionStatus: 'completed',
          payableAmountMinorUnits: 0,
          settledAmountMinorUnits: 0,
          currencyCode: 'TRY',
          attempts: [],
          refunds: [],
        ),
      );

      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('İade Talep Et'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });
}
