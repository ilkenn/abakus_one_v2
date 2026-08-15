import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/clock_provider.dart';
import '../../application/identity/table_session_id_generator.dart';
import '../../application/use_cases/open_table_session.dart';
import '../../data/table_session_repository.dart';

/// The [TableSessionRepository] currently in use.
/// [InMemoryTableSessionRepository] today — no backend persistence exists
/// yet. Mirrors `posOrderRepositoryProvider`'s existing shape.
final tableSessionRepositoryProvider = Provider<TableSessionRepository>((ref) {
  return InMemoryTableSessionRepository();
});

final tableSessionIdGeneratorProvider =
    Provider<TableSessionIdGenerator>((ref) {
  return SequentialTableSessionIdGenerator();
});

/// [OpenTableSession] wired against the two providers above — the
/// customer-facing QR scan flow (`qr_scanner_screen.dart`) and any future
/// staff walk-in flow both read this same provider, matching the use
/// case's own "channel-agnostic" doc comment.
final openTableSessionProvider = Provider<OpenTableSession>((ref) {
  return OpenTableSession(
    clock: ref.watch(clockProvider),
    idGenerator: ref.watch(tableSessionIdGeneratorProvider),
    repository: ref.watch(tableSessionRepositoryProvider),
  );
});
