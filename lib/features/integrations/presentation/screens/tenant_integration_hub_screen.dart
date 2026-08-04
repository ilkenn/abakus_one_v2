import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../application/use_cases/set_tenant_integration_enabled.dart';
import '../../domain/integration_audit_center_entry.dart';
import '../../domain/integration_connection_status.dart';
import '../../domain/integration_provider_category.dart';
import '../../domain/provider_health_entry.dart';
import '../providers/integration_dependencies_provider.dart';

const _categoryLabels = {
  IntegrationProviderCategory.marketplace: 'Pazaryeri',
  IntegrationProviderCategory.payment: 'Ödeme',
};

const _statusLabels = {
  IntegrationConnectionStatus.notConfigured: 'Yapılandırılmadı',
  IntegrationConnectionStatus.configured: 'Yapılandırıldı',
  IntegrationConnectionStatus.connected: 'Bağlı',
  IntegrationConnectionStatus.error: 'Hata',
  IntegrationConnectionStatus.disabled: 'Devre Dışı',
};

const _auditDomainLabels = {
  'integration': 'Entegrasyon',
  'marketplace': 'Pazaryeri',
  'payment-hub': 'Ödeme Merkezi',
};

/// Tenant-facing Integration Hub — Phase 8R (`docs/decisions.md`
/// ADR-025), the first admin-reachable surface for Phase 8's
/// Integration Hub (8H)/Provider Health (8M)/Integration Audit (8N)
/// foundations. Combines: the platform's provider catalog with this
/// tenant's own enable/disable state
/// ([BuildProviderHealthProjection]), a real toggle
/// ([SetTenantIntegrationEnabled]), and a recent-activity list
/// ([BuildIntegrationAuditCenterProjection]) — three previously
/// screen-less use cases surfaced through one cohesive tenant screen.
///
/// Deliberately does **not** attempt full Marketplace Hub/Payment Hub
/// CRUD (account/store/virtual-restaurant/merchant-account management)
/// — those remain domain/application-only this phase, consistent with
/// every other Phase 8 part's "foundation only, presentation deferred"
/// scope, and are reported as such rather than silently expanded here.
class TenantIntegrationHubScreen extends ConsumerStatefulWidget {
  const TenantIntegrationHubScreen({
    super.key,
    required this.organizationId,
    required this.authorizationPolicy,
    required this.performedByStaffId,
  });

  final String organizationId;
  final PosAuthorizationPolicy authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<TenantIntegrationHubScreen> createState() =>
      _TenantIntegrationHubScreenState();
}

class _TenantIntegrationHubScreenState
    extends ConsumerState<TenantIntegrationHubScreen> {
  List<ProviderHealthEntry>? _providers;
  List<IntegrationAuditCenterEntry>? _recentActivity;
  String? _error;
  String? _busyProviderId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final providers = await ref
        .read(buildProviderHealthProjectionProvider)
        .call(organizationId: widget.organizationId);
    final activity = await ref
        .read(buildIntegrationAuditCenterProjectionProvider)
        .call(organizationId: widget.organizationId, limit: 10);
    if (!mounted) return;
    setState(() {
      _providers = providers;
      _recentActivity = activity;
    });
  }

  Future<void> _toggle(ProviderHealthEntry entry, bool enabled) async {
    setState(() {
      _busyProviderId = entry.providerId;
      _error = null;
    });
    try {
      await SetTenantIntegrationEnabled(
        authorizationPolicy: widget.authorizationPolicy,
        providerRegistry: ref.read(integrationProviderRegistryProvider),
        idGenerator:
            ref.read(tenantIntegrationConfigurationIdGeneratorProvider),
        repository: ref.read(tenantIntegrationConfigurationRepositoryProvider),
        auditRepository: ref.read(integrationAuditEntryRepositoryProvider),
      )(
        organizationId: widget.organizationId,
        providerId: entry.providerId,
        enabled: enabled,
        performedByStaffId: widget.performedByStaffId,
        performedAt: DateTime.now(),
      );
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busyProviderId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final providers = _providers;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Entegrasyonlar'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: providers == null
            ? const LoadingView(message: 'Sağlayıcılar yükleniyor...')
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  if (_error != null) ...[
                    Text(_error!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.error)),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  const Text('Sağlayıcı Kataloğu',
                      style: AppTypography.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Hiçbir sağlayıcı gerçek bir satıcı SDK\'sına bağlı '
                    'değil — burada açma/kapama yalnızca bu kiracının '
                    'yapılandırma tercihini kaydeder.',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (providers.isEmpty)
                    const EmptyView(
                      icon: Icons.extension_off_outlined,
                      message: 'Kayıtlı sağlayıcı yok.',
                    )
                  else
                    for (final entry in providers)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AppCard(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(entry.displayName,
                                        style: AppTypography.bodyLarge),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      '${_categoryLabels[entry.category]} · '
                                      '${_statusLabels[entry.connectionStatus]}',
                                      style: AppTypography.bodySmall.copyWith(
                                          color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              _busyProviderId == entry.providerId
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Switch(
                                      value: entry.tenantEnabled,
                                      onChanged: (value) =>
                                          _toggle(entry, value),
                                    ),
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('Son Etkinlik', style: AppTypography.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  if (_recentActivity == null)
                    const LoadingView(message: 'Etkinlik yükleniyor...')
                  else if (_recentActivity!.isEmpty)
                    const EmptyView(
                      icon: Icons.history_outlined,
                      message: 'Henüz bir entegrasyon etkinliği yok.',
                    )
                  else
                    for (final entry in _recentActivity!)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: AppCard(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_auditDomainLabels[entry.domain] ?? entry.domain} · '
                                '${entry.description}',
                                style: AppTypography.bodyMedium,
                              ),
                              Text(
                                'Aktör: ${entry.actorId} · ${entry.timestamp}',
                                style: AppTypography.bodySmall
                                    .copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
      ),
    );
  }
}
