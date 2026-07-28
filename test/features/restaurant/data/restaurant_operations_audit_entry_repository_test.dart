import 'package:abakus_one_v2/features/restaurant/data/restaurant_operations_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/restaurant/domain/audit/restaurant_operations_audit_entry.dart';
import 'package:abakus_one_v2/features/restaurant/domain/audit/restaurant_operations_audit_event_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('appendEvent then findByBranchId returns every event, oldest first',
      () async {
    final repository = InMemoryRestaurantOperationsAuditEntryRepository();
    final first = RestaurantOperationsAuditEntry(
      id: 'e1',
      branchId: 'branch-1',
      type: RestaurantOperationsAuditEventType.channelOperationalStateChanged,
      description: 'first',
      actorStaffId: 'staff-1',
      timestamp: DateTime(2026, 7, 29, 10),
    );
    final second = RestaurantOperationsAuditEntry(
      id: 'e2',
      branchId: 'branch-1',
      type: RestaurantOperationsAuditEventType.emergencyChannelClosure,
      description: 'second',
      actorStaffId: 'staff-1',
      timestamp: DateTime(2026, 7, 29, 11),
    );

    await repository.appendEvent(first);
    await repository.appendEvent(second);

    final events = await repository.findByBranchId('branch-1');
    expect(events.map((e) => e.id), ['e1', 'e2']);
  });

  test('events for a different branch are not returned', () async {
    final repository = InMemoryRestaurantOperationsAuditEntryRepository();
    await repository.appendEvent(RestaurantOperationsAuditEntry(
      id: 'e1',
      branchId: 'branch-a',
      type: RestaurantOperationsAuditEventType.channelOperationalStateChanged,
      description: 'x',
      actorStaffId: 'staff-1',
      timestamp: DateTime(2026, 7, 29),
    ));

    final events = await repository.findByBranchId('branch-b');
    expect(events, isEmpty);
  });
}
