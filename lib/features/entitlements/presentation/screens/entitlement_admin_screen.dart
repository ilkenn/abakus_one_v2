import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../application/use_cases/grant_module_entitlement.dart';
import '../../application/use_cases/set_entitlement_status.dart';
import '../../domain/entitlement_grant.dart';
import '../../domain/entitlement_module.dart';
import '../../domain/entitlement_scope_type.dart';
import '../../domain/entitlement_status.dart';
import '../providers/entitlement_dependencies_provider.dart';

const _moduleLabels = {
  EntitlementModule.smartRestaurantSetup: 'Akıllı Kurulum',
  EntitlementModule.menuImport: 'Menü İçe Aktarma',
  EntitlementModule.inventory: 'Stok Yönetimi',
  EntitlementModule.recipes: 'Reçeteler',
  EntitlementModule.nutrition: 'Beslenme Değerleri',
  EntitlementModule.allergens: 'Alerjenler',
  EntitlementModule.purchasing: 'Satın Alma',
  EntitlementModule.suppliers: 'Tedarikçiler',
  EntitlementModule.costing: 'Maliyetlendirme',
  EntitlementModule.profitability: 'Kârlılık',
  EntitlementModule.advancedReporting: 'Gelişmiş Raporlama',
  // Phase 8 (`docs/decisions.md` ADR-025).
  EntitlementModule.qrMenu: 'QR Menü',
  EntitlementModule.reservations: 'Rezervasyonlar',
  EntitlementModule.crm: 'CRM',
  EntitlementModule.loyalty: 'Sadakat Programı',
  EntitlementModule.pos: 'POS',
  EntitlementModule.kds: 'Mutfak Ekranı (KDS)',
  EntitlementModule.courier: 'Kurye Operasyonları',
  EntitlementModule.marketplace: 'Pazaryeri Entegrasyonu',
  EntitlementModule.payments: 'Ödeme Entegrasyonu',
  EntitlementModule.ai: 'Yapay Zeka',
};

/// Manages which Phase 7 modules a scope (here: the current branch) has
/// purchased — admin-only (`PosAuthorizedAction.manageEntitlements`).
/// "No payment/subscription billing in this phase" — every action here
/// records a subscription *decision*, never processes a payment.
class EntitlementAdminScreen extends ConsumerStatefulWidget {
  const EntitlementAdminScreen({
    super.key,
    required this.branchId,
    this.authorizationPolicy,
    this.performedByStaffId = '',
  });

  final String branchId;
  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<EntitlementAdminScreen> createState() =>
      _EntitlementAdminScreenState();
}

class _EntitlementAdminScreenState
    extends ConsumerState<EntitlementAdminScreen> {
  List<EntitlementGrant>? _grants;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final grants = await ref
        .read(entitlementGrantRepositoryProvider)
        .findByScope(EntitlementScopeType.branch, widget.branchId);
    if (!mounted) return;
    setState(() => _grants = grants);
  }

  Future<void> _requirePolicyAsync(
    Future<void> Function(PosAuthorizationPolicy policy) run,
  ) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await run(policy);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _setStatus(EntitlementGrant grant, EntitlementStatus status) {
    return _requirePolicyAsync((policy) async {
      await SetEntitlementStatus(
        authorizationPolicy: policy,
        repository: ref.read(entitlementGrantRepositoryProvider),
        auditRepository: ref.read(entitlementAuditEntryRepositoryProvider),
      )(
        grantId: grant.id,
        newStatus: status,
        performedByStaffId: widget.performedByStaffId,
        performedAt: DateTime.now(),
      );
      await _load();
    });
  }

  Future<void> _grant(EntitlementModule module) {
    return _requirePolicyAsync((policy) async {
      await GrantModuleEntitlement(
        authorizationPolicy: policy,
        idGenerator: ref.read(entitlementGrantIdGeneratorProvider),
        repository: ref.read(entitlementGrantRepositoryProvider),
        auditRepository: ref.read(entitlementAuditEntryRepositoryProvider),
      )(
        module: module,
        scopeType: EntitlementScopeType.branch,
        scopeId: widget.branchId,
        status: EntitlementStatus.trial,
        performedByStaffId: widget.performedByStaffId,
        performedAt: DateTime.now(),
      );
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final grants = _grants;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Modül Abonelikleri'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: grants == null
            ? const LoadingView(message: 'Abonelikler yükleniyor...')
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  if (_error != null) ...[
                    Text(_error!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.error)),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  for (final module in EntitlementModule.values)
                    Builder(builder: (context) {
                      final grant = grants
                          .where((g) => g.module == module)
                          .cast<EntitlementGrant?>()
                          .firstWhere((_) => true, orElse: () => null);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AppCard(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_moduleLabels[module]!,
                                        style: AppTypography.bodyLarge),
                                    Text(
                                      grant == null
                                          ? 'Abonelik yok'
                                          : grant.status.name,
                                      style: AppTypography.bodySmall.copyWith(
                                          color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              if (grant == null)
                                OutlinedButton(
                                  onPressed: () => _grant(module),
                                  child: const Text('Deneme Ver'),
                                )
                              else
                                Wrap(
                                  spacing: AppSpacing.sm,
                                  children: [
                                    if (grant.status !=
                                        EntitlementStatus.active)
                                      OutlinedButton(
                                        onPressed: () => _setStatus(
                                            grant, EntitlementStatus.active),
                                        child: const Text('Etkinleştir'),
                                      ),
                                    if (grant.status !=
                                        EntitlementStatus.revoked)
                                      OutlinedButton(
                                        onPressed: () => _setStatus(
                                            grant, EntitlementStatus.revoked),
                                        child: const Text('İptal Et'),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
      ),
    );
  }
}
