import 'package:flutter/foundation.dart';
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
///
/// `kReleaseMode`-gated — closed during this phase's mandatory
/// adversarial security review: no Firestore-backed implementation
/// exists yet, so this was previously `InMemory*` unconditionally,
/// including in release builds — "no release build may silently fall
/// back to InMemory persistence." The direct, honest consequence:
/// account deletion cannot be *requested* at all in a release build
/// until a real Firestore-backed repository exists for this collection
/// (mirrors `CanonicalOrderRepository`'s Sprint 9E migration pattern) —
/// a real, named gap for a future sprint, treated as a stricter, safer
/// failure mode than a working-but-non-durable feature would be.
final accountDeletionRequestRepositoryProvider =
    Provider<AccountDeletionRequestRepository>((ref) {
  if (kReleaseMode) {
    return const ProductionUnavailableAccountDeletionRequestRepository();
  }
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
