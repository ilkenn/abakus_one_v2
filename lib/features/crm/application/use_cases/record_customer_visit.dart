import '../../../../core/errors/business_rule_violation.dart';
import '../../data/crm_audit_entry_repository.dart';
import '../../data/customer_repository.dart';
import '../../data/customer_visit_repository.dart';
import '../../domain/audit/crm_audit_entry.dart';
import '../../domain/audit/crm_audit_event_type.dart';
import '../../domain/visits/customer_visit.dart';
import '../identity/customer_visit_id_generator.dart';

/// Records one [CustomerVisit] — "visit counter" foundation of the Visit
/// Passport. A pure recording action: it never computes progress, never
/// grants a reward itself (see `GrantVisitReward`, Sprint 5D Part 3's
/// rewards engine, and `BuildCustomerVisitPassport`, which derives
/// progress/rewards fresh from this history).
///
/// **Sprint 5E**: audited via [CrmAuditEntry]. [performedByStaffId] is
/// `'system'` at this use case's one production call site
/// (`RecordCustomerVisitAndEvaluateRewards`, itself triggered by an
/// automated delivery-completion hook, not a human pressing a button) —
/// a documented sentinel, not a hardcoded impersonation of a real staff
/// member (`docs/decisions.md` ADR-022).
class RecordCustomerVisit {
  const RecordCustomerVisit({
    required CustomerVisitIdGenerator idGenerator,
    required CustomerRepository customerRepository,
    required CustomerVisitRepository visitRepository,
    required CrmAuditEntryRepository auditRepository,
  })  : _idGenerator = idGenerator,
        _customerRepository = customerRepository,
        _visitRepository = visitRepository,
        _auditRepository = auditRepository;

  final CustomerVisitIdGenerator _idGenerator;
  final CustomerRepository _customerRepository;
  final CustomerVisitRepository _visitRepository;
  final CrmAuditEntryRepository _auditRepository;

  Future<CustomerVisit> call({
    required String customerId,
    required String branchId,
    String? orderId,
    required DateTime occurredAt,
    required String performedByStaffId,
  }) async {
    final customer = await _customerRepository.findById(customerId);
    if (customer == null) {
      throw UnknownCrmEntityViolation(entityName: 'Customer', id: customerId);
    }

    final visit = CustomerVisit(
      id: _idGenerator.nextVisitId(),
      customerId: customerId,
      branchId: branchId,
      orderId: orderId,
      occurredAt: occurredAt,
    );
    await _visitRepository.append(visit);

    await _auditRepository.appendEvent(CrmAuditEntry(
      id: '${visit.id}-audit',
      branchId: branchId,
      actorId: performedByStaffId,
      actorRole: performedByStaffId == 'system' ? 'system' : null,
      type: CrmAuditEventType.visitRecorded,
      description: 'Visit recorded for customer $customerId',
      targetEntityId: visit.id,
      timestamp: occurredAt,
    ));

    return visit;
  }
}
