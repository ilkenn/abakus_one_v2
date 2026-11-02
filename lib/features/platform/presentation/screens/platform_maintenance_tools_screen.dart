import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/functions/maintenance_operations_gateway.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../entitlements/domain/entitlement_module.dart';
import '../../../entitlements/domain/entitlement_scope_type.dart';
import '../../data/entitlement_admin_gateway.dart';
import '../providers/platform_dependencies_provider.dart';

/// 2026-10-30 — "Bakım Araçları" (Maintenance Tools): the key-free
/// alternative to running `migrate_canonical_catalog_to_project.mjs`
/// with a downloaded service-account key. Calls a real,
/// `requirePlatformMember`-gated Cloud Function that runs under its own
/// deployed service-account identity — see
/// `maintenance_operations_gateway.dart`'s own doc comment.
///
/// Branch renaming (`renameBranch`) deliberately does **not** live here:
/// it's gated by `requireStaffPermission("manageBranch")`, a wholly
/// separate claim namespace a pure Platform-member session never
/// satisfies (the same documented constraint behind this shell's own
/// "Kiracı Admin Paneline Geç" icon) — its button lives in the tenant
/// Admin shell's Menü screen instead, where a real staff session exists.
class PlatformMaintenanceToolsScreen extends ConsumerStatefulWidget {
  const PlatformMaintenanceToolsScreen({super.key});

  @override
  ConsumerState<PlatformMaintenanceToolsScreen> createState() =>
      _PlatformMaintenanceToolsScreenState();
}

class _PlatformMaintenanceToolsScreenState
    extends ConsumerState<PlatformMaintenanceToolsScreen> {
  final _orgController = TextEditingController(text: 'org-1');
  final _restaurantController = TextEditingController(text: 'restaurant-1');

  bool _syncBusy = false;
  bool _entitlementsBusy = false;
  String? _lastResultMessage;

  @override
  void dispose() {
    _orgController.dispose();
    _restaurantController.dispose();
    super.dispose();
  }

  /// "Tüm Modülleri Aktifleştir" — **not** a bypass: loops the exact same
  /// `grantEntitlement` callable `PlatformEntitlementConsoleScreen`'s own
  /// per-module buttons already call, still `requirePlatformMember`-gated
  /// server-side, still real audited writes to the real `entitlements`
  /// collection. The literal `entitlements: ['*']` the product owner asked
  /// for isn't a value the backend understands (`EntitlementModule` is a
  /// closed, named enum — wildcards were never part of its shape) — this
  /// is the equivalent real effect: every one of the 21 real modules,
  /// granted active, individually and auditably.
  Future<void> _activateAllModules() async {
    setState(() {
      _entitlementsBusy = true;
      _lastResultMessage = null;
    });
    final organizationId = _orgController.text.trim();
    final gateway = ref.read(entitlementAdminGatewayProvider);
    var granted = 0;
    final failures = <String>[];
    for (final module in EntitlementModule.values) {
      try {
        await gateway.grant(
          organizationId: organizationId,
          scopeType: EntitlementScopeType.organization,
          scopeId: organizationId,
          module: module,
          asActiveImmediately: true,
        );
        granted += 1;
      } on EntitlementAdminException catch (e) {
        failures.add('${module.name}: ${e.message}');
      }
    }
    if (!mounted) return;
    setState(() {
      _entitlementsBusy = false;
      _lastResultMessage = failures.isEmpty
          ? '$organizationId için ${EntitlementModule.values.length} '
              'modülün tamamı aktifleştirildi.'
          : '$granted/${EntitlementModule.values.length} modül '
              'aktifleştirildi. Başarısız olanlar: ${failures.join(", ")}';
    });
  }

  Future<void> _runSync() async {
    setState(() {
      _syncBusy = true;
      _lastResultMessage = null;
    });
    try {
      final gateway = ref.read(maintenanceOperationsGatewayProvider);
      final result = await gateway.syncCanonicalCatalog(
        organizationId: _orgController.text.trim(),
        restaurantId: _restaurantController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _lastResultMessage = 'Eşitlendi — ${result.productsWritten} ürün, '
            '${result.categoriesWritten} kategori, '
            '${result.ingredientsWritten} bowl malzemesi'
            '${result.exportedAt != null ? ' (dışa aktarım: ${result.exportedAt})' : ''}.';
      });
    } on MaintenanceOperationsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const Text('Kiracı Kimliği', style: AppTypography.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _orgController,
              decoration: const InputDecoration(labelText: 'organizationId'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _restaurantController,
              decoration: const InputDecoration(labelText: 'restaurantId'),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Menü ve Varyasyonları Eşitle',
                      style: AppTypography.bodyLarge
                          .copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Dart kataloğunun (Bowl karbonhidrat/salata/turşu hakları, '
                    'Burger/Wrap eşlikçileri, çapraz satış grupları dahil) son '
                    'dışa aktarılmış hâlini gerçek Firestore katalog '
                    'koleksiyonlarına yazar. Service-account key gerekmez — '
                    'bu düğme, kendi dağıtılmış kimliğiyle çalışan gerçek bir '
                    'Cloud Function\'ı çağırır.',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: _syncBusy ? null : _runSync,
                    child: _syncBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Menü ve Varyasyonları Eşitle'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tüm Modülleri Aktifleştir',
                      style: AppTypography.bodyLarge
                          .copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${EntitlementModule.values.length} gerçek modülün '
                    '(pos, kds, qrMenu, smartRestaurantSetup, '
                    'advancedReporting dahil) tamamını yukarıdaki '
                    'organizationId için tek seferde "active" olarak '
                    'tanımlar — "Abonelikler" sekmesindeki aynı gerçek '
                    'grantEntitlement çağrısı, modül modül değil hepsi '
                    'birden.',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: _entitlementsBusy ? null : _activateAllModules,
                    child: _entitlementsBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Tüm Modülleri Aktifleştir'),
                  ),
                ],
              ),
            ),
            if (_lastResultMessage != null) ...[
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(_lastResultMessage!,
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.success)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
