import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../data/courier_document_service.dart';
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

/// The courier app's "Kazancım" for a period (stage 6A: any range of days,
/// not only today / this week / this month).
final myCourierPayProvider = FutureProvider.autoDispose
    .family<MyCourierPay, CourierPayRange>((ref, range) {
  return ref
      .watch(courierPayGatewayProvider)
      .myPay(fromDate: range.fromDate, toDate: range.toDate);
});

typedef CourierEarningsScope = ({
  String organizationId,
  CourierPayRange range,
});

/// The panel's earnings per courier for a period.
final courierEarningsReportProvider = FutureProvider.autoDispose
    .family<CourierEarningsReport, CourierEarningsScope>((ref, scope) {
  return ref.watch(courierPayGatewayProvider).earnings(
      organizationId: scope.organizationId,
      fromDate: scope.range.fromDate,
      toDate: scope.range.toDate);
});

/// The panel's open shifts (waiting for approval, or running).
final openCourierShiftsProvider = FutureProvider.autoDispose
    .family<List<CourierShift>, String>((ref, organizationId) {
  return ref
      .watch(courierPayGatewayProvider)
      .listOpenShifts(organizationId: organizationId);
});

/// Stage 6A — the panel's courier invoices (newest first).
final courierInvoicesProvider = FutureProvider.autoDispose
    .family<CourierInvoiceList, String>((ref, organizationId) {
  return ref
      .watch(courierPayGatewayProvider)
      .listInvoices(organizationId: organizationId);
});

/// Stage 6A — picking the invoice file and opening a PDF (replaced in tests).
final courierDocumentServiceProvider = Provider<CourierDocumentService>((ref) {
  return const DeviceCourierDocumentService();
});
