import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/payment_hub_audit_entry_repository.dart';
import '../../data/payment_merchant_account_repository.dart';
import '../../data/payment_merchant_method_mapping_repository.dart';
import '../../domain/audit/payment_hub_audit_entry.dart';
import '../../domain/audit/payment_hub_audit_event_type.dart';
import '../../domain/payment_merchant_method_mapping.dart';
import '../identity/payment_merchant_method_mapping_id_generator.dart';

/// "Merchant Account → Payment Methods" — Phase 8 (`docs/decisions.md`
/// ADR-025), links an existing `PaymentMethod` id to a
/// [PaymentMerchantAccount] as the account that processes it.
/// Re-calling for the same `(merchantAccountId, paymentMethodId)` pair
/// is a no-op returning the existing mapping, never a duplicate.
class MapPaymentMethodToMerchantAccount {
  const MapPaymentMethodToMerchantAccount({
    required PosAuthorizationPolicy authorizationPolicy,
    required PaymentMerchantAccountRepository accountRepository,
    required PaymentMerchantMethodMappingIdGenerator idGenerator,
    required PaymentMerchantMethodMappingRepository repository,
    required PaymentHubAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _accountRepository = accountRepository,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final PaymentMerchantAccountRepository _accountRepository;
  final PaymentMerchantMethodMappingIdGenerator _idGenerator;
  final PaymentMerchantMethodMappingRepository _repository;
  final PaymentHubAuditEntryRepository _auditRepository;

  Future<PaymentMerchantMethodMapping> call({
    required String merchantAccountId,
    required String paymentMethodId,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    final account = await _accountRepository.findById(merchantAccountId);
    if (account == null) {
      throw UnknownPaymentHubEntityViolation(
        entityName: 'PaymentMerchantAccount',
        id: merchantAccountId,
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

    final existing = await _repository.findByMerchantAccountAndMethod(
      merchantAccountId,
      paymentMethodId,
    );
    if (existing != null) return existing;

    final mapping = PaymentMerchantMethodMapping(
      id: _idGenerator.nextPaymentMerchantMethodMappingId(),
      merchantAccountId: merchantAccountId,
      paymentMethodId: paymentMethodId,
      createdAt: performedAt,
      revision: 1,
    );
    await _repository.save(mapping);

    await _auditRepository.appendEvent(PaymentHubAuditEntry(
      id: '${mapping.id}-audit-mapped',
      organizationId: account.organizationId,
      actorId: performedByStaffId,
      type: PaymentHubAuditEventType.paymentMethodMapped,
      description:
          'Payment method "$paymentMethodId" mapped to merchant account '
          '"$merchantAccountId"',
      targetEntityId: mapping.id,
      timestamp: performedAt,
    ));

    return mapping;
  }
}
