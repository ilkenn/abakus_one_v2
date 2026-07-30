import 'package:abakus_one_v2/features/courier/application/identity/delivery_earnings_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/calculate_delivery_earnings.dart';
import 'package:abakus_one_v2/features/courier/data/courier_compensation_profile_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_earnings_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_tracking_repository.dart';
import 'package:abakus_one_v2/features/courier/data/same_destination_group_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/compensation/courier_compensation_profile.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_status.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/same_destination_group.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../../pos/test_support/fake_pos_authorization_policy.dart';
import '../test_support/courier_test_fixtures.dart';

CourierCompensationProfile _testProfile() {
  return CourierCompensationProfile(
    id: 'profile-1',
    courierId: 'courier-1',
    version: 1,
    effectiveFrom: DateTime(2026, 1, 1),
    hourlyRate: Money.fromWhole(50, Currency.tryLira),
    deliveryFeePerPackage: Money.fromWhole(20, Currency.tryLira),
    freeDistanceKm: 3,
    extraDistanceRatePerKm: Money.fromWhole(5, Currency.tryLira),
    createdByStaffId: 'manager-1',
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('CalculateDeliveryEarnings — Sprint 5C same-destination waiver', () {
    late DeliveryRepository deliveryRepository;
    late DeliveryEarningsRepository earningsRepository;
    late SameDestinationGroupRepository groupRepository;
    late CalculateDeliveryEarnings useCase;

    setUp(() async {
      deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
        id: 'delivery-1',
        status: DeliveryStatus.delivered,
        courierId: 'courier-1',
      ));
      await deliveryRepository.save(buildTestDelivery(
        id: 'delivery-2',
        status: DeliveryStatus.delivered,
        courierId: 'courier-1',
      ));

      final profileRepository = InMemoryCourierCompensationProfileRepository();
      await profileRepository.append(_testProfile());

      earningsRepository = InMemoryDeliveryEarningsRepository();
      groupRepository = InMemorySameDestinationGroupRepository();

      useCase = CalculateDeliveryEarnings(
        clock: FakeClock(DateTime(2026, 2, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialDeliveryEarningsIdGenerator(),
        deliveryRepository: deliveryRepository,
        trackingRepository: InMemoryDeliveryTrackingRepository(),
        compensationProfileRepository: profileRepository,
        earningsRepository: earningsRepository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        sameDestinationGroupRepository: groupRepository,
      );
    });

    test(
        'the first delivery in a group to complete earns the full '
        'package fee', () async {
      await groupRepository.append(SameDestinationGroup(
        id: 'group-1',
        branchId: 'branch-1',
        courierId: 'courier-1',
        deliveryIds: const ['delivery-1', 'delivery-2'],
        groupedByStaffId: 'manager-1',
        groupedAt: DateTime(2026, 1, 1, 12),
      ));

      final earnings = await useCase(
        deliveryId: 'delivery-1',
        performedByStaffId: 'courier-1',
      );

      expect(earnings.wasPackageFeeWaivedForSameDestinationGroup, isFalse);
      expect(earnings.packageFee, Money.fromWhole(20, Currency.tryLira));
    });

    test(
        'the second delivery in the same group has its package fee '
        'waived once the first already earned it', () async {
      await groupRepository.append(SameDestinationGroup(
        id: 'group-1',
        branchId: 'branch-1',
        courierId: 'courier-1',
        deliveryIds: const ['delivery-1', 'delivery-2'],
        groupedByStaffId: 'manager-1',
        groupedAt: DateTime(2026, 1, 1, 12),
      ));

      await useCase(deliveryId: 'delivery-1', performedByStaffId: 'courier-1');
      final second = await useCase(
        deliveryId: 'delivery-2',
        performedByStaffId: 'courier-1',
      );

      expect(second.wasPackageFeeWaivedForSameDestinationGroup, isTrue);
      expect(second.packageFee, Money.zero(Currency.tryLira));
      expect(second.totalEarnings, second.extraDistanceEarnings);
    });

    test('a delivery not in any group is never waived', () async {
      final earnings = await useCase(
        deliveryId: 'delivery-1',
        performedByStaffId: 'courier-1',
      );
      expect(earnings.wasPackageFeeWaivedForSameDestinationGroup, isFalse);
      expect(earnings.packageFee, Money.fromWhole(20, Currency.tryLira));
    });

    test(
        'omitting sameDestinationGroupRepository never waives anything, '
        'even for grouped deliveries', () async {
      await groupRepository.append(SameDestinationGroup(
        id: 'group-1',
        branchId: 'branch-1',
        courierId: 'courier-1',
        deliveryIds: const ['delivery-1', 'delivery-2'],
        groupedByStaffId: 'manager-1',
        groupedAt: DateTime(2026, 1, 1, 12),
      ));

      final profileRepositoryForSecondCase =
          InMemoryCourierCompensationProfileRepository();
      await profileRepositoryForSecondCase.append(_testProfile());
      final useCaseWithoutGroups = CalculateDeliveryEarnings(
        clock: FakeClock(DateTime(2026, 2, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialDeliveryEarningsIdGenerator(),
        deliveryRepository: deliveryRepository,
        trackingRepository: InMemoryDeliveryTrackingRepository(),
        compensationProfileRepository: profileRepositoryForSecondCase,
        earningsRepository: InMemoryDeliveryEarningsRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );

      await useCaseWithoutGroups(
          deliveryId: 'delivery-1', performedByStaffId: 'courier-1');
      final second = await useCaseWithoutGroups(
          deliveryId: 'delivery-2', performedByStaffId: 'courier-1');

      expect(second.wasPackageFeeWaivedForSameDestinationGroup, isFalse);
      expect(second.packageFee, Money.fromWhole(20, Currency.tryLira));
    });
  });
}
