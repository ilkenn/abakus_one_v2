/// Mirrors every other `Sequential*IdGenerator` in this codebase (e.g.
/// `CustomerAdminNoteIdGenerator`) — externally supplied identity, no
/// UUID/random-value shortcut.
abstract interface class AccountDeletionRequestIdGenerator {
  String nextRequestId();
}

class SequentialAccountDeletionRequestIdGenerator
    implements AccountDeletionRequestIdGenerator {
  SequentialAccountDeletionRequestIdGenerator(
      {this.prefix = 'deletion-request'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextRequestId() => '$prefix-${++_sequence}';
}
