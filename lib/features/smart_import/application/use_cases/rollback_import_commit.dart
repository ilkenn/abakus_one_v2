import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/import_audit_entry_repository.dart';
import '../../data/import_job_repository.dart';
import '../../domain/import_audit_entry.dart';
import '../../domain/import_audit_event_type.dart';
import '../../domain/import_commit_result.dart';
import '../../domain/import_status.dart';
import '../../../menu/data/menu_category_repository.dart';
import '../../../menu/data/menu_product_repository.dart';

/// Reverses a [ImportStatus.committed] import — manager+
/// (`PosAuthorizedAction.manageSmartImport`). **Deactivates, never
/// deletes**: every category/product this commit created is set
/// `isActive`/`isAvailable: false` through the same repositories
/// `CommitImportDraft` wrote to — mirrors this codebase's established
/// "reversible via status, not history deletion" pattern
/// (`BranchStatus`/`StaffMemberStatus`/`AdminDeviceRegistrationStatus`).
/// A deactivated product still exists and can be manually reactivated
/// by a Menu admin later; this is not a true delete.
class RollbackImportCommit {
  const RollbackImportCommit({
    required PosAuthorizationPolicy authorizationPolicy,
    required ImportJobRepository jobRepository,
    required MenuCategoryRepository categoryRepository,
    required MenuProductRepository productRepository,
    required ImportAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _jobRepository = jobRepository,
        _categoryRepository = categoryRepository,
        _productRepository = productRepository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final ImportJobRepository _jobRepository;
  final MenuCategoryRepository _categoryRepository;
  final MenuProductRepository _productRepository;
  final ImportAuditEntryRepository _auditRepository;

  Future<void> call({
    required String importJobId,
    required ImportCommitResult commitResult,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    final job = await _jobRepository.findById(importJobId);
    if (job == null) {
      throw UnknownImportEntityViolation(
        entityName: 'ImportJob',
        id: importJobId,
      );
    }
    if (job.status != ImportStatus.committed) {
      throw InvalidImportStatusTransitionViolation(
        fromStatusName: job.status.name,
        toStatusName: ImportStatus.rolledBack.name,
      );
    }

    const action = PosAuthorizedAction.manageSmartImport;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {kBranchIdAuthorizationContextKey: job.branchId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    for (final productId in commitResult.createdProductIds) {
      final product = await _productRepository.findById(productId);
      if (product != null) {
        await _productRepository.save(product.copyWith(isAvailable: false));
      }
    }
    for (final categoryId in commitResult.createdCategoryIds) {
      final category = await _categoryRepository.findById(categoryId);
      if (category != null) {
        await _categoryRepository.save(category.copyWith(isActive: false));
      }
    }

    await _jobRepository.save(job.copyWith(
      status: ImportStatus.rolledBack,
      revision: job.revision + 1,
    ));

    await _auditRepository.appendEvent(ImportAuditEntry(
      id: '$importJobId-audit-rollback-${performedAt.microsecondsSinceEpoch}',
      branchId: job.branchId,
      actorId: performedByStaffId,
      type: ImportAuditEventType.importCommitted,
      description: 'Rolled back: ${commitResult.createdCategoryIds.length} '
          'categories and ${commitResult.createdProductIds.length} '
          'products deactivated',
      targetEntityId: importJobId,
      timestamp: performedAt,
    ));
  }
}
