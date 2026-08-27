import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// AP-2 final wiring — the two-axis implementation-readiness model
/// (`docs/decisions.md`'s AP-2 final-wiring entry). The prior single-axis
/// `productionReady` label conflated two genuinely different questions —
/// "is the code for this screen actually real and wired?" and "has this
/// been deployed to a real production Firebase project?" — and a staff
/// member reading "productionReady" could reasonably assume the latter,
/// which was never true (`CLAUDE.md` §5: no real Firebase project has ever
/// been deployed to). This axis answers ONLY the first question — source-
/// verified against each screen's own provider chain, never inferred from
/// a sibling screen or feature name. [ModuleDeploymentAvailability] below
/// answers the second, separately.
enum ModuleImplementationMaturity {
  /// No real screen exists at all for this destination — already
  /// self-disclosing (`AdminComingSoonView`), never rendering a working
  /// feature in any build. Still centrally registered (never silently
  /// exempted) so the coverage scan has one invariant to check, not two.
  notImplemented,

  /// A full, working UI exists, entirely backed by an in-memory
  /// repository/provider — no Cloud Function, no Firestore persistence.
  /// Looks real; isn't. Fails closed in release.
  demoOnly,

  /// The single most dangerous category: a REAL backend exists elsewhere
  /// in this codebase for this exact domain, but THIS screen was never
  /// wired to it and still reads a separate, disconnected in-memory
  /// model — a staff member has no way to tell this screen is
  /// stale/simulated just by looking at it. Fails closed in release
  /// exactly like [demoOnly]; flagged with its own value so the gap is
  /// never conflated with "nothing was ever built."
  partiallyImplementedUnsafe,

  /// The screen is genuinely wired end-to-end (UI -> application/use case
  /// -> real gateway/repository -> callable/read model -> server
  /// authorization -> transaction/audit) and this exact path is proven by
  /// a passing emulator-backed test suite — but has not yet accumulated
  /// the full operational polish (every edge case, every long-tail state)
  /// [implementationComplete] implies. Never inflated to that tier just to
  /// make a report look further along than the evidence supports.
  backendWiredEmulatorVerified,

  /// Genuinely finished: real backend, real wiring, full state coverage
  /// (loading/error/empty/retry, unauthorized, edge cases), and a mature
  /// test suite. This does NOT mean deployed to production — see
  /// [ModuleDeploymentAvailability] for that separate question.
  implementationComplete,
}

/// The second, independent axis — never conflated with [ModuleImplementationMaturity].
/// A module can be [ModuleImplementationMaturity.implementationComplete] and
/// still [disabled] here (nothing has been deployed to a real Firebase
/// project anywhere in this app yet, pre-AP-8) — that combination is the
/// honest default for EVERY destination today, not a contradiction.
enum ModuleDeploymentAvailability {
  /// No real deployment target is even configured for this destination yet.
  disabled,

  /// Real backend code exists and runs against the Firebase Local
  /// Emulator Suite / a `*-dev` project — never a production project.
  development,

  /// Reserved for a future phase — not used by any destination today.
  staging,

  /// Reserved for AP-8 (Production Hardening) — not used by any
  /// destination today. `CLAUDE.md` §5: no real Firebase project has ever
  /// been deployed to in this app's history.
  production,
}

enum ModuleImplementationStatus { productionReady, demoOnly }

/// One destination's full two-axis classification.
class ModuleReadiness {
  const ModuleReadiness(this.maturity, this.deployment);

  final ModuleImplementationMaturity maturity;
  final ModuleDeploymentAvailability deployment;

  /// The gate's own binary release decision. A module only ever renders
  /// unconditionally (no gate, no badge) when BOTH axes clear the bar:
  /// maturity is at least [ModuleImplementationMaturity.backendWiredEmulatorVerified]
  /// AND deployment is [ModuleDeploymentAvailability.production]. Since no
  /// destination is ever [ModuleDeploymentAvailability.production] before
  /// AP-8, this resolves to [ModuleImplementationStatus.demoOnly] for
  /// every destination today regardless of maturity — entitlement,
  /// Platform Owner status, or trusted-device state can never substitute
  /// for either axis clearing on their own (no bypass exists in this
  /// class or its caller).
  ModuleImplementationStatus get status {
    final maturityClears =
        maturity == ModuleImplementationMaturity.backendWiredEmulatorVerified ||
            maturity == ModuleImplementationMaturity.implementationComplete;
    final deploymentClears =
        deployment == ModuleDeploymentAvailability.production;
    return (maturityClears && deploymentClears)
        ? ModuleImplementationStatus.productionReady
        : ModuleImplementationStatus.demoOnly;
  }

  /// The dev/profile-build signal (whether [ModuleReadinessGate] overlays
  /// a `DEMO` badge) is driven by MATURITY alone — deployment availability
  /// is irrelevant to a developer/tester working entirely against the
  /// Local Emulator Suite, where "is this real code" is the only question
  /// that matters. A [status] of [ModuleImplementationStatus.demoOnly]
  /// (always true pre-AP-8) does not by itself mean the dev-mode badge
  /// shows — [ModuleReadinessGate] checks this separately.
  bool get isMatureEnoughForDevBuild =>
      maturity == ModuleImplementationMaturity.backendWiredEmulatorVerified ||
      maturity == ModuleImplementationMaturity.implementationComplete;
}

abstract final class ModuleReadinessRegistry {
  ModuleReadinessRegistry._();

  /// Every real `AdminShellScreen` nav-item id, classified against its own
  /// actual provider chain (see `docs/decisions.md`'s AP-2 entries for the
  /// full destination-by-destination evidence table). `staff` and
  /// `reservations` are the only two [ModuleImplementationMaturity.implementationComplete]
  /// entries; `devices`/`entitlements` reached
  /// [ModuleImplementationMaturity.backendWiredEmulatorVerified] in the
  /// AP-2 final-wiring pass. Every destination's deployment availability
  /// is [ModuleDeploymentAvailability.disabled] (not implemented at all)
  /// or [ModuleDeploymentAvailability.development] (real code, emulator/dev
  /// project only) — never [ModuleDeploymentAvailability.production],
  /// matching this app's real deployment history (`CLAUDE.md` §5).
  static const Map<String, ModuleReadiness> _classifications = {
    // Genel Bakış
    'overview': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
    // Operasyonlar
    'kitchen': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
    'reservations': ModuleReadiness(
        ModuleImplementationMaturity.implementationComplete,
        ModuleDeploymentAvailability.development),
    'dispatch': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
    'orders': ModuleReadiness(ModuleImplementationMaturity.notImplemented,
        ModuleDeploymentAvailability.disabled),
    'pos': ModuleReadiness(ModuleImplementationMaturity.notImplemented,
        ModuleDeploymentAvailability.disabled),
    'cash': ModuleReadiness(ModuleImplementationMaturity.notImplemented,
        ModuleDeploymentAvailability.disabled),
    // Müşteri & Sadakat
    'customer-360': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
    // photo-moderation: a real moderateCustomerPhoto Cloud Function exists
    // (AP-2), but this screen is not wired to it — AP-3+ scope, disclosed,
    // not silently left ambiguous. Stays partiallyImplementedUnsafe.
    'photo-moderation': ModuleReadiness(
        ModuleImplementationMaturity.partiallyImplementedUnsafe,
        ModuleDeploymentAvailability.development),
    'customers': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
    'loyalty': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
    'campaigns': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
    'surveys': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
    'feedback': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
    // Yapılandırma
    'menu': ModuleReadiness(ModuleImplementationMaturity.notImplemented,
        ModuleDeploymentAvailability.disabled),
    'staff': ModuleReadiness(
        ModuleImplementationMaturity.implementationComplete,
        ModuleDeploymentAvailability.development),
    'branches': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
    // AP-2 final wiring — the trusted-device tab is now genuinely wired
    // (requestDeviceRegistration/suspend/revoke/retire + the Approval
    // Inbox for activation); the pre-existing device-inventory tab
    // (POS/printer/payment terminal registry, Phase 6L/ADR-023) remains
    // in-memory-only and out of AP-2's scope. The destination stays
    // backendWiredEmulatorVerified, not implementationComplete, precisely
    // because that second tab is still fake — see
    // `device_registry_screen.dart`'s own in-UI disclosure of which tab is
    // which.
    'devices': ModuleReadiness(
        ModuleImplementationMaturity.backendWiredEmulatorVerified,
        ModuleDeploymentAvailability.development),
    // Akıllı Kurulum & Stok
    'setup-templates': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
    'menu-import': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
    'ingredient-catalog': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
    'inventory': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
    'stock-counts': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
    'recipes': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
    'suppliers': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
    // Sistem
    'reports': ModuleReadiness(ModuleImplementationMaturity.notImplemented,
        ModuleDeploymentAvailability.disabled),
    // audit: a real, durable auditEvents writer exists and is used by
    // every AP-2 Cloud Function (never removed/replaced) — but this
    // VIEWER screen still reads an in-memory projection. AP-3+ scope,
    // disclosed. Stays partiallyImplementedUnsafe.
    'audit': ModuleReadiness(
        ModuleImplementationMaturity.partiallyImplementedUnsafe,
        ModuleDeploymentAvailability.development),
    'localization': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
    'settings': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
    // AP-2 final wiring — grant/renew/suspend/revoke moved to the
    // Platform Owner console (real Platform-Owner-only Cloud Functions);
    // this Tenant-Admin-facing screen is now a genuine, real-time,
    // read-only viewer of the same `entitlements` Firestore documents —
    // no mutation control remains here for a Tenant Admin, matching the
    // real backend's own `requirePlatformMember` authorization exactly.
    'entitlements': ModuleReadiness(
        ModuleImplementationMaturity.backendWiredEmulatorVerified,
        ModuleDeploymentAvailability.development),
    'integrations': ModuleReadiness(ModuleImplementationMaturity.demoOnly,
        ModuleDeploymentAvailability.development),
  };

  /// The rich, two-axis classification — for documentation/audit/test use.
  /// An id with no registry entry is itself a finding, not a pass: it
  /// returns the strictest available classification (`notImplemented` +
  /// `disabled`), so a newly-added destination that forgets to register
  /// itself fails closed by construction rather than silently defaulting
  /// to visible.
  static ModuleReadiness readinessOf(String moduleId) {
    return _classifications[moduleId] ??
        const ModuleReadiness(ModuleImplementationMaturity.notImplemented,
            ModuleDeploymentAvailability.disabled);
  }

  /// The gate's own binary decision — see [ModuleReadiness.status].
  static ModuleImplementationStatus statusOf(String moduleId) {
    return readinessOf(moduleId).status;
  }

  /// Every registered id — used by the coverage-scan test to assert every
  /// real `AdminShellScreen` nav-item id has a registry entry (checked
  /// against the shell's own id list, not the other way around).
  static Set<String> get registeredModuleIds => _classifications.keys.toSet();
}

/// Screen-level fail-closed gate for a non-release-clear destination —
/// mirrors `ModuleEntitlementGate`'s exact shape (screen-level, not just a
/// navigation-entry check, so a deep link/direct selection is re-checked
/// every time, never only hidden from the nav list).
///
/// A destination whose [ModuleReadiness.status] is not
/// [ModuleImplementationStatus.productionReady] is blocked outright in a
/// release build — no exception, entitlement or trusted-device state
/// notwithstanding. Since no destination is ever
/// [ModuleDeploymentAvailability.production] before AP-8 (`CLAUDE.md` §5),
/// this means every destination is hard-blocked in every release build
/// today, unconditionally — `kReleaseMode` itself is the "explicit
/// environment flag" this gate keys on, mirroring every existing
/// `ProductionUnavailable*` repository's own established gate in this
/// codebase, not a new mechanism. In a debug/profile build, a module whose
/// maturity clears [ModuleReadiness.isMatureEnoughForDevBuild] renders
/// directly (no badge — it is genuinely real, proven against the Local
/// Emulator Suite); everything else remains reachable but wrapped in a
/// visible `DEMO` banner.
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
    final readiness = ModuleReadinessRegistry.readinessOf(moduleId);
    if (kReleaseMode) {
      if (readiness.status == ModuleImplementationStatus.productionReady) {
        return child;
      }
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
    if (readiness.isMatureEnoughForDevBuild) {
      return child;
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
