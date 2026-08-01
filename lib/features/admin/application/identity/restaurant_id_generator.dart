abstract interface class RestaurantIdGenerator {
  String nextRestaurantId();
}

class SequentialRestaurantIdGenerator implements RestaurantIdGenerator {
  SequentialRestaurantIdGenerator({this.prefix = 'restaurant'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextRestaurantId() => '$prefix-${++_sequence}';
}
