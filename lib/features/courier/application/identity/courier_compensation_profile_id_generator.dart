abstract interface class CourierCompensationProfileIdGenerator {
  String nextProfileId();
}

class SequentialCourierCompensationProfileIdGenerator
    implements CourierCompensationProfileIdGenerator {
  SequentialCourierCompensationProfileIdGenerator(
      {this.prefix = 'ccompprofile'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextProfileId() => '$prefix-${++_sequence}';
}
