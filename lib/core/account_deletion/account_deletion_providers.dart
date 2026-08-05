import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/account_deletion_request_id_generator.dart';
import 'application/cancel_account_deletion_request.dart';
import 'application/request_account_deletion.dart';
import 'data/account_deletion_request_repository.dart';

/// Central Riverpod wiring for `core/account_deletion` — Sprint 9G
/// (`docs/decisions.md` ADR-026). Mirrors every feature's own
/// `..._dependencies_provider.dart` shape, placed under `core/` instead
/// of a feature since this repository must be reachable from both
/// `features/auth` and `features/profile` (see
/// `AccountDeletionRequestRepository`'s own doc comment).
final accountDeletionRequestRepositoryProvider =
    Provider<AccountDeletionRequestRepository>((ref) {
  return InMemoryAccountDeletionRequestRepository();
});

final accountDeletionRequestIdGeneratorProvider =
    Provider<AccountDeletionRequestIdGenerator>((ref) {
  return SequentialAccountDeletionRequestIdGenerator();
});

final requestAccountDeletionProvider = Provider<RequestAccountDeletion>((ref) {
  return RequestAccountDeletion(
    repository: ref.watch(accountDeletionRequestRepositoryProvider),
    idGenerator: ref.watch(accountDeletionRequestIdGeneratorProvider),
  );
});

final cancelAccountDeletionRequestProvider =
    Provider<CancelAccountDeletionRequest>((ref) {
  return CancelAccountDeletionRequest(
    repository: ref.watch(accountDeletionRequestRepositoryProvider),
  );
});
