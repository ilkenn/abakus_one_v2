abstract interface class IntegrationCredentialRefIdGenerator {
  String nextIntegrationCredentialRefId();
}

class SequentialIntegrationCredentialRefIdGenerator
    implements IntegrationCredentialRefIdGenerator {
  SequentialIntegrationCredentialRefIdGenerator({this.prefix = 'credential'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextIntegrationCredentialRefId() => '$prefix-${++_sequence}';
}
