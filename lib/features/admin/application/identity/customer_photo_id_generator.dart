abstract interface class CustomerPhotoIdGenerator {
  String nextPhotoId();
}

class SequentialCustomerPhotoIdGenerator implements CustomerPhotoIdGenerator {
  SequentialCustomerPhotoIdGenerator({this.prefix = 'customer-photo'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextPhotoId() => '$prefix-${++_sequence}';
}
