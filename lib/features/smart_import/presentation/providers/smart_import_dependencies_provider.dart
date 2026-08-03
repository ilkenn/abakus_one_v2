import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../pos/presentation/providers/actor_session_provider.dart';
import '../../../menu/application/identity/menu_category_id_generator.dart';
import '../../../menu/application/identity/menu_product_id_generator.dart';
import '../../../menu/data/menu_category_repository.dart';
import '../../../menu/data/menu_product_repository.dart';
import '../../application/identity/import_draft_id_generator.dart';
import '../../application/identity/import_job_id_generator.dart';
import '../../application/use_cases/approve_import_draft.dart';
import '../../application/use_cases/commit_import_draft.dart';
import '../../application/use_cases/create_import_draft.dart';
import '../../application/use_cases/create_import_job.dart';
import '../../application/use_cases/normalize_and_analyze_parsed_menu.dart';
import '../../application/use_cases/parse_import_source.dart';
import '../../application/use_cases/rollback_import_commit.dart';
import '../../data/import_audit_entry_repository.dart';
import '../../data/import_draft_repository.dart';
import '../../data/import_job_repository.dart';

/// Central Riverpod wiring for `features/smart_import` — Phase 7
/// (`docs/decisions.md` ADR-024), mirrors `admin_dependencies_provider
/// .dart`'s shape. `menuCategoryRepositoryProvider`/
/// `menuProductRepositoryProvider` are shared, singleton providers —
/// `CommitImportDraft`'s writes must land in the same store every other
/// Menu-reading provider resolves against.
final importJobRepositoryProvider = Provider<ImportJobRepository>((ref) {
  return InMemoryImportJobRepository();
});

final importJobIdGeneratorProvider = Provider<ImportJobIdGenerator>((ref) {
  return SequentialImportJobIdGenerator();
});

final importDraftRepositoryProvider = Provider<ImportDraftRepository>((ref) {
  return InMemoryImportDraftRepository();
});

final importDraftIdGeneratorProvider = Provider<ImportDraftIdGenerator>((ref) {
  return SequentialImportDraftIdGenerator();
});

final importAuditEntryRepositoryProvider =
    Provider<ImportAuditEntryRepository>((ref) {
  return InMemoryImportAuditEntryRepository();
});

final menuCategoryRepositoryProvider = Provider<MenuCategoryRepository>((ref) {
  return InMemoryMenuCategoryRepository();
});

final menuCategoryIdGeneratorProvider =
    Provider<MenuCategoryIdGenerator>((ref) {
  return SequentialMenuCategoryIdGenerator();
});

final menuProductRepositoryProvider = Provider<MenuProductRepository>((ref) {
  return InMemoryMenuProductRepository();
});

final menuProductIdGeneratorProvider = Provider<MenuProductIdGenerator>((ref) {
  return SequentialMenuProductIdGenerator();
});

final normalizeAndAnalyzeParsedMenuProvider =
    Provider<NormalizeAndAnalyzeParsedMenu>((ref) {
  return const NormalizeAndAnalyzeParsedMenu();
});

final parseImportSourceProvider = Provider<ParseImportSource>((ref) {
  return ParseImportSource(
    jobRepository: ref.watch(importJobRepositoryProvider),
    auditRepository: ref.watch(importAuditEntryRepositoryProvider),
  );
});

final createImportDraftProvider = Provider<CreateImportDraft>((ref) {
  return CreateImportDraft(
    jobRepository: ref.watch(importJobRepositoryProvider),
    draftRepository: ref.watch(importDraftRepositoryProvider),
    idGenerator: ref.watch(importDraftIdGeneratorProvider),
    auditRepository: ref.watch(importAuditEntryRepositoryProvider),
  );
});

final createImportJobProvider = Provider<CreateImportJob>((ref) {
  return CreateImportJob(
    authorizationPolicy: ref.watch(posAuthorizationPolicyProvider),
    idGenerator: ref.watch(importJobIdGeneratorProvider),
    repository: ref.watch(importJobRepositoryProvider),
    auditRepository: ref.watch(importAuditEntryRepositoryProvider),
  );
});

final approveImportDraftProvider = Provider<ApproveImportDraft>((ref) {
  return ApproveImportDraft(
    authorizationPolicy: ref.watch(posAuthorizationPolicyProvider),
    jobRepository: ref.watch(importJobRepositoryProvider),
    auditRepository: ref.watch(importAuditEntryRepositoryProvider),
  );
});

final commitImportDraftProvider = Provider<CommitImportDraft>((ref) {
  return CommitImportDraft(
    jobRepository: ref.watch(importJobRepositoryProvider),
    draftRepository: ref.watch(importDraftRepositoryProvider),
    categoryRepository: ref.watch(menuCategoryRepositoryProvider),
    productRepository: ref.watch(menuProductRepositoryProvider),
    categoryIdGenerator: ref.watch(menuCategoryIdGeneratorProvider),
    productIdGenerator: ref.watch(menuProductIdGeneratorProvider),
    auditRepository: ref.watch(importAuditEntryRepositoryProvider),
  );
});

final rollbackImportCommitProvider = Provider<RollbackImportCommit>((ref) {
  return RollbackImportCommit(
    authorizationPolicy: ref.watch(posAuthorizationPolicyProvider),
    jobRepository: ref.watch(importJobRepositoryProvider),
    categoryRepository: ref.watch(menuCategoryRepositoryProvider),
    productRepository: ref.watch(menuProductRepositoryProvider),
    auditRepository: ref.watch(importAuditEntryRepositoryProvider),
  );
});
