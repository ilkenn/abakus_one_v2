import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/courier_compensation_profile_id_generator.dart';
import '../../application/identity/courier_earnings_adjustment_id_generator.dart';
import '../../application/identity/courier_earnings_payment_id_generator.dart';
import '../../application/identity/courier_shift_schedule_id_generator.dart';
import '../../application/identity/delivery_earnings_id_generator.dart';
import '../../application/identity/shift_hourly_earnings_id_generator.dart';
import '../../data/courier_compensation_profile_repository.dart';
import '../../data/courier_earnings_adjustment_repository.dart';
import '../../data/courier_earnings_payment_repository.dart';
import '../../data/courier_shift_schedule_repository.dart';
import '../../data/delivery_earnings_repository.dart';
import '../../data/shift_hourly_earnings_repository.dart';

/// Sprint 5A — Courier Compensation & Earnings dependencies, split out of
/// `courier_dependencies_provider.dart` (Sprint 5E Part 7,
/// `docs/decisions.md` ADR-022) — self-contained, no cross-sub-domain
/// provider references.
final courierCompensationProfileRepositoryProvider =
    Provider<CourierCompensationProfileRepository>((ref) {
  return InMemoryCourierCompensationProfileRepository();
});

final courierShiftScheduleRepositoryProvider =
    Provider<CourierShiftScheduleRepository>((ref) {
  return InMemoryCourierShiftScheduleRepository();
});

final deliveryEarningsRepositoryProvider =
    Provider<DeliveryEarningsRepository>((ref) {
  return InMemoryDeliveryEarningsRepository();
});

final shiftHourlyEarningsRepositoryProvider =
    Provider<ShiftHourlyEarningsRepository>((ref) {
  return InMemoryShiftHourlyEarningsRepository();
});

final courierEarningsAdjustmentRepositoryProvider =
    Provider<CourierEarningsAdjustmentRepository>((ref) {
  return InMemoryCourierEarningsAdjustmentRepository();
});

final courierEarningsPaymentRepositoryProvider =
    Provider<CourierEarningsPaymentRepository>((ref) {
  return InMemoryCourierEarningsPaymentRepository();
});

final courierCompensationProfileIdGeneratorProvider =
    Provider<CourierCompensationProfileIdGenerator>((ref) {
  return SequentialCourierCompensationProfileIdGenerator();
});

final courierShiftScheduleIdGeneratorProvider =
    Provider<CourierShiftScheduleIdGenerator>((ref) {
  return SequentialCourierShiftScheduleIdGenerator();
});

final deliveryEarningsIdGeneratorProvider =
    Provider<DeliveryEarningsIdGenerator>((ref) {
  return SequentialDeliveryEarningsIdGenerator();
});

final shiftHourlyEarningsIdGeneratorProvider =
    Provider<ShiftHourlyEarningsIdGenerator>((ref) {
  return SequentialShiftHourlyEarningsIdGenerator();
});

final courierEarningsAdjustmentIdGeneratorProvider =
    Provider<CourierEarningsAdjustmentIdGenerator>((ref) {
  return SequentialCourierEarningsAdjustmentIdGenerator();
});

final courierEarningsPaymentIdGeneratorProvider =
    Provider<CourierEarningsPaymentIdGenerator>((ref) {
  return SequentialCourierEarningsPaymentIdGenerator();
});
