import '../../../../core/errors/business_rule_violation.dart';
import '../../../../shared/models/money.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/supplier_audit_entry_repository.dart';
import '../../data/supplier_price_repository.dart';
import '../../domain/supplier_audit_entry.dart';
import '../../domain/supplier_audit_event_type.dart';
import '../../domain/supplier_price.dart';
import '../identity/supplier_price_id_generator.dart';

/// Records a new, append-only [SupplierPrice] — admin-only
/// (`PosAuthorizedAction.manageSupplierPricing`, the brief's own
/// "confidentiality" tier for supplier pricing), Phase 7
/// (`docs/decisions.md` ADR-024). Never edits or removes a prior
/// price — "supplier prices never overwrite historical receipts."
class RecordSupplierPrice {
  const RecordSupplierPrice({
    required PosAuthorizationPolicy authorizationPolicy,
    required SupplierPriceIdGenerator idGenerator,
    required SupplierPriceRepository repository,
    required SupplierAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final SupplierPriceIdGenerator _idGenerator;
  final SupplierPriceRepository _repository;
  final SupplierAuditEntryRepository _auditRepository;

  Future<SupplierPrice> call({
    required String organizationId,
    required String supplierProductId,
    required Money pricePerUnit,
    required DateTime effectiveFrom,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageSupplierPricing;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final price = SupplierPrice(
      id: _idGenerator.nextSupplierPriceId(),
      supplierProductId: supplierProductId,
      pricePerUnit: pricePerUnit,
      effectiveFrom: effectiveFrom,
      createdByStaffId: performedByStaffId,
      createdAt: performedAt,
    );
    await _repository.save(price);

    await _auditRepository.appendEvent(SupplierAuditEntry(
      id: '${price.id}-audit-recorded',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: SupplierAuditEventType.supplierPriceRecorded,
      description: 'Supplier price recorded for product '
          '"$supplierProductId"',
      targetEntityId: price.id,
      timestamp: performedAt,
    ));

    return price;
  }
}
