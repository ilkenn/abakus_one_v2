import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/table_session_id_generator.dart';
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
