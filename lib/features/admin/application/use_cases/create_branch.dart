import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/branch_repository.dart';
import '../../data/restaurant_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/organization/branch.dart';
import '../identity/branch_id_generator.dart';

/// Creates a [Branch] under an existing [Restaurant] — admin-only
/// (`PosAuthorizedAction.manageBranch`). "Every admin query must be
/// scoped" starts here: a [Branch] is always created as a child of one,
/// already-existing [Restaurant] — there is no orphaned-branch path.
class CreateBranch {
  const CreateBranch({
    required PosAuthorizationPolicy authorizationPolicy,
    required BranchIdGenerator idGenerator,
    required BranchRepository repository,
    required RestaurantRepository restaurantRepository,
    required AdminAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _restaurantRepository = restaurantRepository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final BranchIdGenerator _idGenerator;
  final BranchRepository _repository;
  final RestaurantRepository _restaurantRepository;
  final AdminAuditEntryRepository _auditRepository;

  Future<Branch> call({
    required String restaurantId,
    required String name,
    String timezone = 'Europe/Istanbul',
    String currencyCode = 'TRY',
    String localeCode = 'tr',
    required String performedByStaffId,
    required DateTime createdAt,
  }) async {
    const action = PosAuthorizedAction.manageBranch;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final restaurant = await _restaurantRepository.findById(restaurantId);
    if (restaurant == null) {
      throw UnknownAdminEntityViolation(
        entityName: 'Restaurant',
        id: restaurantId,
      );
    }

    final branch = Branch(
      id: _idGenerator.nextBranchId(),
      restaurantId: restaurantId,
      name: name,
      timezone: timezone,
      currencyCode: currencyCode,
      localeCode: localeCode,
      createdAt: createdAt,
      revision: 1,
    );
    await _repository.save(branch);

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '${branch.id}-audit-created',
      branchId: branch.id,
      actorId: performedByStaffId,
      type: AdminAuditEventType.branchCreated,
      description: 'Branch created: "$name"',
      targetEntityId: branch.id,
      timestamp: createdAt,
    ));

    return branch;
  }
}
