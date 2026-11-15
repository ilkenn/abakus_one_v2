import 'dart:typed_data';

import 'package:abakus_one_v2/features/courier/domain/pay/courier_pay_models.dart';
import 'package:abakus_one_v2/features/courier/presentation/providers/courier_pay_providers.dart';
import 'package:abakus_one_v2/features/courier/presentation/screens/courier_pay_management_screen.dart';
import 'package:abakus_one_v2/features/courier/presentation/widgets/courier_earnings_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'courier_pay_test_support.dart';

/// ADR-085 stage 6A — invoices and payments in "Kazancım" (courier) and in
/// "Kurye Vardiya & Kazanç" → "Faturalar" / "Kazançlar" (panel).
final _now = DateTime.utc(2026, 11, 15, 12);

Future<FakeCourierDocumentService> _pump(
    WidgetTester tester, FakeCourierPayGateway gateway, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(480, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final documents = FakeCourierDocumentService();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      courierPayGatewayProvider.overrideWithValue(gateway),
      courierPayClockProvider.overrideWithValue(() => _now),
      courierDocumentServiceProvider.overrideWithValue(documents),
    ],
    child: MaterialApp(home: child),
  ));
  await tester.pumpAndSettle();
  return documents;
}

const _totals = CourierEarningsTotals(
  packageCount: 3,
  packageMinorUnits: 12000,
  shiftMinutes: 0,
  shiftMinorUnits: 0,
  totalMinorUnits: 12000,
);

void main() {
  group('Kazancım (courier)', () {
    testWidgets(
        'shows paid and the balance; an invoicing courier sees its invoices '
        'and sends one with the PDF', (tester) async {
      final gateway = FakeCourierPayGateway()
        ..myPayResult = MyCourierPay(
          shiftsEnabled: false,
          currentRate: shopRate,
          openShift: null,
          totals: _totals,
          lines: const [],
          issuesInvoice: true,
          paidInPeriodMinorUnits: 4000,
          balance: const CourierBalance(
            earnedTotalMinorUnits: 30000,
            paidTotalMinorUnits: 10000,
            balanceMinorUnits: 20000,
          ),
          invoices: [
            sampleInvoice(id: 'old', status: CourierInvoiceStatus.rejected),
          ],
        )
        ..preview = const CourierInvoicePreview(
          lineCount: 3,
          earnedMinorUnits: 12000,
          carriedLineCount: 1,
          overlapping: false,
        );
      await _pump(tester, gateway, const Scaffold(body: CourierEarningsTab()));

      expect(find.text('Bu dönemde ödenen: 40 TL'), findsOneWidget);
      expect(find.text('Kalan Bakiye: 200 TL'), findsOneWidget);
      expect(find.text('Reddedildi'), findsOneWidget);
      expect(find.textContaining('Gerekçe: Fatura no hatalı'), findsOneWidget);

      await tester.tap(find.byKey(const Key('invoiceUpload')));
      await tester.pumpAndSettle();
      expect(gateway.calls.last, startsWith('preview:'));
      expect(find.text('Hakediş: 120 TL'), findsOneWidget);
      expect(find.textContaining('1 kalem önceki tarihlerden'), findsOneWidget);
      expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('invoiceAmount')))
              .controller
              ?.text,
          '120',
          reason: 'prefilled with the computed earnings');

      await tester.enterText(find.byKey(const Key('invoiceAmount')), '141,60');
      await tester.pumpAndSettle();
      expect(find.textContaining('21,60 TL fazla'), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('invoiceNumber')), 'ABC2026000001');
      await tester.tap(find.byKey(const Key('invoiceSend')));
      await tester.pumpAndSettle();
      expect(find.text('Fatura dosyasını ekleyin.'), findsOneWidget);
      expect(gateway.calls, isNot(contains('submitInvoice')));

      await tester.tap(find.byKey(const Key('invoicePickPdf')));
      await tester.pumpAndSettle();
      expect(find.text('Eklendi: fatura.pdf'), findsOneWidget);
      await tester.tap(find.byKey(const Key('invoiceSend')));
      await tester.pumpAndSettle();
      expect(gateway.lastSubmit?['amount'], 14160);
      expect(gateway.lastSubmit?['number'], 'ABC2026000001');
      expect(gateway.lastSubmit?['contentType'], 'application/pdf');
      expect(find.text('Faturanız gönderildi. Onaylanınca bildirilecek.'),
          findsOneWidget);
      expect(find.byKey(const Key('invoiceSend')), findsNothing,
          reason: 'back on "Kazancım"');
    });

    testWidgets('an already invoiced period cannot be sent again',
        (tester) async {
      final gateway = FakeCourierPayGateway()
        ..myPayResult = emptyMyPay().copyWithInvoicing()
        ..preview = const CourierInvoicePreview(
          lineCount: 0,
          earnedMinorUnits: 0,
          carriedLineCount: 0,
          overlapping: true,
        );
      await _pump(tester, gateway, const Scaffold(body: CourierEarningsTab()));
      await tester.tap(find.byKey(const Key('invoiceUpload')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('invoiceOverlap')), findsOneWidget);
      expect(
          tester
              .widget<ElevatedButton>(find.byKey(const Key('invoiceSend')))
              .onPressed,
          isNull);
    });

    testWidgets('a courier who does not invoice has no "Fatura Yükle"',
        (tester) async {
      await _pump(tester, FakeCourierPayGateway(),
          const Scaffold(body: CourierEarningsTab()));
      expect(find.byKey(const Key('invoiceUpload')), findsNothing);
    });
  });

  group('Faturalar (panel)', () {
    Future<void> openInvoices(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('tabCourierInvoices')));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'a manager sees the difference, opens the file, approves; cannot pay',
        (tester) async {
      final gateway = FakeCourierPayGateway()
        ..invoices = [sampleInvoice()]
        ..file = (
          bytes: Uint8List.fromList([1, 2, 3]),
          contentType: 'application/pdf',
        );
      final documents = await _pump(tester, gateway,
          const CourierPayManagementScreen(organizationId: 'org-1'));
      await openInvoices(tester);
      expect(find.text('Onay Bekliyor'), findsOneWidget);

      await tester.tap(find.byKey(const Key('invoice-inv-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('invoiceReviewDifference')), findsOneWidget);
      expect(find.textContaining('+21,60 TL'), findsOneWidget);
      expect(find.byKey(const Key('invoicePayFull')), findsNothing);

      await tester.tap(find.byKey(const Key('invoiceViewFile')));
      await tester.pumpAndSettle();
      expect(documents.opened, ['fatura-inv-1.pdf']);

      await tester.tap(find.byKey(const Key('invoiceApprove')));
      await tester.pumpAndSettle();
      expect(gateway.calls, contains('approveInvoice:inv-1'));
      expect(find.text('Fatura onaylandı.'), findsOneWidget);
    });

    testWidgets('a rejection needs a reason', (tester) async {
      final gateway = FakeCourierPayGateway()..invoices = [sampleInvoice()];
      await _pump(tester, gateway,
          const CourierPayManagementScreen(organizationId: 'org-1'));
      await openInvoices(tester);
      await tester.tap(find.byKey(const Key('invoice-inv-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('invoiceReject')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reasonConfirm')));
      await tester.pumpAndSettle();
      expect(find.text('Gerekçe yazın'), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('reasonField')), 'Fatura no hatalı');
      await tester.tap(find.byKey(const Key('reasonConfirm')));
      await tester.pumpAndSettle();
      expect(gateway.calls, contains('rejectInvoice:inv-1'));
      expect(gateway.lastReason, 'Fatura no hatalı');
    });

    testWidgets('an admin pays in part, then in full', (tester) async {
      final gateway = FakeCourierPayGateway()
        ..canRecordPayments = true
        ..invoices = [
          sampleInvoice(status: CourierInvoiceStatus.approved, amount: 10000)
        ];
      await _pump(tester, gateway,
          const CourierPayManagementScreen(organizationId: 'org-1'));
      await openInvoices(tester);

      await tester.tap(find.byKey(const Key('invoice-inv-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('invoicePayPartial')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('paymentAmount')), '150');
      await tester.tap(find.byKey(const Key('paymentSave')));
      await tester.pumpAndSettle();
      expect(find.text('Kalan tutardan fazla olamaz'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('paymentAmount')), '40');
      await tester.enterText(find.byKey(const Key('paymentNote')), 'Havale');
      await tester.tap(find.byKey(const Key('paymentSave')));
      await tester.pumpAndSettle();
      expect(gateway.lastPayment?['amount'], 4000);
      expect(gateway.lastPayment?['note'], 'Havale');
      expect(gateway.lastPayment?['full'], isFalse);

      await tester.tap(find.byKey(const Key('invoice-inv-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('invoicePayFull')));
      await tester.pumpAndSettle();
      expect(find.text('Ödenecek: 100 TL'), findsOneWidget);
      await tester.tap(find.byKey(const Key('paymentSave')));
      await tester.pumpAndSettle();
      expect(gateway.lastPayment?['full'], isTrue);
      expect(find.text('Fatura tamamen ödendi.'), findsOneWidget);
    });
  });

  group('Kazançlar (panel)', () {
    testWidgets(
        'shows paid and the balance per courier; an admin enters an advance '
        'and reverses a payment', (tester) async {
      final gateway = FakeCourierPayGateway()
        ..report = const CourierEarningsReport(
          totalMinorUnits: 12000,
          truncated: false,
          paidInPeriodMinorUnits: 5000,
          canRecordPayments: true,
          couriers: [
            CourierEarningsEntry(
              staffUid: 'courier-1',
              courierName: 'Ali Kurye',
              totals: _totals,
              lines: [],
              paidInPeriodMinorUnits: 5000,
              balance: CourierBalance(
                earnedTotalMinorUnits: 30000,
                paidTotalMinorUnits: 5000,
                balanceMinorUnits: 25000,
              ),
              payments: [
                CourierPayment(
                  paymentId: 'p1',
                  kind: CourierPaymentKind.advance,
                  amountMinorUnits: 5000,
                  paidDate: '2026-11-15',
                  invoiceId: null,
                  reversed: false,
                  note: null,
                ),
              ],
            ),
          ],
        );
      await _pump(tester, gateway,
          const CourierPayManagementScreen(organizationId: 'org-1'));
      await tester.tap(find.byKey(const Key('tabCourierEarnings')));
      await tester.pumpAndSettle();
      expect(find.text('Bu dönemde ödenen: 50 TL'), findsOneWidget);
      expect(find.textContaining('Kalan Bakiye 250 TL'), findsOneWidget);

      await tester.tap(find.byKey(const Key('courierEarnings-courier-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('advance-courier-1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('paymentAmount')), '75');
      await tester.tap(find.byKey(const Key('paymentSave')));
      await tester.pumpAndSettle();
      expect(gateway.calls, contains('payment:advance'));
      expect(gateway.lastPayment?['targetUid'], 'courier-1');
      expect(gateway.lastPayment?['amount'], 7500);

      await tester.tap(find.byKey(const Key('reversePayment-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reversePaymentConfirm')));
      await tester.pumpAndSettle();
      expect(gateway.calls, contains('payment:reversal'));
      expect(gateway.lastPayment?['reversesPaymentId'], 'p1');
    });
  });
}

extension on MyCourierPay {
  MyCourierPay copyWithInvoicing() => MyCourierPay(
        shiftsEnabled: shiftsEnabled,
        currentRate: currentRate,
        openShift: openShift,
        totals: totals,
        lines: lines,
        issuesInvoice: true,
      );
}
