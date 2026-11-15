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

  void _maybeFail() {
    final e = error;
    if (e != null) {
      error = null;
      throw e;
    }
  }

  @override
  Future<CourierPayRate?> currentRate({
    required String organizationId,
    required String targetUid,
  }) async {
    calls.add('currentRate:$targetUid');
    return rate;
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
