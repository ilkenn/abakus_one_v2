import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/marketplace_account_repository.dart';
import '../../data/marketplace_audit_entry_repository.dart';
import '../../data/marketplace_store_repository.dart';
import '../../domain/audit/marketplace_audit_entry.dart';
import '../../domain/audit/marketplace_audit_event_type.dart';
import '../../domain/marketplace_store.dart';
import '../identity/marketplace_store_id_generator.dart';

/// Creates a [MarketplaceStore] under an existing [MarketplaceAccount]
/// — Phase 8 (`docs/decisions.md` ADR-025), "Marketplace Account →
/// Marketplace Store." tenantOwner-only, organization-scoped (resolved
/// from the parent account, since a store has no `organizationId` of
/// its own — "never assume 1 provider, 1 account, 1 restaurant" holds
/// by always deriving scope from the actual owning account).
class CreateMarketplaceStore {
  const CreateMarketplaceStore({
    required PosAuthorizationPolicy authorizationPolicy,
    required MarketplaceAccountRepository accountRepository,
    required MarketplaceStoreIdGenerator idGenerator,
    required MarketplaceStoreRepository repository,
    required MarketplaceAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _accountRepository = accountRepository,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final MarketplaceAccountRepository _accountRepository;
  final MarketplaceStoreIdGenerator _idGenerator;
  final MarketplaceStoreRepository _repository;
  final MarketplaceAuditEntryRepository _auditRepository;

  Future<MarketplaceStore> call({
    required String marketplaceAccountId,
    required String externalStoreId,
    required String storeName,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    final account = await _accountRepository.findById(marketplaceAccountId);
    if (account == null) {
      throw UnknownMarketplaceEntityViolation(
        entityName: 'MarketplaceAccount',
        id: marketplaceAccountId,
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

    final store = MarketplaceStore(
      id: _idGenerator.nextMarketplaceStoreId(),
      marketplaceAccountId: marketplaceAccountId,
      externalStoreId: externalStoreId,
      storeName: storeName,
      createdAt: performedAt,
      revision: 1,
    );
    await _repository.save(store);

    await _auditRepository.appendEvent(MarketplaceAuditEntry(
      id: '${store.id}-audit-created',
      organizationId: account.organizationId,
      actorId: performedByStaffId,
      type: MarketplaceAuditEventType.storeCreated,
      description: 'Marketplace store "$storeName" created under account '
          '"$marketplaceAccountId"',
      targetEntityId: store.id,
      timestamp: performedAt,
    ));

    return store;
  }
}
