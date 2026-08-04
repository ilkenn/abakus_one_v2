import '../../../../core/services/feature_flags/feature_flags_keys.dart';
import '../../../../core/services/feature_flags/feature_flags_service.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart'
    show
        kBranchIdAuthorizationContextKey,
        kOrganizationIdAuthorizationContextKey;
import '../../data/entitlement_grant_repository.dart';
import '../../domain/entitlement_module.dart';
import '../../domain/entitlement_scope_type.dart';
import '../../domain/module_access_denial_reason.dart';
import '../../domain/module_access_result.dart';

/// The single composed check every Phase 7 screen/use case must pass
/// before it is usable — "all three must authorize access" (Phase 7,
/// `docs/decisions.md` ADR-024):
///
/// 1. **Entitlement** — has the tenant purchased this module?
///    (`EntitlementGrantRepository`).
/// 2. **Feature flag** — is the functionality technically enabled?
///    (`FeatureFlagsService`).
/// 3. **Role permission** — may the current actor perform this action?
///    (`PosAuthorizationPolicy`).
///
/// Checked in this exact order so the reported [ModuleAccessDenialReason]
/// is the most fundamental blocker first — "hiding a menu item is not
/// sufficient" applies equally to which reason surfaces: a
/// not-entitled tenant should never be told "you lack permission," which
/// would incorrectly suggest purchasing wouldn't help alone.
class CheckModuleAccess {
  const CheckModuleAccess({
    required EntitlementGrantRepository entitlementRepository,
    required FeatureFlagsService featureFlagsService,
    required PosAuthorizationPolicy authorizationPolicy,
  })  : _entitlementRepository = entitlementRepository,
        _featureFlagsService = featureFlagsService,
        _authorizationPolicy = authorizationPolicy;

  final EntitlementGrantRepository _entitlementRepository;
  final FeatureFlagsService _featureFlagsService;
  final PosAuthorizationPolicy _authorizationPolicy;

  static const Map<EntitlementModule, String> _featureFlagKeyByModule = {
    EntitlementModule.smartRestaurantSetup:
        FeatureFlagsKeys.smartRestaurantSetupEnabled,
    EntitlementModule.menuImport: FeatureFlagsKeys.menuImportEnabled,
    EntitlementModule.inventory: FeatureFlagsKeys.inventoryEnabled,
    EntitlementModule.recipes: FeatureFlagsKeys.recipesEnabled,
    EntitlementModule.nutrition: FeatureFlagsKeys.nutritionEnabled,
    EntitlementModule.allergens: FeatureFlagsKeys.allergensEnabled,
    EntitlementModule.purchasing: FeatureFlagsKeys.purchasingEnabled,
    EntitlementModule.suppliers: FeatureFlagsKeys.suppliersEnabled,
    EntitlementModule.costing: FeatureFlagsKeys.costingEnabled,
    EntitlementModule.profitability: FeatureFlagsKeys.profitabilityEnabled,
    EntitlementModule.advancedReporting:
        FeatureFlagsKeys.advancedReportingEnabled,
    // Phase 8 (`docs/decisions.md` ADR-025). qrMenu/reservations
    // deliberately reuse the pre-existing flags those features already
    // had before module entitlements existed.
    EntitlementModule.qrMenu: FeatureFlagsKeys.qrScannerEnabled,
    EntitlementModule.reservations: FeatureFlagsKeys.reservationsEnabled,
    EntitlementModule.crm: FeatureFlagsKeys.crmEnabled,
    EntitlementModule.loyalty: FeatureFlagsKeys.loyaltyEnabled,
    EntitlementModule.pos: FeatureFlagsKeys.posModuleEnabled,
    EntitlementModule.kds: FeatureFlagsKeys.kdsModuleEnabled,
    EntitlementModule.courier: FeatureFlagsKeys.courierModuleEnabled,
    EntitlementModule.marketplace: FeatureFlagsKeys.marketplaceEnabled,
    EntitlementModule.payments: FeatureFlagsKeys.paymentsEnabled,
    EntitlementModule.ai: FeatureFlagsKeys.aiEnabled,
  };

  /// The representative "may this actor use this module at all" action
  /// per module — individual mutations within a module (e.g.
  /// `recordStockCount` vs. `manageInventory`) still run their own,
  /// finer-grained `authorize()` call at the use-case level; this is the
  /// module-entry-point gate only.
  static const Map<EntitlementModule, PosAuthorizedAction> _actionByModule = {
    EntitlementModule.smartRestaurantSetup:
        PosAuthorizedAction.manageRestaurantSetup,
    EntitlementModule.menuImport: PosAuthorizedAction.manageSmartImport,
    EntitlementModule.inventory: PosAuthorizedAction.manageInventory,
    EntitlementModule.recipes: PosAuthorizedAction.manageRecipes,
    EntitlementModule.nutrition: PosAuthorizedAction.manageNutrition,
    EntitlementModule.allergens: PosAuthorizedAction.manageAllergens,
    EntitlementModule.purchasing: PosAuthorizedAction.managePurchasing,
    EntitlementModule.suppliers: PosAuthorizedAction.manageSuppliers,
    EntitlementModule.costing: PosAuthorizedAction.manageCostingConfiguration,
    EntitlementModule.profitability: PosAuthorizedAction.viewProfitability,
    EntitlementModule.advancedReporting:
        PosAuthorizedAction.viewAdvancedReporting,
    // Phase 8 (`docs/decisions.md` ADR-025). marketplace/payments
    // deliberately reuse `manageTenantIntegrations` — both are, per the
    // kickoff's own framing, Integration Hub configuration rather than
    // a distinct standalone module action.
    EntitlementModule.qrMenu: PosAuthorizedAction.manageQrMenuConfiguration,
    EntitlementModule.reservations: PosAuthorizedAction.manageReservations,
    EntitlementModule.crm: PosAuthorizedAction.manageCrmModule,
    EntitlementModule.loyalty: PosAuthorizedAction.manageLoyaltyModule,
    EntitlementModule.pos: PosAuthorizedAction.usePosModule,
    EntitlementModule.kds: PosAuthorizedAction.useKdsModule,
    EntitlementModule.courier: PosAuthorizedAction.manageCourierModule,
    EntitlementModule.marketplace: PosAuthorizedAction.manageTenantIntegrations,
    EntitlementModule.payments: PosAuthorizedAction.manageTenantIntegrations,
    EntitlementModule.ai: PosAuthorizedAction.manageAiModule,
  };

  Future<ModuleAccessResult> call({
    required EntitlementModule module,
    required EntitlementScopeType scopeType,
    required String scopeId,
    required String actorStaffId,
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();

    final grant = await _entitlementRepository.findByModuleAndScope(
      module,
      scopeType,
      scopeId,
    );
    if (grant == null || !grant.isCurrentlyEntitled(now)) {
      return const ModuleAccessResult.denied(
        ModuleAccessDenialReason.notEntitled,
      );
    }

    final flagKey = _featureFlagKeyByModule[module]!;
    if (!_featureFlagsService.isEnabled(flagKey)) {
      return const ModuleAccessResult.denied(
        ModuleAccessDenialReason.featureDisabled,
      );
    }

    final action = _actionByModule[module]!;
    // Phase 8S security pass (`docs/decisions.md` ADR-025): every scope
    // type that has a corresponding `RealPosAuthorizationPolicy` context
    // check must forward it — a scope this switch doesn't recognize must
    // never silently skip authorization context. `EntitlementScopeType
    // .restaurant` has no equivalent check anywhere in this codebase's
    // authorization policy yet (only branch/organization exist) — a
    // separate, pre-existing gap, not invented here.
    final Map<String, String> authorizationContext;
    switch (scopeType) {
      case EntitlementScopeType.branch:
        authorizationContext = {kBranchIdAuthorizationContextKey: scopeId};
      case EntitlementScopeType.organization:
        authorizationContext = {
          kOrganizationIdAuthorizationContextKey: scopeId,
        };
      case EntitlementScopeType.restaurant:
        authorizationContext = const {};
    }
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: actorStaffId,
      context: authorizationContext,
    );
    if (!authResult.granted) {
      return const ModuleAccessResult.denied(
        ModuleAccessDenialReason.permissionDenied,
      );
    }

    return const ModuleAccessResult.granted();
  }
}
