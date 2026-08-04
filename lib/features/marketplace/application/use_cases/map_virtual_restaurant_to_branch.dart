import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/marketplace_account_repository.dart';
import '../../data/marketplace_audit_entry_repository.dart';
import '../../data/marketplace_branch_mapping_repository.dart';
import '../../data/marketplace_store_repository.dart';
import '../../data/virtual_restaurant_repository.dart';
import '../../domain/audit/marketplace_audit_entry.dart';
import '../../domain/audit/marketplace_audit_event_type.dart';
import '../../domain/marketplace_branch_mapping.dart';
import '../identity/marketplace_branch_mapping_id_generator.dart';

/// Links a [VirtualRestaurant] to the real `Branch` that fulfills it —
/// Phase 8 (`docs/decisions.md` ADR-025), "Virtual Restaurant → Branch
/// Mapping." Re-calling with a different [branchId] re-maps (the
/// repository is keyed by `virtualRestaurantId`, one mapping per
/// virtual restaurant) rather than accumulating stale mappings.
class MapVirtualRestaurantToBranch {
  const MapVirtualRestaurantToBranch({
    required PosAuthorizationPolicy authorizationPolicy,
    required VirtualRestaurantRepository virtualRestaurantRepository,
    required MarketplaceStoreRepository storeRepository,
    required MarketplaceAccountRepository accountRepository,
    required MarketplaceBranchMappingIdGenerator idGenerator,
    required MarketplaceBranchMappingRepository repository,
    required MarketplaceAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _virtualRestaurantRepository = virtualRestaurantRepository,
        _storeRepository = storeRepository,
        _accountRepository = accountRepository,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final VirtualRestaurantRepository _virtualRestaurantRepository;
  final MarketplaceStoreRepository _storeRepository;
  final MarketplaceAccountRepository _accountRepository;
  final MarketplaceBranchMappingIdGenerator _idGenerator;
  final MarketplaceBranchMappingRepository _repository;
  final MarketplaceAuditEntryRepository _auditRepository;

  Future<MarketplaceBranchMapping> call({
    required String virtualRestaurantId,
    required String branchId,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    final restaurant =
        await _virtualRestaurantRepository.findById(virtualRestaurantId);
    if (restaurant == null) {
      throw UnknownMarketplaceEntityViolation(
        entityName: 'VirtualRestaurant',
        id: virtualRestaurantId,
      );
    }
    final store =
        await _storeRepository.findById(restaurant.marketplaceStoreId);
    if (store == null) {
      throw UnknownMarketplaceEntityViolation(
        entityName: 'MarketplaceStore',
        id: restaurant.marketplaceStoreId,
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

    final existing =
        await _repository.findByVirtualRestaurantId(virtualRestaurantId);
    final mapping = MarketplaceBranchMapping(
      id: existing?.id ?? _idGenerator.nextMarketplaceBranchMappingId(),
      virtualRestaurantId: virtualRestaurantId,
      branchId: branchId,
      createdAt: existing?.createdAt ?? performedAt,
      revision: (existing?.revision ?? 0) + 1,
    );
    await _repository.save(mapping);

    await _auditRepository.appendEvent(MarketplaceAuditEntry(
      id: '${mapping.id}-audit-mapped-${performedAt.microsecondsSinceEpoch}',
      organizationId: account.organizationId,
      actorId: performedByStaffId,
      type: MarketplaceAuditEventType.branchMapped,
      description: 'Virtual restaurant "$virtualRestaurantId" mapped to '
          'branch "$branchId"',
      targetEntityId: mapping.id,
      timestamp: performedAt,
    ));

    return mapping;
  }
}
