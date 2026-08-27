import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// AP-2 closure correction — the full, exhaustive implementation-readiness
/// classification for every real `AdminShellScreen` nav-item id (source:
/// `admin_shell_screen.dart`'s own `_groups()` — every id here is copied
/// verbatim from that file's `_AdminNavItem(id: '...')` literals, never
/// guessed). Distinct from [ModuleEntitlementGate] (has the tenant
/// PURCHASED this module?): this answers "does a real backend for this
/// SPECIFIC screen actually exist and is this screen actually wired to
/// it?" — a purchased, fully-entitled module can still be non-production
/// if the screen itself still reads an in-memory repository.
enum ModuleReadinessClassification {
  /// A real Cloud Function + Firestore-backed repository/gateway backs
  /// this exact screen — verified by reading its own provider chain, not
  /// inferred from a sibling screen or feature name.
  productionReady,

  /// A real backend exists in `functions/src/**` for this domain, but the
  /// backend has not been deployed to a real (non-emulator) Firebase
  /// project — code-real, deployment-pending. Treated identically to
  /// [productionReady] for the gate's own binary release decision (the
  /// code itself is real and tested; only deployment status differs, and
  /// this app has no real deployment anywhere yet per `CLAUDE.md` §5) —
  /// kept as a distinct value purely for documentation/audit accuracy.
  emulatorBackendReady,

  /// A full, working UI exists, entirely backed by an in-memory
  /// repository/provider — no Cloud Function, no Firestore persistence.
  /// Looks real; isn't. Fails closed in release.
  demoOnly,

  /// No real screen exists at all for this destination — already
  /// self-disclosing (`AdminComingSoonView`), never rendering a working
  /// feature in any build. Still centrally registered (never silently
  /// exempted) so the coverage scan has one invariant to check, not two.
  notImplemented,

  /// The single most dangerous category: a REAL backend exists elsewhere
  /// in this codebase for this exact domain (built in an earlier AP-2
  /// wave), but THIS screen was never wired to it and still reads a
  /// separate, disconnected in-memory model — a staff member has no way
  /// to tell this screen is stale/simulated just by looking at it. Fails
  /// closed in release exactly like [demoOnly]; flagged with its own
  /// value so the gap is never conflated with "nothing was ever built."
  partiallyImplementedUnsafe,
}

enum ModuleImplementationStatus { productionReady, demoOnly }

abstract final class ModuleReadinessRegistry {
  ModuleReadinessRegistry._();

  /// Every real `AdminShellScreen` nav-item id, classified against its own
  /// actual provider chain (see this session's AP-2 closure report for the
  /// full destination-by-destination evidence table). `staff` and
  /// `reservations` are the only two `productionReady` entries — every
  /// other destination fails closed in a release build.
  static const Map<String, ModuleReadinessClassification> _classifications = {
    // Genel Bakış
    'overview': ModuleReadinessClassification.demoOnly,
    // Operasyonlar
    'kitchen': ModuleReadinessClassification.demoOnly,
    'reservations': ModuleReadinessClassification.productionReady,
    'dispatch': ModuleReadinessClassification.demoOnly,
    'orders': ModuleReadinessClassification.notImplemented,
    'pos': ModuleReadinessClassification.notImplemented,
    'cash': ModuleReadinessClassification.notImplemented,
    // Müşteri & Sadakat
    'customer-360': ModuleReadinessClassification.demoOnly,
    'photo-moderation':
        ModuleReadinessClassification.partiallyImplementedUnsafe,
    'customers': ModuleReadinessClassification.demoOnly,
    'loyalty': ModuleReadinessClassification.demoOnly,
    'campaigns': ModuleReadinessClassification.demoOnly,
    'surveys': ModuleReadinessClassification.demoOnly,
    'feedback': ModuleReadinessClassification.demoOnly,
    // Yapılandırma
    'menu': ModuleReadinessClassification.notImplemented,
    'staff': ModuleReadinessClassification.productionReady,
    'branches': ModuleReadinessClassification.demoOnly,
    'devices': ModuleReadinessClassification.partiallyImplementedUnsafe,
    // Akıllı Kurulum & Stok
    'setup-templates': ModuleReadinessClassification.demoOnly,
    'menu-import': ModuleReadinessClassification.demoOnly,
    'ingredient-catalog': ModuleReadinessClassification.demoOnly,
    'inventory': ModuleReadinessClassification.demoOnly,
    'stock-counts': ModuleReadinessClassification.demoOnly,
    'recipes': ModuleReadinessClassification.demoOnly,
    'suppliers': ModuleReadinessClassification.demoOnly,
    // Sistem
    'reports': ModuleReadinessClassification.notImplemented,
    'audit': ModuleReadinessClassification.partiallyImplementedUnsafe,
    'localization': ModuleReadinessClassification.demoOnly,
    'settings': ModuleReadinessClassification.demoOnly,
    'entitlements': ModuleReadinessClassification.partiallyImplementedUnsafe,
    'integrations': ModuleReadinessClassification.demoOnly,
  };

  /// The rich, 5-value classification — for documentation/audit/test use.
  /// An id with no registry entry is itself a finding, not a pass: it
  /// returns [ModuleReadinessClassification.notImplemented], the
  /// strictest available classification, so a newly-added destination
  /// that forgets to register itself fails closed by construction rather
  /// than silently defaulting to visible.
  static ModuleReadinessClassification classificationOf(String moduleId) {
    return _classifications[moduleId] ??
        ModuleReadinessClassification.notImplemented;
  }

  /// The gate's own binary decision, derived from [classificationOf] —
  /// only [ModuleReadinessClassification.productionReady]/
  /// [ModuleReadinessClassification.emulatorBackendReady] ever resolve to
  /// [ModuleImplementationStatus.productionReady]; every other
  /// classification, including an unregistered id, fails closed to
  /// [ModuleImplementationStatus.demoOnly].
  static ModuleImplementationStatus statusOf(String moduleId) {
    switch (classificationOf(moduleId)) {
      case ModuleReadinessClassification.productionReady:
      case ModuleReadinessClassification.emulatorBackendReady:
        return ModuleImplementationStatus.productionReady;
      case ModuleReadinessClassification.demoOnly:
      case ModuleReadinessClassification.notImplemented:
      case ModuleReadinessClassification.partiallyImplementedUnsafe:
        return ModuleImplementationStatus.demoOnly;
    }
  }

  /// Every registered id — used by the coverage-scan test to assert every
  /// real `AdminShellScreen` nav-item id has a registry entry (checked
  /// against the shell's own id list, not the other way around).
  static Set<String> get registeredModuleIds => _classifications.keys.toSet();
}

/// Screen-level fail-closed gate for a non-`productionReady` destination —
/// mirrors `ModuleEntitlementGate`'s exact shape (screen-level, not just a
/// navigation-entry check, so a deep link/direct selection is re-checked
/// every time, never only hidden from the nav list).
///
/// A non-`productionReady` module is blocked outright in a release build —
/// no exception, entitlement or trusted-device state notwithstanding. In a
/// debug/profile build, the module remains reachable but is wrapped in a
/// visible `DEMO` banner — `kReleaseMode` itself is the "explicit
/// environment flag" this gate keys on, mirroring every existing
/// `ProductionUnavailable*` repository's own established gate in this
/// codebase, not a new mechanism.
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
