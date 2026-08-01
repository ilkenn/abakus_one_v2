abstract interface class LocalizationConfigIdGenerator {
  String nextLocalizationConfigId();
}

class SequentialLocalizationConfigIdGenerator
    implements LocalizationConfigIdGenerator {
  SequentialLocalizationConfigIdGenerator({this.prefix = 'locconfig'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextLocalizationConfigId() => '$prefix-${++_sequence}';
}
