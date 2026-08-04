abstract interface class PlatformMemberIdGenerator {
  String nextPlatformMemberId();
}

class SequentialPlatformMemberIdGenerator implements PlatformMemberIdGenerator {
  SequentialPlatformMemberIdGenerator({this.prefix = 'platform-member'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextPlatformMemberId() => '$prefix-${++_sequence}';
}
