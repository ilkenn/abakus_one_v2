import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/organization_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/organization/organization.dart';
import '../identity/organization_id_generator.dart';

/// Creates the top of Phase 6D's minimum tenant boundary — admin-only
/// (`PosAuthorizedAction.manageOrganization`).
class CreateOrganization {
  const CreateOrganization({
    required PosAuthorizationPolicy authorizationPolicy,
    required OrganizationIdGenerator idGenerator,
    required OrganizationRepository repository,
    required AdminAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final OrganizationIdGenerator _idGenerator;
  final OrganizationRepository _repository;
  final AdminAuditEntryRepository _auditRepository;

  Future<Organization> call({
    required String name,
    required String performedByStaffId,
    required DateTime createdAt,
  }) async {
    const action = PosAuthorizedAction.manageOrganization;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final organization = Organization(
      id: _idGenerator.nextOrganizationId(),
      name: name,
      createdAt: createdAt,
      revision: 1,
    );
    await _repository.save(organization);

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '${organization.id}-audit-created',
      actorId: performedByStaffId,
      type: AdminAuditEventType.organizationCreated,
      description: 'Organization created: "$name"',
      targetEntityId: organization.id,
      timestamp: createdAt,
    ));

    return organization;
  }
}
