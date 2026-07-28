import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../orders/data/package_preparation_repository.dart';

/// The [PackagePreparationRepository] currently in use.
/// [InMemoryPackagePreparationRepository] today — no backend persistence
/// exists yet. Mirrors `kitchenTicketRepositoryProvider`'s existing shape.
final packagePreparationRepositoryProvider =
    Provider<PackagePreparationRepository>((ref) {
  return InMemoryPackagePreparationRepository();
});
