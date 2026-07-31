import '../domain/staff/staff_role_change_event.dart';

/// Append-only storage for [StaffRoleChangeEvent] — no update or delete
/// method exists at all, matching every other audit-shaped repository in
/// this codebase.
abstract interface class StaffRoleChangeEventRepository {
  Future<void> append(StaffRoleChangeEvent event);
  Future<List<StaffRoleChangeEvent>> findByStaffMemberId(String staffMemberId);
}

class InMemoryStaffRoleChangeEventRepository
    implements StaffRoleChangeEventRepository {
  final List<StaffRoleChangeEvent> _events = [];

  @override
  Future<void> append(StaffRoleChangeEvent event) async {
    _events.add(event);
  }

  @override
  Future<List<StaffRoleChangeEvent>> findByStaffMemberId(
      String staffMemberId) async {
    return List.unmodifiable(
      _events.where((e) => e.staffMemberId == staffMemberId),
    );
  }
}
