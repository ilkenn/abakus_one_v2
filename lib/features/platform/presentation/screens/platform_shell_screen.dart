import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/platform_actor_session_provider.dart';
import '../providers/platform_session_controller.dart';
import 'platform_customer_directory_screen.dart';
import 'platform_entitlement_console_screen.dart';
import 'platform_monitoring_screen.dart';
import 'platform_sign_in_screen.dart';
import 'release_readiness_screen.dart';
import 'store_compliance_screen.dart';

/// The Platform Owner Hub shell — Phase 8R (`docs/decisions.md`
/// ADR-025). Reached only via [AppRoutes.platform] (AP-2 final wiring —
/// a real `go_router` route, never linked to from anywhere in the
/// customer or tenant-Admin UI) or [PlatformSignInScreen]'s Development
/// Login — the wholly separate platform-role stack (8A) has no
/// navigation crossover with the tenant hierarchy. A simple tab shell
/// (not `AdminShellScreen`'s responsive sidebar/rail/drawer machinery):
/// Monitoring/Release-Readiness/Store-Compliance remain read-only. AP-2
/// final wiring added the entitlement mutation surface (Abonelikler,
/// `PlatformEntitlementConsoleScreen`); AP-3 continuation adds the global
/// Customer Directory (Müşteriler, `PlatformCustomerDirectoryScreen`) —
/// every registered customer platform-wide, capability-gated restriction,
/// and the audited full-address-book reveal. The tenant-management and
/// integration-catalog CRUD screens `PlatformAuthorizedAction` already
/// anticipates (`manageTenantOrganizations`, `managePlatformAdministrators`,
/// `managePlatformIntegrationCatalog`) remain domain/application-only —
/// reported as a real, deliberate scope boundary, not silently expanded
/// here.
class PlatformShellScreen extends ConsumerStatefulWidget {
  const PlatformShellScreen({super.key});

  @override
  ConsumerState<PlatformShellScreen> createState() =>
      _PlatformShellScreenState();
}

class _PlatformShellScreenState extends ConsumerState<PlatformShellScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    await ref.read(platformSessionControllerProvider).signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PlatformSignInScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(platformActorSessionProvider);
    if (session == null || !session.isValid) {
      return const PlatformSignInScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Platform Merkezi'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          // AP-2 final wiring — a "scoped context handoff," not a
          // duplicate device/approval management surface: no backend
          // capability lets a pure Platform Owner call tenant-scoped
          // `requireStaffPermission`/`requireBranchAccess`-gated commands
          // (device suspend/revoke/retire, approval respond) directly —
          // those callables authorize against real STAFF membership, a
          // wholly separate claim namespace platform membership alone
          // never satisfies (ADR-025). This link only ever leads
          // somewhere useful if the signed-in account *also* happens to
          // hold real staff membership at the tenant being handled —
          // disclosed here rather than building a second, parallel
          // (and backend-unsupported) device/approval UI inside this
          // console.
          IconButton(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: 'Kiracı Admin Paneline Geç (cihaz/onay yönetimi için)',
            onPressed: () => context.go(AppRoutes.admin),
          ),
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: 'Çıkış Yap',
            onPressed: _signOut,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: AppTypography.labelLarge,
          tabs: const [
            Tab(text: 'İzleme'),
            Tab(text: 'Yayın Hazırlığı'),
            Tab(text: 'Mağaza Uyumluluğu'),
            Tab(text: 'Abonelikler'),
            Tab(text: 'Müşteriler'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: const [
            PlatformMonitoringScreen(),
            ReleaseReadinessScreen(),
            StoreComplianceScreen(),
            PlatformEntitlementConsoleScreen(),
            PlatformCustomerDirectoryScreen(),
          ],
        ),
      ),
    );
  }
}
