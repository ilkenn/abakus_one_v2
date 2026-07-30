import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/same_destination_group_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/delivery/same_destination_group.dart';
import '../identity/same_destination_group_id_generator.dart';

/// A manager's "assign together" decision for two or more
/// same-destination deliveries — Sprint 5C Part 6. Manager-only
/// ([PosAuthorizedAction.groupSameDestinationDeliveries]). Choosing
/// "assign separately" is simply never calling this — no use case exists
/// for that choice because it requires no state change at all.
///
/// This use case only **records the grouping decision**; it does not
/// itself assign the deliveries (`ManuallyAssignDelivery`/
/// `OfferDeliveryAssignment` remain the only ways a delivery gets
/// assigned) and does not itself waive any package fee — that happens
/// automatically, later, when `CalculateDeliveryEarnings` is given this
/// repository as an optional collaborator and finds a sibling delivery in
/// the same group that already earned the package fee.
class GroupSameDestinationDeliveries {
  const GroupSameDestinationDeliveries({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required SameDestinationGroupIdGenerator idGenerator,
    required SameDestinationGroupRepository repository,
    required CourierOperationalAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final SameDestinationGroupIdGenerator _idGenerator;
  final SameDestinationGroupRepository _repository;
  final CourierOperationalAuditEntryRepository _auditRepository;

  Future<SameDestinationGroup> call({
    required String branchId,
    required String courierId,
    required List<String> deliveryIds,
    required String performedByStaffId,
  }) async {
    if (deliveryIds.length < 2) {
      throw SameDestinationGroupTooSmallViolation(
          deliveryCount: deliveryIds.length);
    }

    const action = PosAuthorizedAction.groupSameDestinationDeliveries;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'courierId': courierId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final now = _clock.now();
    final group = SameDestinationGroup(
      id: _idGenerator.nextGroupId(),
      branchId: branchId,
      courierId: courierId,
      deliveryIds: deliveryIds,
      groupedByStaffId: performedByStaffId,
      groupedAt: now,
    );
    await _repository.append(group);

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${group.id}-audit',
      branchId: branchId,
      actorStaffId: performedByStaffId,
      courierId: courierId,
      type: CourierAuditEventType.sameDestinationGrouped,
      description:
          'Same-destination deliveries grouped: ${deliveryIds.join(', ')}',
      timestamp: now,
      correlationId: group.id,
    ));

    return group;
  }
}
