import 'package:abakus_one_v2/features/courier/application/identity/courier_fraud_signal_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/detect_repeated_location_loss_signal.dart';
import 'package:abakus_one_v2/features/courier/data/courier_fraud_signal_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_location_availability_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/fraud/courier_fraud_signal_type.dart';
import 'package:abakus_one_v2/features/courier/domain/location/courier_location_availability.dart';
import 'package:abakus_one_v2/features/courier/domain/location/location_unavailable_reason.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';

CourierLocationAvailability _entry({
  required LocationUnavailableReason? reason,
  required DateTime updatedAt,
  required int revision,
}) {
  return CourierLocationAvailability(
    courierId: 'courier-1',
    status: reason == null
        ? CourierLocationAvailabilityStatus.available
        : CourierLocationAvailabilityStatus.unavailable,
    reason: reason,
    updatedAt: updatedAt,
    revision: revision,
  );
}

void main() {
  group('DetectRepeatedLocationLossSignal', () {
    late CourierLocationAvailabilityRepository availabilityRepository;
    late CourierFraudSignalRepository signalRepository;
    late DetectRepeatedLocationLossSignal useCase;

    setUp(() {
      availabilityRepository = InMemoryCourierLocationAvailabilityRepository();
      signalRepository = InMemoryCourierFraudSignalRepository();
      useCase = DetectRepeatedLocationLossSignal(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        availabilityRepository: availabilityRepository,
        idGenerator: SequentialCourierFraudSignalIdGenerator(),
        repository: signalRepository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        minimumOccurrences: 3,
      );
    });

    test('fewer occurrences than the minimum produces no signal', () async {
      await availabilityRepository.save(_entry(
        reason: LocationUnavailableReason.signalLost,
        updatedAt: DateTime(2026, 1, 1, 11, 50),
        revision: 1,
      ));
      await availabilityRepository.save(_entry(
        reason: LocationUnavailableReason.signalLost,
        updatedAt: DateTime(2026, 1, 1, 11, 55),
        revision: 2,
      ));

      final signal = await useCase(
        branchId: 'branch-1',
        courierId: 'courier-1',
        deviceId: 'device-1',
        reason: LocationUnavailableReason.signalLost,
      );

      expect(signal, isNull);
    });

    test(
        'reaching the minimum within the window produces a repeatedGpsLoss '
        'signal', () async {
      for (final minute in [40, 45, 50]) {
        await availabilityRepository.save(_entry(
          reason: LocationUnavailableReason.signalLost,
          updatedAt: DateTime(2026, 1, 1, 11, minute),
          revision: minute,
        ));
      }

      final signal = await useCase(
        branchId: 'branch-1',
        courierId: 'courier-1',
        deviceId: 'device-1',
        reason: LocationUnavailableReason.signalLost,
      );

      expect(signal?.type, CourierFraudSignalType.repeatedGpsLoss);
      expect(await signalRepository.findByCourierId('courier-1'), hasLength(1));
    });

    test('occurrences outside the window are never counted', () async {
      // Well outside the default 1-hour window.
      for (final hour in [1, 2, 3]) {
        await availabilityRepository.save(_entry(
          reason: LocationUnavailableReason.signalLost,
          updatedAt: DateTime(2026, 1, 1, hour),
          revision: hour,
        ));
      }

      final signal = await useCase(
        branchId: 'branch-1',
        courierId: 'courier-1',
        deviceId: 'device-1',
        reason: LocationUnavailableReason.signalLost,
      );

      expect(signal, isNull);
    });

    test(
        'backgroundBlocked reaching the minimum produces '
        'backgroundTrackingDisabled', () async {
      for (final minute in [40, 45, 50]) {
        await availabilityRepository.save(_entry(
          reason: LocationUnavailableReason.backgroundBlocked,
          updatedAt: DateTime(2026, 1, 1, 11, minute),
          revision: minute,
        ));
      }

      final signal = await useCase(
        branchId: 'branch-1',
        courierId: 'courier-1',
        deviceId: 'device-1',
        reason: LocationUnavailableReason.backgroundBlocked,
      );

      expect(signal?.type, CourierFraudSignalType.backgroundTrackingDisabled);
    });

    test('a reason other than signalLost/backgroundBlocked never triggers',
        () async {
      for (final minute in [40, 45, 50]) {
        await availabilityRepository.save(_entry(
          reason: LocationUnavailableReason.permissionDenied,
          updatedAt: DateTime(2026, 1, 1, 11, minute),
          revision: minute,
        ));
      }

      final signal = await useCase(
        branchId: 'branch-1',
        courierId: 'courier-1',
        deviceId: 'device-1',
        reason: LocationUnavailableReason.permissionDenied,
      );

      expect(signal, isNull);
    });
  });
}
