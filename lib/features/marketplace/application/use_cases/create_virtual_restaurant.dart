import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/marketplace_account_repository.dart';
import '../../data/marketplace_audit_entry_repository.dart';
import '../../data/marketplace_store_repository.dart';
import '../../data/virtual_restaurant_repository.dart';
import '../../domain/audit/marketplace_audit_entry.dart';
import '../../domain/audit/marketplace_audit_event_type.dart';
import '../../domain/virtual_restaurant.dart';
import '../identity/virtual_restaurant_id_generator.dart';

/// Creates a [VirtualRestaurant] under an existing [MarketplaceStore] —
/// Phase 8 (`docs/decisions.md` ADR-025), "Marketplace Store → Virtual
/// Restaurant." tenantOwner-only, organization-scoped (resolved by
/// walking store → account, since neither a store nor a virtual
/// restaurant carries its own `organizationId`).
class CreateVirtualRestaurant {
  const CreateVirtualRestaurant({
    required PosAuthorizationPolicy authorizationPolicy,
    required MarketplaceStoreRepository storeRepository,
    required MarketplaceAccountRepository accountRepository,
    required VirtualRestaurantIdGenerator idGenerator,
    required VirtualRestaurantRepository repository,
    required MarketplaceAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _storeRepository = storeRepository,
        _accountRepository = accountRepository,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final MarketplaceStoreRepository _storeRepository;
  final MarketplaceAccountRepository _accountRepository;
  final VirtualRestaurantIdGenerator _idGenerator;
  final VirtualRestaurantRepository _repository;
  final MarketplaceAuditEntryRepository _auditRepository;

  Future<VirtualRestaurant> call({
    required String marketplaceStoreId,
    required String name,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    final store = await _storeRepository.findById(marketplaceStoreId);
    if (store == null) {
      throw UnknownMarketplaceEntityViolation(
        entityName: 'MarketplaceStore',
        id: marketplaceStoreId,
      );
    }
    final account =
        await _accountRepository.findById(store.marketplaceAccountId);
    if (account == null) {
      throw UnknownMarketplaceEntityViolation(
        entityName: 'MarketplaceAccount',
        id: store.marketplaceAccountId,
      );
    }

    const action = PosAuthorizedAction.manageTenantIntegrations;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {
        kOrganizationIdAuthorizationContextKey: account.organizationId,
      },
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final restaurant = VirtualRestaurant(
      id: _idGenerator.nextVirtualRestaurantId(),
      marketplaceStoreId: marketplaceStoreId,
      name: name,
      createdAt: performedAt,
      revision: 1,
    );
    await _repository.save(restaurant);

    await _auditRepository.appendEvent(MarketplaceAuditEntry(
      id: '${restaurant.id}-audit-created',
      organizationId: account.organizationId,
      actorId: performedByStaffId,
      type: MarketplaceAuditEventType.virtualRestaurantCreated,
      description: 'Virtual restaurant "$name" created under store '
          '"$marketplaceStoreId"',
      targetEntityId: restaurant.id,
      timestamp: performedAt,
    ));

    return restaurant;
  }
}
