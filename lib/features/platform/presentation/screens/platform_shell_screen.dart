import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/platform_actor_session_provider.dart';
import '../providers/platform_session_controller.dart';
import 'platform_monitoring_screen.dart';
import 'platform_sign_in_screen.dart';
import 'release_readiness_screen.dart';
import 'store_compliance_screen.dart';

/// The Platform Owner Hub shell — Phase 8R (`docs/decisions.md`
/// ADR-025). Reached only via [PlatformSignInScreen]'s Development
/// Login, never from the tenant-side `AdminShellScreen` — the wholly
/// separate platform-role stack (8A) has no navigation crossover with
/// the tenant hierarchy. Deliberately a simple 3-tab shell (not
/// `AdminShellScreen`'s responsive sidebar/rail/drawer machinery) —
/// only 3 read-only destinations exist so far
/// (Monitoring/Release-Readiness/Store-Compliance); the tenant
/// -management, entitlement-catalog, and integration-catalog CRUD
/// screens `PlatformAuthorizedAction` already anticipates
/// (`manageTenantOrganizations`, `managePlatformAdministrators`,
/// `manageGlobalEntitlementCatalog`, `managePlatformIntegrationCatalog`)
/// remain domain/application-only this phase — reported as a real,
/// deliberate scope boundary, not silently expanded here.
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
    _tabController = TabController(length: 3, vsync: this);
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
          ],
        ),
      ),
    );
  }
}
