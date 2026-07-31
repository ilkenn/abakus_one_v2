import '../../../../core/errors/business_rule_violation.dart';
import '../../data/crm_audit_entry_repository.dart';
import '../../data/customer_repository.dart';
import '../../domain/audit/crm_audit_entry.dart';
import '../../domain/audit/crm_audit_event_type.dart';
import '../../domain/segmentation/customer.dart';
import '../../domain/segmentation/customer_category.dart';

/// Sets or clears a customer's [CustomerCategory] — always the customer's
/// own choice, never an administrator action, so this use case carries no
/// authorization gate (mirrors `SetCourierAvailability`'s self-service
/// shape). [customCategoryLabel] is only kept when [category] is
/// [CustomerCategory.other]; it is silently cleared for every other
/// category so a stale free-text note can never survive a category
/// switch away from "other."
///
/// **Sprint 5E**: audited via [CrmAuditEntry] — the actor is the customer
/// themselves ([customerId], `actorRole: 'customer'`), reflecting that
/// this is genuinely self-service, not an admin/staff mutation
/// (`docs/decisions.md` ADR-022).
class SetCustomerCategory {
  const SetCustomerCategory({
    required CustomerRepository repository,
    required CrmAuditEntryRepository auditRepository,
  })  : _repository = repository,
        _auditRepository = auditRepository;

  final CustomerRepository _repository;
  final CrmAuditEntryRepository _auditRepository;

  Future<Customer> call({
    required String customerId,
    CustomerCategory? category,
    String? customCategoryLabel,
    required DateTime performedAt,
  }) async {
    final existing = await _repository.findById(customerId);
    if (existing == null) {
      throw UnknownCrmEntityViolation(entityName: 'Customer', id: customerId);
    }

    final keepsLabel = category == CustomerCategory.other;
    final updated = existing.copyWith(
      category: category,
      clearCategory: category == null,
      customCategoryLabel: keepsLabel ? customCategoryLabel : null,
      clearCustomCategoryLabel: !keepsLabel,
      revision: existing.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(CrmAuditEntry(
      id: '$customerId-audit-${performedAt.microsecondsSinceEpoch}',
      actorId: customerId,
      actorRole: 'customer',
      type: CrmAuditEventType.customerCategoryChanged,
      description: 'Customer category changed to '
          '${category?.name ?? 'none'}',
      targetEntityId: customerId,
      previousStateName: existing.category?.name,
      newStateName: category?.name,
      timestamp: performedAt,
    ));

    return updated;
  }
}
