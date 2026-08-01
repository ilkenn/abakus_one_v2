abstract interface class OrganizationIdGenerator {
  String nextOrganizationId();
}

class SequentialOrganizationIdGenerator implements OrganizationIdGenerator {
  SequentialOrganizationIdGenerator({this.prefix = 'org'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextOrganizationId() => '$prefix-${++_sequence}';
}
