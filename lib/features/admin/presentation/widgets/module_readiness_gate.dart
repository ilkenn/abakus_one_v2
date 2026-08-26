import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// AP-2 Stage B, §11/Correction #9 — implementation-readiness registry.
/// Distinct from [ModuleEntitlementGate] (has the tenant PURCHASED this
/// module?): this answers "does a real backend for this module actually
/// exist yet in THIS codebase?" — a purchased, fully-entitled module can
/// still be `demoOnly` if AP-3 through AP-7 haven't wired it yet.
/// Deliberately a static, explicit, auditable list — adding a module here
/// as `productionReady` is itself the disclosure that its backend now
/// exists; nothing infers readiness from entitlement or device state.
enum ModuleImplementationStatus { productionReady, demoOnly }

abstract final class ModuleReadinessRegistry {
  ModuleReadinessRegistry._();

  /// Every module id NOT yet wired to a real backend as of AP-2 — table/
  /// order operations (AP-3), payment/cash/fiscal (AP-4), KDS/stock (AP-5),
  /// courier/marketplace (AP-6), CRM/reports (AP-7). Update this set only
  /// as each phase actually closes its own backend wiring — never
  /// preemptively.
  static const Set<String> _demoOnlyModuleIds = {
    'tableOrders',
    'pos',
    'cash',
    'fiscal',
    'kds',
    'stock',
    'courier',
    'marketplace',
    'crm',
    'reports',
  };

  static ModuleImplementationStatus statusOf(String moduleId) {
    return _demoOnlyModuleIds.contains(moduleId)
        ? ModuleImplementationStatus.demoOnly
        : ModuleImplementationStatus.productionReady;
  }
}

/// Screen-level fail-closed gate for a `demoOnly` module — mirrors
/// `ModuleEntitlementGate`'s exact shape (screen-level, not just a
/// navigation-entry check, so a deep link is re-checked every time).
///
/// A `demoOnly` module is blocked outright in a release build — no
/// exception, entitlement or trusted-device state notwithstanding
/// (Correction #9: "Entitlement verilmesi... otomatik olarak
/// production-ready yapmaz. Trusted device aktif olması da... orphan/
/// in-memory ekranı production-ready yapmaz"). In a debug/profile build,
/// the module remains reachable but is wrapped in a visible `DEMO` banner
/// — `kReleaseMode` itself is the "explicit environment flag" this gate
/// keys on, mirroring every existing `ProductionUnavailable*` repository's
/// own established gate in this codebase, not a new mechanism.
class ModuleReadinessGate extends StatelessWidget {
  const ModuleReadinessGate({
    super.key,
    required this.moduleId,
    required this.child,
  });

  final String moduleId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final status = ModuleReadinessRegistry.statusOf(moduleId);
    if (status == ModuleImplementationStatus.productionReady) {
      return child;
    }
    if (kReleaseMode) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Kullanıma Açık Değil'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.construction_outlined,
                      size: 48, color: AppColors.textSecondary),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Bu modül henüz production kullanımına açılmadı.',
                    style: AppTypography.bodyLarge
                        .copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Stack(
      children: [
        child,
        Positioned(
          top: AppSpacing.sm,
          right: AppSpacing.sm,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.warning,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Text(
              'DEMO',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.surface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
