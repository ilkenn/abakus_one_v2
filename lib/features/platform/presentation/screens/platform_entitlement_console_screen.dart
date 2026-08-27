import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../admin/domain/organization/organization.dart';
import '../../../entitlements/domain/entitlement_grant.dart';
import '../../../entitlements/domain/entitlement_module.dart';
import '../../../entitlements/domain/entitlement_scope_type.dart';
import '../../../entitlements/domain/entitlement_status.dart';
import '../../../entitlements/presentation/providers/entitlement_dependencies_provider.dart';
import '../../data/entitlement_admin_gateway.dart';
import '../providers/platform_dependencies_provider.dart';

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

const _statusLabels = {
  EntitlementStatus.trial: 'Deneme',
  EntitlementStatus.active: 'Aktif',
  EntitlementStatus.grace: 'Ek Süre',
  EntitlementStatus.suspended: 'Askıya Alındı',
  EntitlementStatus.expired: 'Süresi Doldu',
  EntitlementStatus.revoked: 'İptal Edildi',
};

final _tenantsProvider = FutureProvider<List<Organization>>((ref) {
  return ref.watch(platformOrganizationRepositoryProvider).findAll();
});

final _orgEntitlementsProvider =
    FutureProvider.family<List<EntitlementGrant>, String>(
        (ref, organizationId) {
  return ref
      .watch(entitlementGrantReadRepositoryProvider)
      .findByScope(EntitlementScopeType.organization, organizationId);
});

/// AP-2 final wiring — the Platform Owner's real entitlement management
/// console. The ONLY UI surface anywhere in this app that calls
/// `grantEntitlement`/`renewEntitlement`/`suspendEntitlement`/
/// `revokeEntitlement` — matching those callables' own
/// `requirePlatformMember` authorization exactly; a Tenant Admin has no
/// path to this screen at all (it lives under [AppRoutes.platform], never
/// linked from the tenant-facing Admin shell).
class PlatformEntitlementConsoleScreen extends ConsumerStatefulWidget {
  const PlatformEntitlementConsoleScreen({super.key});

  @override
  ConsumerState<PlatformEntitlementConsoleScreen> createState() =>
      _PlatformEntitlementConsoleScreenState();
}

class _PlatformEntitlementConsoleScreenState
    extends ConsumerState<PlatformEntitlementConsoleScreen> {
  String? _selectedOrganizationId;

  @override
  Widget build(BuildContext context) {
    final tenantsAsync = ref.watch(_tenantsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Abonelik Yönetimi'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: tenantsAsync.when(
          loading: () => const LoadingView(message: 'İşletmeler yükleniyor...'),
          error: (error, stackTrace) => ErrorView(
            message: 'İşletme dizinine ulaşılamadı.',
            retryLabel: 'Tekrar Dene',
            onRetry: () => ref.invalidate(_tenantsProvider),
          ),
          data: (tenants) {
            if (tenants.isEmpty) {
              return const EmptyView(
                icon: Icons.storefront_outlined,
                message: 'Kayıtlı işletme yok.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedOrganizationId,
                    decoration:
                        const InputDecoration(labelText: 'İşletme Seçin'),
                    items: [
                      for (final org in tenants)
                        DropdownMenuItem(value: org.id, child: Text(org.name)),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedOrganizationId = value),
                  ),
                ),
                if (_selectedOrganizationId != null)
                  Expanded(
                    child: _OrganizationEntitlementsPane(
                      organizationId: _selectedOrganizationId!,
                    ),
                  )
                else
                  const Expanded(
                    child: EmptyView(
                      icon: Icons.touch_app_outlined,
                      message: 'Devam etmek için yukarıdan bir işletme seçin.',
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OrganizationEntitlementsPane extends ConsumerWidget {
  const _OrganizationEntitlementsPane({required this.organizationId});

  final String organizationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grantsAsync = ref.watch(_orgEntitlementsProvider(organizationId));
    return grantsAsync.when(
      loading: () => const LoadingView(message: 'Abonelikler yükleniyor...'),
      error: (error, stackTrace) => ErrorView(
        message: 'Abonelik verisine ulaşılamadı.',
        retryLabel: 'Tekrar Dene',
        onRetry: () => ref.invalidate(_orgEntitlementsProvider(organizationId)),
      ),
      data: (grants) {
        final byModule = {for (final g in grants) g.module: g};
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            for (final module in EntitlementModule.values)
              _ModuleRow(
                organizationId: organizationId,
                module: module,
                grant: byModule[module],
              ),
          ],
        );
      },
    );
  }
}

class _ModuleRow extends ConsumerStatefulWidget {
  const _ModuleRow({
    required this.organizationId,
    required this.module,
    required this.grant,
  });

  final String organizationId;
  final EntitlementModule module;
  final EntitlementGrant? grant;

  @override
  ConsumerState<_ModuleRow> createState() => _ModuleRowState();
}

class _ModuleRowState extends ConsumerState<_ModuleRow> {
  bool _busy = false;

  void _refresh() =>
      ref.invalidate(_orgEntitlementsProvider(widget.organizationId));

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return; // double-submit / concurrent-mutation protection
    setState(() => _busy = true);
    try {
      await action();
      _refresh();
    } on EntitlementAdminException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _promptReason(String title) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Gerekçe (zorunlu)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            // Not disabled based on live text — see `device_registry_screen
            // .dart`'s identical fix/comment for why a plain `TextField`
            // inside this non-`StatefulBuilder` dialog can never re-enable
            // a conditionally-disabled button. Blank input is rejected
            // right after the dialog closes instead.
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );
  }

  Future<DateTime?> _promptDate() {
    return showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: DateTime.now().add(const Duration(days: 365)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grant = widget.grant;
    final gateway = ref.read(entitlementAdminGatewayProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(_moduleLabels[widget.module]!,
                      style: AppTypography.bodyLarge),
                ),
                Text(
                  grant == null ? 'Abonelik yok' : _statusLabels[grant.status]!,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
            if (grant != null) ...[
              Text(
                'Sürüm: ${grant.revision}'
                '${grant.expiresAt != null ? " · Sözleşme bitiş: ${grant.expiresAt}" : ""}'
                '${grant.status == EntitlementStatus.grace && grant.graceEndsAt != null ? " · Ek süre bitiş: ${grant.graceEndsAt}" : ""}',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                if (grant == null) ...[
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => gateway.grant(
                              organizationId: widget.organizationId,
                              scopeType: EntitlementScopeType.organization,
                              scopeId: widget.organizationId,
                              module: widget.module,
                            )),
                    child: const Text('Deneme Oluştur'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => gateway.grant(
                              organizationId: widget.organizationId,
                              scopeType: EntitlementScopeType.organization,
                              scopeId: widget.organizationId,
                              module: widget.module,
                              asActiveImmediately: true,
                            )),
                    child: const Text('Doğrudan Aktifleştir'),
                  ),
                ] else ...[
                  OutlinedButton(
                    onPressed:
                        _busy || grant.status == EntitlementStatus.revoked
                            ? null
                            : () async {
                                final date = await _promptDate();
                                if (date == null) return;
                                await _run(() => gateway.renew(
                                    entitlementId: grant.id,
                                    contractEndsAt: date));
                              },
                    child: const Text('Yenile'),
                  ),
                  OutlinedButton(
                    onPressed:
                        _busy || grant.status == EntitlementStatus.revoked
                            ? null
                            : () async {
                                final reason =
                                    await _promptReason('Aboneliği Askıya Al');
                                if (reason == null) return;
                                await _run(() => gateway.suspend(
                                    entitlementId: grant.id,
                                    reasonMessage: reason));
                              },
                    child: const Text('Askıya Al'),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error),
                    onPressed:
                        _busy || grant.status == EntitlementStatus.revoked
                            ? null
                            : () async {
                                final reason =
                                    await _promptReason('Aboneliği İptal Et');
                                if (reason == null) return;
                                await _run(() => gateway.revoke(
                                    entitlementId: grant.id,
                                    reasonMessage: reason));
                              },
                    child: const Text('İptal Et'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
