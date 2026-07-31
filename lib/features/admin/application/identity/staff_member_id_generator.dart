abstract interface class StaffMemberIdGenerator {
  String nextStaffMemberId();
}

class SequentialStaffMemberIdGenerator implements StaffMemberIdGenerator {
  SequentialStaffMemberIdGenerator({this.prefix = 'staff-member'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextStaffMemberId() => '$prefix-${++_sequence}';
}
