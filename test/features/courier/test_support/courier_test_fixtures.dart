import 'package:abakus_one_v2/features/courier/application/use_cases/record_courier_event.dart';
import 'package:abakus_one_v2/features/courier/application/identity/courier_event_id_generator.dart';
import 'package:abakus_one_v2/features/courier/data/courier_event_repository.dart';
import 'package:abakus_one_v2/features/courier/data/in_memory_courier_event_bus.dart';
import 'package:abakus_one_v2/features/courier/domain/availability/courier_availability.dart';
import 'package:abakus_one_v2/features/courier/domain/availability/courier_availability_status.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_status.dart';
import 'package:abakus_one_v2/features/courier/domain/identity/courier.dart';
import 'package:abakus_one_v2/features/courier/domain/identity/courier_vehicle_type.dart';
import 'package:abakus_one_v2/features/courier/domain/shift/courier_shift.dart';
import 'package:abakus_one_v2/features/courier/domain/shift/courier_shift_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';

/// A minimal, valid [Courier] for use-case tests that need one without
/// exercising `RegisterCourier` itself.
Courier buildTestCourier({
  String id = 'courier-1',
  String primaryBranchId = 'branch-1',
  List<String> eligibleBranchIds = const [],
  String displayName = 'Test Kurye',
  int capacity = 3,
  CourierVehicleType vehicleType = CourierVehicleType.motorcycle,
}) {
  return Courier(
    id: id,
    primaryBranchId: primaryBranchId,
    eligibleBranchIds: eligibleBranchIds,
    displayName: displayName,
    phoneNumber: '+905551112233',
    vehicleType: vehicleType,
    capacity: capacity,
    registeredAt: DateTime(2026, 1, 1),
  );
}

/// A minimal, active [CourierShift].
CourierShift buildTestActiveShift({
  String id = 'shift-1',
  String courierId = 'courier-1',
  String branchId = 'branch-1',
  CourierShiftStatus status = CourierShiftStatus.active,
  int revision = 1,
}) {
  return CourierShift(
    id: id,
    courierId: courierId,
    branchId: branchId,
    status: status,
    requestedAt: DateTime(2026, 1, 1, 8),
    approvedByStaffId: 'manager-1',
    approvedAt: DateTime(2026, 1, 1, 8, 5),
    startedAt: DateTime(2026, 1, 1, 9),
    revision: revision,
  );
}

/// A minimal [CourierAvailability].
CourierAvailability buildTestAvailability({
  String courierId = 'courier-1',
  String shiftId = 'shift-1',
  CourierAvailabilityStatus status = CourierAvailabilityStatus.available,
  int activeAssignmentCount = 0,
  int capacity = 3,
  int revision = 1,
}) {
  return CourierAvailability(
    courierId: courierId,
    shiftId: shiftId,
    status: status,
    activeAssignmentCount: activeAssignmentCount,
    capacity: capacity,
    updatedAt: DateTime(2026, 1, 1, 9),
    revision: revision,
  );
}

/// A [Delivery] at [status] (default: [DeliveryStatus.readyForAssignment]).
Delivery buildTestDelivery({
  String id = 'delivery-1',
  String orderId = 'order-1',
  String branchId = 'branch-1',
  DeliveryStatus status = DeliveryStatus.readyForAssignment,
  String? courierId,
  String? currentAssignmentId,
  int revision = 1,
}) {
  return Delivery(
    id: id,
    orderId: OrderId(orderId),
    branchId: branchId,
    status: status,
    courierId: courierId,
    currentAssignmentId: currentAssignmentId,
    createdAt: DateTime(2026, 1, 1, 12),
    revision: revision,
  );
}

/// A [RecordCourierEvent] wired to fresh in-memory infrastructure.
RecordCourierEvent buildTestRecordCourierEvent({
  CourierEventRepository? eventRepository,
}) {
  return RecordCourierEvent(
    idGenerator: SequentialCourierEventIdGenerator(),
    eventRepository: eventRepository ?? InMemoryCourierEventRepository(),
    eventPublisher: InMemoryCourierEventBus(),
  );
}
