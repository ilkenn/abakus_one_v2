import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/supplier_audit_entry_repository.dart';
import '../../data/supplier_repository.dart';
import '../../domain/supplier.dart';
import '../../domain/supplier_audit_entry.dart';
import '../../domain/supplier_audit_event_type.dart';
import '../identity/supplier_id_generator.dart';

/// Creates a [Supplier] — manager+
/// (`PosAuthorizedAction.manageSuppliers`), Phase 7
/// (`docs/decisions.md` ADR-024).
class CreateSupplier {
  const CreateSupplier({
    required PosAuthorizationPolicy authorizationPolicy,
    required SupplierIdGenerator idGenerator,
    required SupplierRepository repository,
    required SupplierAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final SupplierIdGenerator _idGenerator;
  final SupplierRepository _repository;
  final SupplierAuditEntryRepository _auditRepository;

  Future<Supplier> call({
    required String organizationId,
    required String name,
    String? contactPhone,
    String? contactEmail,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageSuppliers;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final supplier = Supplier(
      id: _idGenerator.nextSupplierId(),
      organizationId: organizationId,
      name: name,
      contactPhone: contactPhone,
      contactEmail: contactEmail,
      createdAt: performedAt,
      revision: 1,
    );
    await _repository.save(supplier);

    await _auditRepository.appendEvent(SupplierAuditEntry(
      id: '${supplier.id}-audit-created',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: SupplierAuditEventType.supplierCreated,
      description: 'Supplier "$name" created',
      targetEntityId: supplier.id,
      timestamp: performedAt,
    ));

    return supplier;
  }
}
