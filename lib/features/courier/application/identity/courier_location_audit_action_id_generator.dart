/// Shared id source for Sprint 5B Part 11's audit-only location actions
/// (start/stop tracking, history reset) — none of these produce their own
/// persisted domain entity the way `LocationEmergencyOverride` does, so
/// there is no natural "entity id" to derive the audit correlation id
/// from; this generator is that id source instead.
abstract interface class CourierLocationAuditActionIdGenerator {
  String nextActionId();
}

class SequentialCourierLocationAuditActionIdGenerator
    implements CourierLocationAuditActionIdGenerator {
  SequentialCourierLocationAuditActionIdGenerator({this.prefix = 'locaction'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextActionId() => '$prefix-${++_sequence}';
}
