import '../../../../core/errors/business_rule_violation.dart';
import '../../../menu/application/identity/menu_category_id_generator.dart';
import '../../../menu/application/identity/menu_product_id_generator.dart';
import '../../../menu/data/menu_category_repository.dart';
import '../../../menu/data/menu_product_repository.dart';
import '../../../menu/domain/models/menu_category.dart';
import '../../../menu/domain/models/menu_product.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/import_audit_entry_repository.dart';
import '../../data/import_draft_repository.dart';
import '../../data/import_job_repository.dart';
import '../../domain/import_approval.dart';
import '../../domain/import_audit_entry.dart';
import '../../domain/import_audit_event_type.dart';
import '../../domain/import_commit_result.dart';
import '../../domain/import_review_decision.dart';
import '../../domain/import_status.dart';

/// The **only** point in the whole Smart Import flow that writes to a
/// real domain repository — manager+
/// (`PosAuthorizedAction.manageSmartImport`), Phase 7
/// (`docs/decisions.md` ADR-024). Requires [ImportStatus.approved];
/// throws [ImportNotApprovedViolation] otherwise, structurally
/// preventing "import commit without approval" regardless of what any
/// caller intends. Idempotent by status: an already-
/// [ImportStatus.committed] job throws
/// [InvalidImportStatusTransitionViolation] rather than creating a
/// second copy of every product.
///
/// Only [ParsedCategory]/[ParsedProduct] entities with a matching
/// [ImportReviewOutcome.approved] decision are ever created — anything
/// without one is counted in [ImportCommitResult.skippedCount], never
/// silently created anyway. [ImportReviewDecision.editedName]/
/// [ImportReviewDecision.editedPrice], when present, override the
/// parsed value — "approving *edited* content."
class CommitImportDraft {
  const CommitImportDraft({
    required PosAuthorizationPolicy authorizationPolicy,
    required ImportJobRepository jobRepository,
    required ImportDraftRepository draftRepository,
    required MenuCategoryRepository categoryRepository,
    required MenuProductRepository productRepository,
    required MenuCategoryIdGenerator categoryIdGenerator,
    required MenuProductIdGenerator productIdGenerator,
    required ImportAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _jobRepository = jobRepository,
        _draftRepository = draftRepository,
        _categoryRepository = categoryRepository,
        _productRepository = productRepository,
        _categoryIdGenerator = categoryIdGenerator,
        _productIdGenerator = productIdGenerator,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final ImportJobRepository _jobRepository;
  final ImportDraftRepository _draftRepository;
  final MenuCategoryRepository _categoryRepository;
  final MenuProductRepository _productRepository;
  final MenuCategoryIdGenerator _categoryIdGenerator;
  final MenuProductIdGenerator _productIdGenerator;
  final ImportAuditEntryRepository _auditRepository;

  Future<ImportCommitResult> call({
    required String importJobId,
    required ImportApproval approval,
    required DateTime performedAt,
  }) async {
    final job = await _jobRepository.findById(importJobId);
    if (job == null) {
      throw UnknownImportEntityViolation(
        entityName: 'ImportJob',
        id: importJobId,
      );
    }

    const action = PosAuthorizedAction.manageSmartImport;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: approval.approvedByStaffId,
      context: {kBranchIdAuthorizationContextKey: job.branchId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    if (job.status != ImportStatus.approved) {
      throw ImportNotApprovedViolation(importJobId: importJobId);
    }

    final draft = await _draftRepository.findByImportJobId(importJobId);
    if (draft == null) {
      throw UnknownImportEntityViolation(
        entityName: 'ImportDraft',
        id: importJobId,
      );
    }

    await _jobRepository.save(job.copyWith(
      status: ImportStatus.committing,
      revision: job.revision + 1,
    ));

    final decisionByTempId = {
      for (final decision in approval.decisions) decision.tempId: decision,
    };

    final createdCategoryIds = <String>[];
    final productCategoryTempIdToRealId = <String, String>{};
    var skippedCount = 0;

    for (final category in draft.parsedMenu.categories) {
      final decision = decisionByTempId[category.tempId];
      if (decision == null ||
          decision.outcome != ImportReviewOutcome.approved) {
        skippedCount++;
        continue;
      }
      final realId = _categoryIdGenerator.nextMenuCategoryId();
      await _categoryRepository.save(MenuCategory(
        id: realId,
        name: decision.editedName ?? category.name,
        sortOrder: category.sortOrder ?? 0,
        isActive: true,
      ));
      createdCategoryIds.add(realId);
      productCategoryTempIdToRealId[category.tempId] = realId;
    }

    final createdProductIds = <String>[];
    var errorCount = 0;
    for (final product in draft.parsedMenu.products) {
      final decision = decisionByTempId[product.tempId];
      if (decision == null ||
          decision.outcome != ImportReviewOutcome.approved) {
        skippedCount++;
        continue;
      }
      final realCategoryId =
          productCategoryTempIdToRealId[product.categoryTempId];
      final price = decision.editedPrice ?? product.price;
      if (realCategoryId == null || price == null) {
        // The product's own category wasn't approved, or it still has
        // no valid price — never fabricated, counted as an error.
        errorCount++;
        continue;
      }
      final realId = _productIdGenerator.nextMenuProductId();
      await _productRepository.save(MenuProduct(
        id: realId,
        categoryId: realCategoryId,
        name: decision.editedName ?? product.name,
        description: product.description ?? '',
        basePrice: price,
        imageKey: '',
        isAvailable: product.isAvailable,
      ));
      createdProductIds.add(realId);
    }

    await _jobRepository.save(job.copyWith(
      status: ImportStatus.committed,
      completedAt: performedAt,
      revision: job.revision + 2,
    ));

    await _auditRepository.appendEvent(ImportAuditEntry(
      id: '$importJobId-audit-committed-${performedAt.microsecondsSinceEpoch}',
      branchId: job.branchId,
      actorId: approval.approvedByStaffId,
      type: ImportAuditEventType.importCommitted,
      description: 'Committed: ${createdCategoryIds.length} categories, '
          '${createdProductIds.length} products, $skippedCount skipped, '
          '$errorCount errors',
      targetEntityId: importJobId,
      timestamp: performedAt,
    ));

    return ImportCommitResult(
      importJobId: importJobId,
      createdCategoryIds: createdCategoryIds,
      createdProductIds: createdProductIds,
      skippedCount: skippedCount,
      errorCount: errorCount,
      committedAt: performedAt,
    );
  }
}
