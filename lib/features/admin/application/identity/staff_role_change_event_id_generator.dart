abstract interface class StaffRoleChangeEventIdGenerator {
  String nextEventId();
}

class SequentialStaffRoleChangeEventIdGenerator
    implements StaffRoleChangeEventIdGenerator {
  SequentialStaffRoleChangeEventIdGenerator({this.prefix = 'role-change'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextEventId() => '$prefix-${++_sequence}';
}
