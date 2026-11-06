import 'dart:async';

import 'package:abakus_one_v2/features/pos/data/pax_gmp3_terminal_client.dart';
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
  int recordPaymentAttemptCallCount = 0;
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
  }) async {
    recordPaymentAttemptCallCount += 1;
    return const PaymentAttemptResult(
        attemptId: 'attempt-1', status: 'succeeded');
  }

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

class _NeverResolvingPaxClient implements PaxGmp3TerminalClient {
  _NeverResolvingPaxClient(this._completer);

  final Completer<PaxTerminalResult> _completer;

  @override
  Future<PaxTerminalResult> collectPayment({
    required int amountMinorUnits,
    required String currencyCode,
    required String idempotencyKey,
  }) =>
      _completer.future;
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
      // 2026-11-06 compact-modal redesign — `PosCheckoutScreen` now
      // returns a bare `Dialog`, exactly like `PosProductCustomization
      // Dialog`'s own existing pattern, and like that widget it is only
      // ever actually shown via `showDialog` in production
      // (`pos_table_workspace_screen.dart`'s `onOpenCheckout`) — a
      // `Dialog` relies on its surrounding `ModalRoute`/`Overlay` for
      // correct sizing/positioning, so pumping it as plain body content
      // (as this test did before that redesign) no longer represents
      // real usage.
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const PosCheckoutScreen(
                  ctx: _ctx,
                  checkId: 'check-1',
                  view: _view,
                ),
              ),
              child: const Text('Ödemeyi Aç'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Ödemeyi Aç'));
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

  group('PosCheckoutScreen — PAX A910SF "Kredi Kartı" collection (2026-11-06)',
      () {
    PaymentSessionView openSession() {
      return const PaymentSessionView(
        exists: true,
        sessionId: 'session-1',
        sessionStatus: 'collecting',
        payableAmountMinorUnits: 4000,
        settledAmountMinorUnits: 0,
        currencyCode: 'TRY',
        subAccountAllocations: [
          PaymentSubAccountAllocation(
            subAccountId: 'sub-1',
            payableAmountMinorUnits: 4000,
          ),
        ],
        attempts: [],
        refunds: [],
      );
    }

    testWidgets(
        '"PAX Cihazı ile Oku" butonu sadece Kredi Kartı tenderi secildiginde gorunur',
        (tester) async {
      await _pumpCompletedCheckout(tester, session: openSession());

      expect(find.byKey(const Key('collectViaPaxButton')), findsNothing,
          reason: 'varsayilan tender nakit, PAX butonu henuz gorunmemeli');

      await tester.tap(find.text('Kredi/Banka Kartı (Sandbox)'));
      await tester.pump();

      expect(find.byKey(const Key('collectViaPaxButton')), findsOneWidget);
    });

    testWidgets(
        'PAX butonuna basinca "POS Cihazından Kart Bekleniyor..." modali acilir, '
        'gercek cihaz baglantisi olmadigindan dogru/yapilandirilmadi mesaji gosterir, '
        've gateway.recordPaymentAttempt hic cagrilmaz', (tester) async {
      final gateway =
          await _pumpCompletedCheckout(tester, session: openSession());

      await tester.tap(find.text('Kredi/Banka Kartı (Sandbox)'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Tutar'), '40,00');
      // The button sits below the fold of the compact modal's own
      // scrollable tender panel — scroll it into view before tapping,
      // exactly like a real finger would need to.
      await tester.ensureVisible(find.byKey(const Key('collectViaPaxButton')));
      await tester.tap(find.byKey(const Key('collectViaPaxButton')));
      await tester.pump();

      expect(find.text('POS Cihazından Kart Bekleniyor...'), findsOneWidget);
      expect(find.textContaining('Tutar:'), findsOneWidget);

      // The stubbed client resolves near-instantly with "unavailable" —
      // no need to wait out the 30s countdown.
      await tester.pumpAndSettle();

      expect(find.text('POS Cihazından Kart Bekleniyor...'), findsNothing,
          reason: 'modal must have closed once the client resolved');
      expect(
        find.textContaining('PAX A910SF / GMP-3 entegrasyonu'),
        findsOneWidget,
        reason: 'the honest "not configured" message must be shown, never '
            'a fabricated approval/decline',
      );
      expect(gateway.recordPaymentAttemptCallCount, 0,
          reason: 'an unavailable terminal result must never be recorded '
              'server-side as if it were a real tender');
    });

    testWidgets('modal "İptal" ile kapatilinca hicbir mesaj gosterilmez',
        (tester) async {
      // A never-resolving client — the real terminal takes real seconds;
      // this proves "İptal" closes the dialog on its own, never racing
      // against the (otherwise near-instant) stub's own resolution.
      final neverResolves = Completer<PaxTerminalResult>();
      final gateway = _FakePaymentGateway(openSession());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paymentGatewayProvider.overrideWithValue(gateway),
            paxGmp3TerminalClientProvider
                .overrideWithValue(_NeverResolvingPaxClient(neverResolves)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const PosCheckoutScreen(
                      ctx: _ctx,
                      checkId: 'check-1',
                      view: _view,
                    ),
                  ),
                  child: const Text('Ödemeyi Aç'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ödemeyi Aç'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kredi/Banka Kartı (Sandbox)'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Tutar'), '40,00');
      // The button sits below the fold of the compact modal's own
      // scrollable tender panel — scroll it into view before tapping,
      // exactly like a real finger would need to.
      await tester.ensureVisible(find.byKey(const Key('collectViaPaxButton')));
      await tester.tap(find.byKey(const Key('collectViaPaxButton')));
      await tester.pump();
      expect(find.text('POS Cihazından Kart Bekleniyor...'), findsOneWidget);

      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();

      expect(find.text('POS Cihazından Kart Bekleniyor...'), findsNothing);
      expect(find.textContaining('PAX A910SF'), findsNothing);
    });
  });
}
