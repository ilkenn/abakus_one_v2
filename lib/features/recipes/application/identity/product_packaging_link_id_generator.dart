abstract interface class ProductPackagingLinkIdGenerator {
  String nextProductPackagingLinkId();
}

class SequentialProductPackagingLinkIdGenerator
    implements ProductPackagingLinkIdGenerator {
  SequentialProductPackagingLinkIdGenerator({this.prefix = 'packaging-link'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextProductPackagingLinkId() => '$prefix-${++_sequence}';
}
