import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/qr/domain/i18n/guest_locale.dart';
import 'package:abakus_one_v2/features/qr/domain/i18n/qr_flow_strings.dart';

void main() {
  test('QrFlowStrings.of(tr) returns the Turkish set', () {
    final strings = QrFlowStrings.of(GuestLocale.tr);
    expect(strings.welcomeTitle, "Abaküs Street Food'a Hoş Geldiniz");
    expect(strings.badgeExpiredMessage,
        'Oturum süresi doldu — QR kodu tekrar okutun');
    expect(strings.tableLabel('Masa 12'), 'Masa: Masa 12');
  });

  test('QrFlowStrings.of(en) returns the English set', () {
    final strings = QrFlowStrings.of(GuestLocale.en);
    expect(strings.welcomeTitle, 'Welcome to Abaküs Street Food');
    expect(strings.badgeExpiredMessage,
        'Session expired — please scan the QR code again');
    expect(strings.tableLabel('Table 12'), 'Table: Table 12');
  });

  test(
      'every status/exception message differs between tr and en — no '
      'field was left copy-pasted from the other locale', () {
    final tr = QrFlowStrings.of(GuestLocale.tr);
    final en = QrFlowStrings.of(GuestLocale.en);

    expect(tr.welcomeTitle, isNot(en.welcomeTitle));
    expect(tr.checkingQr, isNot(en.checkingQr));
    expect(tr.openingTable, isNot(en.openingTable));
    expect(tr.statusNotFound, isNot(en.statusNotFound));
    expect(tr.statusInvalid, isNot(en.statusInvalid));
    expect(tr.statusExpired, isNot(en.statusExpired));
    expect(tr.statusReserved, isNot(en.statusReserved));
    expect(tr.statusUnknown, isNot(en.statusUnknown));
    expect(tr.connectionUnavailable, isNot(en.connectionUnavailable));
    expect(tr.exceptionNotFound, isNot(en.exceptionNotFound));
    expect(
        tr.exceptionFailedPrecondition, isNot(en.exceptionFailedPrecondition));
    expect(tr.exceptionResourceExhausted, isNot(en.exceptionResourceExhausted));
    expect(tr.exceptionUnknown, isNot(en.exceptionUnknown));
    expect(tr.sessionOpenError, isNot(en.sessionOpenError));
    expect(tr.retryLabel, isNot(en.retryLabel));
    expect(tr.badgeExpiredMessage, isNot(en.badgeExpiredMessage));
    expect(tr.waiterTooltip, isNot(en.waiterTooltip));
    expect(tr.billTooltip, isNot(en.billTooltip));
    expect(tr.serviceRequestSent, isNot(en.serviceRequestSent));
    expect(
        tr.serviceRequestFailedGeneric, isNot(en.serviceRequestFailedGeneric));
    // Self-Order QR Faz 5.
    expect(tr.requestHelpTooltip, isNot(en.requestHelpTooltip));
    expect(tr.requestSheetTitle, isNot(en.requestSheetTitle));
    expect(tr.requestTeaOption, isNot(en.requestTeaOption));
    expect(tr.requestBillOption, isNot(en.requestBillOption));
    expect(tr.requestAshtrayOrServiceOption,
        isNot(en.requestAshtrayOrServiceOption));
    expect(tr.requestClearTableOption, isNot(en.requestClearTableOption));
    expect(tr.requestCustomNoteOption, isNot(en.requestCustomNoteOption));
    expect(tr.customNoteInputHint, isNot(en.customNoteInputHint));
    expect(tr.customNoteSendLabel, isNot(en.customNoteSendLabel));
    expect(tr.dismissLabel, isNot(en.dismissLabel));
  });
}
