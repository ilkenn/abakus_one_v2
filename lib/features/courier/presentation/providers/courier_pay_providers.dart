import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../data/courier_pay_gateway.dart';
import '../../domain/pay/courier_pay_models.dart';

/// ADR-085 stage 5 — courier pay, shifts and earnings (server-backed).
final courierPayGatewayProvider = Provider<CourierPayGateway>((ref) {
  if (!ref.watch(firebaseReadyProvider)) {
    return const UnavailableCourierPayGateway();
  }
  return FirebaseCourierPayGateway();
});

/// "Now" for the period chips — a provider so tests can pin the day.
final courierPayClockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

/// The courier app's "Kazancım" for a period.
final myCourierPayProvider = FutureProvider.autoDispose
    .family<MyCourierPay, CourierPayPeriod>((ref, period) {
  final range = period.range(ref.watch(courierPayClockProvider)());
  return ref
      .watch(courierPayGatewayProvider)
      .myPay(fromDate: range.fromDate, toDate: range.toDate);
});

typedef CourierEarningsScope = ({
  String organizationId,
  CourierPayPeriod period,
});

/// The panel's earnings per courier for a period.
final courierEarningsReportProvider = FutureProvider.autoDispose
    .family<CourierEarningsReport, CourierEarningsScope>((ref, scope) {
  final range = scope.period.range(ref.watch(courierPayClockProvider)());
  return ref.watch(courierPayGatewayProvider).earnings(
      organizationId: scope.organizationId,
      fromDate: range.fromDate,
      toDate: range.toDate);
});

/// The panel's open shifts (waiting for approval, or running).
final openCourierShiftsProvider = FutureProvider.autoDispose
    .family<List<CourierShift>, String>((ref, organizationId) {
  return ref
      .watch(courierPayGatewayProvider)
      .listOpenShifts(organizationId: organizationId);
});
