import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/check_id_generator.dart';
import '../../data/check_repository.dart';

/// The [CheckRepository] currently in use. [InMemoryCheckRepository]
/// today — no backend persistence exists yet. Mirrors
/// `paymentSessionRepositoryProvider`'s existing shape.
final checkRepositoryProvider = Provider<CheckRepository>((ref) {
  return InMemoryCheckRepository();
});

final checkIdGeneratorProvider = Provider<CheckIdGenerator>((ref) {
  return SequentialCheckIdGenerator();
});
