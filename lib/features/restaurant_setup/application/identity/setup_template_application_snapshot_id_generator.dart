abstract interface class SetupTemplateApplicationSnapshotIdGenerator {
  String nextSnapshotId();
}

class SequentialSetupTemplateApplicationSnapshotIdGenerator
    implements SetupTemplateApplicationSnapshotIdGenerator {
  SequentialSetupTemplateApplicationSnapshotIdGenerator({
    this.prefix = 'setup-template-snapshot',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextSnapshotId() => '$prefix-${++_sequence}';
}
