import 'dart:typed_data';

import 'package:abakus_one_v2/features/courier/data/courier_document_service.dart';
import 'package:abakus_one_v2/features/courier/data/courier_pay_gateway.dart';
import 'package:abakus_one_v2/features/courier/domain/pay/courier_pay_models.dart';

/// ADR-085 stage 5 — an in-memory [CourierPayGateway] for widget tests.
/// Records every call; [error] makes the next command fail.
class FakeCourierPayGateway implements CourierPayGateway {
  final calls = <String>[];
  CourierPayException? error;
  CourierPayRate? rate;
  MyCourierPay myPayResult = emptyMyPay();
  List<CourierShift> openShifts = const [];
  CourierEarningsReport report = const CourierEarningsReport(
      totalMinorUnits: 0, truncated: false, couriers: []);
  DateTime? lastApprovedAt;
  String? lastReason;
  CourierPayRateInput? lastInput;

  // Stage 6A.
  bool issuesInvoice = false;
  bool? lastInvoicing;
  CourierInvoicePreview preview = const CourierInvoicePreview(
      lineCount: 0,
      earnedMinorUnits: 0,
      carriedLineCount: 0,
      overlapping: false);
  List<CourierInvoice> invoices = const [];
  bool canRecordPayments = false;
  ({Uint8List bytes, String contentType})? file;
  Map<String, Object?>? lastSubmit;
  Map<String, Object?>? lastPayment;

  void _maybeFail() {
    final e = error;
    if (e != null) {
      error = null;
      throw e;
    }
  }

  @override
  Future<CourierPayProfileSummary> payProfile({
    required String organizationId,
    required String targetUid,
  }) async {
    calls.add('currentRate:$targetUid');
    return CourierPayProfileSummary(
        currentRate: rate, issuesInvoice: issuesInvoice);
  }

  @override
  Future<void> setInvoicing({
    required String organizationId,
    required String targetUid,
    required bool issuesInvoice,
  }) async {
    calls.add('setInvoicing:$targetUid:$issuesInvoice');
    _maybeFail();
    lastInvoicing = issuesInvoice;
  }

  @override
  Future<CourierInvoicePreview> previewInvoice({
    required String periodFrom,
    required String periodTo,
  }) async {
    calls.add('preview:$periodFrom..$periodTo');
    return preview;
  }

  @override
  Future<CourierInvoice> submitInvoice({
    required String periodFrom,
    required String periodTo,
    required int invoiceAmountMinorUnits,
    required String invoiceNumber,
    required String note,
    required Uint8List bytes,
    required String contentType,
  }) async {
    calls.add('submitInvoice');
    _maybeFail();
    lastSubmit = {
      'periodFrom': periodFrom,
      'periodTo': periodTo,
      'amount': invoiceAmountMinorUnits,
      'number': invoiceNumber,
      'note': note,
      'contentType': contentType,
      'size': bytes.length,
    };
    return sampleInvoice();
  }

  @override
  Future<CourierInvoiceList> listInvoices({
    required String organizationId,
  }) async =>
      CourierInvoiceList(
          invoices: invoices, canRecordPayments: canRecordPayments);

  @override
  Future<void> reviewInvoice({
    required String organizationId,
    required String invoiceId,
    required bool approve,
    String? reason,
  }) async {
    calls.add('${approve ? 'approveInvoice' : 'rejectInvoice'}:$invoiceId');
    _maybeFail();
    lastReason = reason;
  }

  @override
  Future<void> recordPayment({
    required String organizationId,
    required CourierPaymentKind kind,
    String? invoiceId,
    String? targetUid,
    String? reversesPaymentId,
    int? amountMinorUnits,
    bool full = false,
    String? paidDate,
    String? note,
  }) async {
    calls.add('payment:${kind.name}');
    _maybeFail();
    lastPayment = {
      'invoiceId': invoiceId,
      'targetUid': targetUid,
      'reversesPaymentId': reversesPaymentId,
      'amount': amountMinorUnits,
      'full': full,
      'paidDate': paidDate,
      'note': note,
    };
  }

  @override
  Future<({Uint8List bytes, String contentType})> invoiceFile({
    required String invoiceId,
  }) async {
    calls.add('file:$invoiceId');
    return file!;
  }

  @override
  Future<void> setRate({
    required String organizationId,
    required String targetUid,
    required CourierPayRateInput input,
  }) async {
    calls.add('setRate:$targetUid');
    _maybeFail();
    lastInput = input;
  }

  @override
  Future<List<CourierShift>> listOpenShifts({
    required String organizationId,
  }) async =>
      openShifts;

  @override
  Future<void> reviewShift({
    required String organizationId,
    required String shiftId,
    required bool approve,
    DateTime? approvedAt,
    String? reason,
  }) async {
    calls.add('${approve ? 'approve' : 'reject'}:$shiftId');
    _maybeFail();
    lastApprovedAt = approvedAt;
    lastReason = reason;
    openShifts = openShifts.where((s) => s.shiftId != shiftId).toList();
  }

  @override
  Future<void> closeShift({
    required String organizationId,
    required String shiftId,
    required DateTime endedAt,
    required String reason,
  }) async {
    calls.add('close:$shiftId');
    _maybeFail();
    lastApprovedAt = endedAt;
    lastReason = reason;
    openShifts = openShifts.where((s) => s.shiftId != shiftId).toList();
  }

  @override
  Future<CourierEarningsReport> earnings({
    required String organizationId,
    required String fromDate,
    required String toDate,
  }) async {
    calls.add('earnings:$fromDate..$toDate');
    return report;
  }

  @override
  Future<MyCourierPay> myPay({
    required String fromDate,
    required String toDate,
  }) async {
    calls.add('myPay:$fromDate..$toDate');
    return myPayResult;
  }

  @override
  Future<void> startShift() async {
    calls.add('startShift');
    _maybeFail();
  }

  @override
  Future<void> endShift() async {
    calls.add('endShift');
    _maybeFail();
  }
}

const zeroTotals = CourierEarningsTotals(
  packageCount: 0,
  packageMinorUnits: 0,
  shiftMinutes: 0,
  shiftMinorUnits: 0,
  totalMinorUnits: 0,
);

MyCourierPay emptyMyPay({
  bool shiftsEnabled = true,
  CourierPayRate? rate,
  CourierShift? openShift,
  CourierEarningsTotals totals = zeroTotals,
  List<CourierEarningLine> lines = const [],
}) =>
    MyCourierPay(
      shiftsEnabled: shiftsEnabled,
      currentRate: rate,
      openShift: openShift,
      totals: totals,
      lines: lines,
    );

const shopRate = CourierPayRate(
  versionId: 'v1',
  kind: CourierPayKind.shop,
  perPackageMinorUnits: 4000,
  hourlyMinorUnits: 15000,
  effectiveFromDate: '2026-11-15',
);

CourierInvoice sampleInvoice({
  String id = 'inv-1',
  CourierInvoiceStatus status = CourierInvoiceStatus.submitted,
  int earned = 12000,
  int amount = 14160,
  int paid = 0,
  String contentType = 'application/pdf',
}) =>
    CourierInvoice(
      invoiceId: id,
      staffUid: 'courier-1',
      courierName: 'Ali Kurye',
      periodFrom: '2026-11-01',
      periodTo: '2026-11-14',
      lineCount: 3,
      earnedMinorUnits: earned,
      invoiceAmountMinorUnits: amount,
      invoiceNumber: 'ABC2026000001',
      note: null,
      contentType: contentType,
      status: status,
      rejectReason:
          status == CourierInvoiceStatus.rejected ? 'Fatura no hatalı' : null,
      paidMinorUnits: paid,
      remainingMinorUnits: amount - paid,
    );

/// Stage 6A — picks a fixed file and records opened PDFs.
class FakeCourierDocumentService implements CourierDocumentService {
  CourierPickedDocument? next = (
    bytes: Uint8List.fromList(List.filled(1024, 1)),
    contentType: 'application/pdf',
    name: 'fatura.pdf',
  );
  final opened = <String>[];

  @override
  Future<CourierPickedDocument?> pickPdf() async => next;

  @override
  Future<CourierPickedDocument?> pickPhoto({required bool fromCamera}) async =>
      next == null
          ? null
          : (bytes: next!.bytes, contentType: 'image/jpeg', name: 'foto.jpg');

  @override
  Future<bool> openPdf(Uint8List bytes, {required String name}) async {
    opened.add(name);
    return true;
  }
}
