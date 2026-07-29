abstract interface class CourierIdGenerator {
  String nextCourierId();
}

class SequentialCourierIdGenerator implements CourierIdGenerator {
  SequentialCourierIdGenerator({this.prefix = 'courier'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextCourierId() => '$prefix-${++_sequence}';
}
