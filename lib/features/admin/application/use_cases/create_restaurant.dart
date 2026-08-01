import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/organization_repository.dart';
import '../../data/restaurant_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/organization/restaurant.dart';
import '../identity/restaurant_id_generator.dart';

/// Creates a [Restaurant] under an existing [Organization] — admin-only
/// (`PosAuthorizedAction.manageRestaurant`).
class CreateRestaurant {
  const CreateRestaurant({
    required PosAuthorizationPolicy authorizationPolicy,
    required RestaurantIdGenerator idGenerator,
    required RestaurantRepository repository,
    required OrganizationRepository organizationRepository,
    required AdminAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _organizationRepository = organizationRepository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final RestaurantIdGenerator _idGenerator;
  final RestaurantRepository _repository;
  final OrganizationRepository _organizationRepository;
  final AdminAuditEntryRepository _auditRepository;

  Future<Restaurant> call({
    required String organizationId,
    required String name,
    String defaultLanguageCode = 'tr',
    List<String> supportedLanguageCodes = const ['tr'],
    required String performedByStaffId,
    required DateTime createdAt,
  }) async {
    const action = PosAuthorizedAction.manageRestaurant;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final organization = await _organizationRepository.findById(
      organizationId,
    );
    if (organization == null) {
      throw UnknownAdminEntityViolation(
        entityName: 'Organization',
        id: organizationId,
      );
    }

    final restaurant = Restaurant(
      id: _idGenerator.nextRestaurantId(),
      organizationId: organizationId,
      name: name,
      defaultLanguageCode: defaultLanguageCode,
      supportedLanguageCodes: supportedLanguageCodes,
      createdAt: createdAt,
      revision: 1,
    );
    await _repository.save(restaurant);

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '${restaurant.id}-audit-created',
      actorId: performedByStaffId,
      type: AdminAuditEventType.restaurantCreated,
      description: 'Restaurant created: "$name"',
      targetEntityId: restaurant.id,
      timestamp: createdAt,
    ));

    return restaurant;
  }
}
