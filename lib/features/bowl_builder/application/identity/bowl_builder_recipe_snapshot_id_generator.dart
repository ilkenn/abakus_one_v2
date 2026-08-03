abstract interface class BowlBuilderRecipeSnapshotIdGenerator {
  String nextBowlBuilderRecipeSnapshotId();
}

class SequentialBowlBuilderRecipeSnapshotIdGenerator
    implements BowlBuilderRecipeSnapshotIdGenerator {
  SequentialBowlBuilderRecipeSnapshotIdGenerator({
    this.prefix = 'bowl-builder-snapshot',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextBowlBuilderRecipeSnapshotId() => '$prefix-${++_sequence}';
}
