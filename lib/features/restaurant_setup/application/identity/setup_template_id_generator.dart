abstract interface class SetupTemplateIdGenerator {
  String nextSetupTemplateId();
}

class SequentialSetupTemplateIdGenerator implements SetupTemplateIdGenerator {
  SequentialSetupTemplateIdGenerator({this.prefix = 'setup-template'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextSetupTemplateId() => '$prefix-${++_sequence}';
}
