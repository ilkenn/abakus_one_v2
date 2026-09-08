import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../courier/presentation/screens/courier_dispatch_dashboard_screen.dart';
import '../../../crm/presentation/screens/customer_notification_campaigns_admin_screen.dart';
import '../../../crm/presentation/screens/customer_segmentation_admin_screen.dart';
import '../../../crm/presentation/screens/survey_admin_screen.dart';
import '../../../crm/presentation/screens/visit_reward_rules_admin_screen.dart';
import '../../../entitlements/domain/entitlement_module.dart';
import '../../../entitlements/domain/entitlement_scope_type.dart';
import '../../../entitlements/presentation/screens/entitlement_admin_screen.dart';
import '../../../entitlements/presentation/widgets/module_entitlement_gate.dart';
import '../../../feedback/presentation/screens/feedback_admin_screen.dart';
import '../../../integrations/presentation/screens/tenant_integration_hub_screen.dart';
import '../../../inventory/presentation/screens/ingredient_catalog_screen.dart';
import '../../../inventory/presentation/screens/inventory_screen.dart';
import '../../../inventory/presentation/screens/stock_counts_screen.dart';
import '../../../purchasing/presentation/screens/suppliers_screen.dart';
import '../../../recipes/presentation/screens/recipe_ingredient_links_screen.dart';
import '../../../recipes/presentation/screens/recipes_screen.dart';
import '../../../restaurant_setup/presentation/screens/setup_templates_screen.dart';
import '../../../smart_import/presentation/screens/import_jobs_screen.dart';
import '../../../navigation/presentation/providers/current_branch_provider.dart';
import '../../../pos/domain/authorization/actor_session.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/role_permission_map.dart';
import '../../../pos/domain/authorization/staff_role.dart';
import '../../../pos/presentation/providers/actor_session_provider.dart';
import '../../../pos/presentation/widgets/role_gate.dart';
import '../../../pos/presentation/screens/kitchen_display_board_screen.dart';
import '../../../pos/presentation/screens/pos_branch_overview_screen.dart';
import '../widgets/admin_coming_soon_view.dart';
import '../widgets/admin_context_gate.dart';
import '../widgets/module_readiness_gate.dart';
import '../providers/admin_dependencies_provider.dart';
import '../providers/staff_session_controller.dart';
import 'admin_financial_operations_screen.dart';
import 'admin_overview_screen.dart';
import 'admin_session_expired_screen.dart';
import 'admin_unauthorized_screen.dart';
import 'approval_inbox_screen.dart';
import 'audit_center_screen.dart';
import 'branch_admin_screen.dart';
import 'customer_management_screen.dart';
import 'customer_photo_moderation_screen.dart';
import 'device_registry_screen.dart';
import 'localization_admin_screen.dart';
import 'reservation_operations_screen.dart';
import 'system_health_admin_screen.dart';
import 'staff_management_screen.dart';
import 'staff_sign_in_screen.dart';

class _AdminNavItem {
  const _AdminNavItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.visibleToRoles,
    required this.builder,
  });

  final String id;
  final String label;
  final IconData icon;
  final Set<StaffRole> visibleToRoles;
  final Widget Function(BuildContext context, WidgetRef ref) builder;
}

class _AdminNavGroup {
  const _AdminNavGroup({
    required this.label,
    required this.icon,
    required this.items,
  });

  final String label;
  final IconData icon;
  final List<_AdminNavItem> items;
}

/// The single production Admin Platform control center — Phase 6A
/// (`docs/decisions.md` ADR-023). Responsive: a permanent sidebar on
/// wide screens, a `NavigationRail` for tablet-width groups, and a
/// `Drawer` on phones — the same grouped destination list feeds all
/// three, so there is only one navigation structure to maintain, not
/// three. "Do not put every page directly in one menu" — 18 individual
/// sections are organized under 5 groups.
///
/// Every destination is still individually wrapped in its own
/// `RoleGate` at push time (mirrors `OperationsHubScreen`'s precedent) —
/// this shell's own group-visibility filtering is a UX convenience, not
/// the security boundary.
class AdminShellScreen extends ConsumerStatefulWidget {
  const AdminShellScreen({super.key});

  @override
  ConsumerState<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends ConsumerState<AdminShellScreen> {
  /// Faz R.3A.1 — the reservation module's sidebar visibility must follow
  /// permission resolution, not a separately hand-authored role list: the
  /// two had drifted (a hardcoded `{manager, admin}` silently excluded
  /// `tenantOwner`, even though tenantOwner inherits `manageReservations`
  /// from the manager tier per `RolePermissionMap`). Derived directly from
  /// the exact same source `RoleGate.forAction(manageReservations)` itself
  /// consults below, so role is only ever an *input* to permission
  /// resolution here, never a second, independently-maintained gate.
  static final Set<StaffRole> _reservationsVisibleToRoles = {
    for (final role in StaffRole.values)
      if (RolePermissionMap.permissionsFor(role)
          .contains(PosAuthorizedAction.manageReservations))
        role,
  };

  List<_AdminNavGroup> _groups(String branchId, String actorId) {
    return [
      _AdminNavGroup(
        label: 'Genel Bakış',
        icon: Icons.dashboard_outlined,
        items: [
          _AdminNavItem(
            id: 'overview',
            label: 'Genel Bakış',
            icon: Icons.dashboard_outlined,
            visibleToRoles: const {
              StaffRole.staff,
              StaffRole.manager,
              StaffRole.admin,
              StaffRole.courier,
            },
            builder: (context, ref) => RoleGate.forRoles(
              const {
                StaffRole.staff,
                StaffRole.manager,
                StaffRole.admin,
                StaffRole.courier,
              },
              child: AdminOverviewScreen(branchId: branchId),
            ),
          ),
        ],
      ),
      _AdminNavGroup(
        label: 'Operasyonlar',
        icon: Icons.storefront_outlined,
        items: [
          _AdminNavItem(
            id: 'kitchen',
            label: 'Mutfak / KDS',
            icon: Icons.soup_kitchen_outlined,
            visibleToRoles: const {
              StaffRole.staff,
              StaffRole.manager,
              StaffRole.admin
            },
            builder: (context, ref) => RoleGate.forRoles(
              const {StaffRole.staff, StaffRole.manager, StaffRole.admin},
              child: KitchenDisplayBoardScreen(
                branchId: branchId,
                authorizationPolicy: ref.read(posAuthorizationPolicyProvider),
                performedByStaffId: actorId,
              ),
            ),
          ),
          _AdminNavItem(
            id: 'reservations',
            label: 'Rezervasyonlar',
            icon: Icons.event_seat_outlined,
            visibleToRoles: _reservationsVisibleToRoles,
            builder: (context, ref) => ModuleEntitlementGate(
              module: EntitlementModule.reservations,
              scopeType: EntitlementScopeType.branch,
              scopeId: branchId,
              actorStaffId: actorId,
              child: RoleGate.forAction(
                PosAuthorizedAction.manageReservations,
                child: const ReservationOperationsScreen(),
              ),
            ),
          ),
          _AdminNavItem(
            id: 'dispatch',
            label: 'Kurye / Sevkiyat',
            icon: Icons.local_shipping_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => RoleGate.forRoles(
              const {StaffRole.manager, StaffRole.admin},
              child: CourierDispatchDashboardScreen(
                branchId: branchId,
                authorizationPolicy: ref.read(posAuthorizationPolicyProvider),
                performedByStaffId: actorId,
              ),
            ),
          ),
          _AdminNavItem(
            id: 'orders',
            label: 'Siparişler',
            icon: Icons.receipt_long_outlined,
            visibleToRoles: const {
              StaffRole.staff,
              StaffRole.manager,
              StaffRole.admin
            },
            builder: (context, ref) => RoleGate.forRoles(
              const {StaffRole.staff, StaffRole.manager, StaffRole.admin},
              child: const AdminComingSoonView(
                title: 'Siparişler',
                reason: 'Genel bir sipariş yönetimi ekranı henüz yok — sipariş '
                    'işlemleri POS/KDS akışları üzerinden yürütülüyor.',
              ),
            ),
          ),
          _AdminNavItem(
            id: 'pos',
            label: 'POS',
            icon: Icons.point_of_sale_outlined,
            visibleToRoles: const {
              StaffRole.staff,
              StaffRole.manager,
              StaffRole.admin
            },
            builder: (context, ref) => RoleGate.forRoles(
              const {StaffRole.staff, StaffRole.manager, StaffRole.admin},
              child: const PosBranchOverviewScreen(),
            ),
          ),
          _AdminNavItem(
            id: 'cash',
            label: 'Finansal İşlemler',
            icon: Icons.point_of_sale,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => RoleGate.forAction(
              PosAuthorizedAction.viewFinancialOperations,
              child: const AdminFinancialOperationsScreen(),
            ),
          ),
        ],
      ),
      _AdminNavGroup(
        label: 'Müşteri & Sadakat',
        icon: Icons.groups_outlined,
        items: [
          _AdminNavItem(
            id: 'customer-360',
            label: 'Müşteri 360',
            icon: Icons.badge_outlined,
            visibleToRoles: const {
              StaffRole.staff,
              StaffRole.manager,
              StaffRole.admin
            },
            builder: (context, ref) => RoleGate.forAction(
              PosAuthorizedAction.viewCustomerAdmin,
              child: const CustomerManagementScreen(),
            ),
          ),
          _AdminNavItem(
            id: 'photo-moderation',
            label: 'Fotoğraf Denetimi',
            icon: Icons.image_search_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => RoleGate.forAction(
              PosAuthorizedAction.moderateCustomerPhoto,
              child: CustomerPhotoModerationScreen(
                authorizationPolicy: ref.read(posAuthorizationPolicyProvider),
                performedByStaffId: actorId,
              ),
            ),
          ),
          _AdminNavItem(
            id: 'customers',
            label: 'Segmentasyon',
            icon: Icons.people_outline,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => RoleGate.forRoles(
              const {StaffRole.manager, StaffRole.admin},
              child: const CustomerSegmentationAdminScreen(),
            ),
          ),
          _AdminNavItem(
            id: 'loyalty',
            label: 'Sadakat',
            icon: Icons.card_giftcard_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => RoleGate.forAction(
              PosAuthorizedAction.manageVisitRewardRules,
              child: VisitRewardRulesAdminScreen(
                authorizationPolicy: ref.read(posAuthorizationPolicyProvider),
                performedByStaffId: actorId,
              ),
            ),
          ),
          _AdminNavItem(
            id: 'campaigns',
            label: 'Kampanyalar',
            icon: Icons.campaign_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => RoleGate.forAction(
              PosAuthorizedAction.manageCustomerNotificationCampaigns,
              child: CustomerNotificationCampaignsAdminScreen(
                authorizationPolicy: ref.read(posAuthorizationPolicyProvider),
                performedByStaffId: actorId,
              ),
            ),
          ),
          _AdminNavItem(
            id: 'surveys',
            label: 'Anketler',
            icon: Icons.poll_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => RoleGate.forAction(
              PosAuthorizedAction.manageSurveys,
              child: SurveyAdminScreen(
                authorizationPolicy: ref.read(posAuthorizationPolicyProvider),
                performedByStaffId: actorId,
              ),
            ),
          ),
          _AdminNavItem(
            id: 'feedback',
            label: 'Geri Bildirim',
            icon: Icons.feedback_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => RoleGate.forAction(
              PosAuthorizedAction.manageCustomerFeedback,
              child: FeedbackAdminScreen(
                branchId: branchId,
                authorizationPolicy: ref.read(posAuthorizationPolicyProvider),
                performedByStaffId: actorId,
              ),
            ),
          ),
        ],
      ),
      _AdminNavGroup(
        label: 'Yapılandırma',
        icon: Icons.settings_outlined,
        items: [
          _AdminNavItem(
            id: 'menu',
            label: 'Menü',
            icon: Icons.restaurant_menu_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => RoleGate.forRoles(
              const {StaffRole.manager, StaffRole.admin},
              child: const AdminComingSoonView(
                title: 'Menü',
                reason: 'Menü/kategori/ürün/modifiye yönetimi için ayrı bir '
                    'admin ekranı henüz yok.',
              ),
            ),
          ),
          _AdminNavItem(
            id: 'staff',
            label: 'Personel',
            icon: Icons.badge_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => RoleGate.forAction(
              PosAuthorizedAction.viewStaffAudit,
              child: StaffManagementScreen(
                authorizationPolicy: ref.read(posAuthorizationPolicyProvider),
                performedByStaffId: actorId,
              ),
            ),
          ),
          _AdminNavItem(
            id: 'branches',
            label: 'Şubeler',
            icon: Icons.storefront_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => RoleGate.forAction(
              PosAuthorizedAction.manageBranch,
              child: BranchAdminScreen(
                authorizationPolicy: ref.read(posAuthorizationPolicyProvider),
                performedByStaffId: actorId,
              ),
            ),
          ),
          _AdminNavItem(
            id: 'devices',
            label: 'Cihazlar',
            icon: Icons.devices_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => RoleGate.forAction(
              PosAuthorizedAction.manageDeviceRegistry,
              child: DeviceRegistryScreen(
                branchId: branchId,
                authorizationPolicy: ref.read(posAuthorizationPolicyProvider),
                performedByStaffId: actorId,
              ),
            ),
          ),
        ],
      ),
      _AdminNavGroup(
        label: 'Akıllı Kurulum & Stok',
        icon: Icons.auto_awesome_outlined,
        items: [
          _AdminNavItem(
            id: 'setup-templates',
            label: 'Kurulum Şablonları',
            icon: Icons.dashboard_customize_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => ModuleEntitlementGate(
              module: EntitlementModule.smartRestaurantSetup,
              scopeType: EntitlementScopeType.branch,
              scopeId: branchId,
              actorStaffId: actorId,
              child: SetupTemplatesScreen(
                organizationId: 'org-1',
                restaurantId: 'restaurant-1',
                branchId: branchId,
                authorizationPolicy: ref.read(posAuthorizationPolicyProvider),
                performedByStaffId: actorId,
              ),
            ),
          ),
          _AdminNavItem(
            id: 'menu-import',
            label: 'Menü İçe Aktarma',
            icon: Icons.file_upload_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => ModuleEntitlementGate(
              module: EntitlementModule.menuImport,
              scopeType: EntitlementScopeType.branch,
              scopeId: branchId,
              actorStaffId: actorId,
              child: ImportJobsScreen(
                // Single-tenant seed today (Phase 6D) — no multi-org
                // switching exists yet to resolve these dynamically.
                organizationId: 'org-1',
                restaurantId: 'restaurant-1',
                branchId: branchId,
                performedByStaffId: actorId,
              ),
            ),
          ),
          _AdminNavItem(
            id: 'ingredient-catalog',
            label: 'Malzeme Kataloğu',
            icon: Icons.egg_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => ModuleEntitlementGate(
              module: EntitlementModule.inventory,
              scopeType: EntitlementScopeType.branch,
              scopeId: branchId,
              actorStaffId: actorId,
              child: IngredientCatalogScreen(
                organizationId: 'org-1',
                authorizationPolicy: ref.read(posAuthorizationPolicyProvider),
                performedByStaffId: actorId,
              ),
            ),
          ),
          _AdminNavItem(
            id: 'inventory',
            label: 'Envanter',
            icon: Icons.inventory_2_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => ModuleEntitlementGate(
              module: EntitlementModule.inventory,
              scopeType: EntitlementScopeType.branch,
              scopeId: branchId,
              actorStaffId: actorId,
              child: InventoryScreen(
                organizationId: 'org-1',
                branchId: branchId,
              ),
            ),
          ),
          _AdminNavItem(
            id: 'stock-counts',
            label: 'Stok Sayımları',
            icon: Icons.fact_check_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => ModuleEntitlementGate(
              module: EntitlementModule.inventory,
              scopeType: EntitlementScopeType.branch,
              scopeId: branchId,
              actorStaffId: actorId,
              child: StockCountsScreen(
                branchId: branchId,
                authorizationPolicy: ref.read(posAuthorizationPolicyProvider),
                performedByStaffId: actorId,
              ),
            ),
          ),
          _AdminNavItem(
            id: 'recipes',
            label: 'Tarifler',
            icon: Icons.menu_book_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => ModuleEntitlementGate(
              module: EntitlementModule.recipes,
              scopeType: EntitlementScopeType.branch,
              scopeId: branchId,
              actorStaffId: actorId,
              child: RecipesScreen(
                organizationId: 'org-1',
                authorizationPolicy: ref.read(posAuthorizationPolicyProvider),
                performedByStaffId: actorId,
              ),
            ),
          ),
          _AdminNavItem(
            id: 'recipe-ingredient-links',
            label: 'Reçete-Malzeme Bağlantıları',
            icon: Icons.link,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => ModuleEntitlementGate(
              module: EntitlementModule.recipes,
              scopeType: EntitlementScopeType.branch,
              scopeId: branchId,
              actorStaffId: actorId,
              child: const RecipeIngredientLinksScreen(
                organizationId: 'org-1',
              ),
            ),
          ),
          _AdminNavItem(
            id: 'suppliers',
            label: 'Tedarikçiler',
            icon: Icons.local_shipping_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => ModuleEntitlementGate(
              module: EntitlementModule.suppliers,
              scopeType: EntitlementScopeType.branch,
              scopeId: branchId,
              actorStaffId: actorId,
              child: SuppliersScreen(
                organizationId: 'org-1',
                authorizationPolicy: ref.read(posAuthorizationPolicyProvider),
                performedByStaffId: actorId,
              ),
            ),
          ),
        ],
      ),
      _AdminNavGroup(
        label: 'Sistem',
        icon: Icons.admin_panel_settings_outlined,
        items: [
          _AdminNavItem(
            id: 'reports',
            label: 'Raporlar',
            icon: Icons.bar_chart_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => RoleGate.forRoles(
              const {StaffRole.manager, StaffRole.admin},
              child: const AdminComingSoonView(
                title: 'Raporlar',
                reason: 'Genel raporlama ekranı henüz yok — kurye performans/'
                    'işlem özeti gibi modül içi raporlar kendi ekranlarında '
                    'mevcut.',
              ),
            ),
          ),
          _AdminNavItem(
            id: 'audit',
            label: 'Denetim',
            icon: Icons.fact_check_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => RoleGate.forAction(
              PosAuthorizedAction.viewAuditCenter,
              child: AuditCenterScreen(branchId: branchId),
            ),
          ),
          _AdminNavItem(
            id: 'localization',
            label: 'Yerelleştirme',
            icon: Icons.translate_outlined,
            visibleToRoles: const {StaffRole.admin},
            builder: (context, ref) => RoleGate.forAction(
              PosAuthorizedAction.manageLocalizationConfig,
              child: LocalizationAdminScreen(
                branchId: branchId,
                authorizationPolicy: ref.read(posAuthorizationPolicyProvider),
                performedByStaffId: actorId,
              ),
            ),
          ),
          _AdminNavItem(
            id: 'settings',
            label: 'Ayarlar',
            icon: Icons.tune_outlined,
            visibleToRoles: const {StaffRole.manager, StaffRole.admin},
            builder: (context, ref) => RoleGate.forAction(
              PosAuthorizedAction.viewFeatureFlags,
              child: SystemHealthAdminScreen(
                authorizationPolicy: ref.read(posAuthorizationPolicyProvider),
                performedByStaffId: actorId,
              ),
            ),
          ),
          _AdminNavItem(
            id: 'entitlements',
            label: 'Abonelikler',
            icon: Icons.workspace_premium_outlined,
            visibleToRoles: const {StaffRole.admin},
            builder: (context, ref) => RoleGate.forAction(
              PosAuthorizedAction.manageEntitlements,
              child: EntitlementAdminScreen(
                branchId: branchId,
                authorizationPolicy: ref.read(posAuthorizationPolicyProvider),
                performedByStaffId: actorId,
              ),
            ),
          ),
          _AdminNavItem(
            id: 'integrations',
            label: 'Entegrasyonlar',
            icon: Icons.hub_outlined,
            visibleToRoles: const {StaffRole.tenantOwner},
            builder: (context, ref) => RoleGate.forAction(
              PosAuthorizedAction.manageTenantIntegrations,
              child: TenantIntegrationHubScreen(
                organizationId: ref.read(currentOrganizationIdProvider),
                authorizationPolicy: ref.read(posAuthorizationPolicyProvider),
                performedByStaffId: actorId,
              ),
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(actorSessionProvider);
    if (session == null) {
      return AdminUnauthorizedScreen(
        onSignIn: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const StaffSignInScreen()),
        ),
      );
    }
    if (!session.isValid) {
      return AdminSessionExpiredScreen(
        onSignInAgain: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const StaffSignInScreen()),
        ),
      );
    }

    // AP-2 closure correction — the real multi-org/multi-branch context
    // gate. Runs AFTER the staff-session check above (a session, even a
    // valid one, says nothing about WHICH organization/branch it should
    // operate against) and BEFORE any destination content ever renders —
    // see `AdminContextGate`'s own doc comment for the full revoked-
    // access/auto-select/explicit-picker behavior.
    return AdminContextGate(
      child: Builder(
        builder: (context) {
          final branchId = ref.watch(currentBranchIdProvider);
          final groups = _groups(branchId, session.actorId)
              .map((g) => _AdminNavGroup(
                    label: g.label,
                    icon: g.icon,
                    items: g.items
                        .where((item) =>
                            session.roles.any(item.visibleToRoles.contains))
                        .toList(),
                  ))
              .where((g) => g.items.isNotEmpty)
              .toList();

          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              if (width >= 1000) {
                return _DesktopShell(
                    groups: groups, session: session, ref: ref);
              }
              if (width >= 600) {
                return _TabletShell(groups: groups, session: session, ref: ref);
              }
              return _MobileShell(groups: groups, session: session, ref: ref);
            },
          );
        },
      ),
    );
  }
}

class _TopBar extends ConsumerWidget implements PreferredSizeWidget {
  const _TopBar({
    required this.title,
    required this.actorId,
    this.leading,
  });

  final String title;
  final String actorId;
  final Widget? leading;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final organizationId = ref.watch(currentOrganizationIdProvider);
    final branchId = ref.watch(currentBranchIdProvider);
    // Mobile-width AppBars have no room for both the full context label
    // and the decorative notification/search icons (neither has an
    // `onTap` — they are unwired placeholders) — on narrow screens the
    // real, functional context switcher wins the space; the placeholders
    // are hidden entirely rather than truncated illegibly.
    final isNarrow = MediaQuery.sizeOf(context).width < 600;

    return AppBar(
      leading: leading,
      title: Text(title),
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      actions: [
        // AP-2 closure correction — explicit, on-demand organization/
        // branch switching (not only the automatic revoked-access
        // detection `AdminContextGate` performs). Semantics/tooltip make
        // this keyboard/screen-reader reachable, not only a bare icon tap.
        Tooltip(
          message: 'İşletme/şube değiştir',
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.small),
            onTap: () => showAdminContextSwitcherSheet(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storefront_outlined,
                      size: 18, color: AppColors.textSecondary),
                  if (!isNarrow) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Text('$organizationId · $branchId',
                        style: AppTypography.bodySmall),
                  ],
                  const Icon(Icons.expand_more_rounded,
                      size: 18, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        // AP-2 final wiring — the Approval Inbox is real and backend-wired
        // this pass; unlike the still-decorative search icon (hidden on
        // narrow screens, no `onTap`), this stays visible and tappable at
        // every width — it is a genuine, functional destination, not a
        // placeholder.
        IconButton(
          icon: const Icon(Icons.notifications_none_outlined,
              color: AppColors.textSecondary),
          tooltip: 'Onay Kutusu',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ApprovalInboxScreen()),
          ),
        ),
        if (!isNarrow) ...[
          const Icon(Icons.search_outlined, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.md),
        ],
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.lg),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.primary,
                child:
                    Icon(Icons.person_outline, size: 16, color: Colors.white),
              ),
              if (!isNarrow) ...[
                const SizedBox(width: AppSpacing.xs),
                Text(actorId, style: AppTypography.bodySmall),
              ],
            ],
          ),
        ),
        IconButton(
          icon:
              const Icon(Icons.logout_outlined, color: AppColors.textSecondary),
          tooltip: 'Çıkış Yap',
          onPressed: () => ref.read(staffSessionControllerProvider).signOut(),
        ),
      ],
    );
  }
}

/// Shared, breakpoint-agnostic content pane: renders [selectedId]'s
/// destination, or an empty state when nothing is selected yet.
///
/// AP-2 closure correction — every destination is wrapped in
/// [ModuleReadinessGate] HERE, centrally, keyed by the destination's own
/// `item.id` (the exact `_AdminNavItem(id: '...')` literal each group
/// declares — never a second, parallel naming scheme). This is the single
/// enforcement point for every possible way a destination's content could
/// ever render (nav click, initial-selection, or any future deep-link/
/// state-restoration path this shell adds) — nav-item hiding
/// (`session.roles.any(item.visibleToRoles.contains)` in `build()` above)
/// is a UX convenience only, never the sole gate, exactly like `RoleGate`'s
/// own "individually wrapped at push time" precedent this file's own class
/// doc comment already documents one layer up.
class _ContentPane extends StatelessWidget {
  const _ContentPane({
    required this.groups,
    required this.selectedId,
    required this.ref,
  });

  final List<_AdminNavGroup> groups;
  final String? selectedId;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    if (selectedId == null) {
      return const Center(
        child: Text('Bir bölüm seçin', style: AppTypography.bodyMedium),
      );
    }
    for (final group in groups) {
      for (final item in group.items) {
        if (item.id == selectedId) {
          return ModuleReadinessGate(
            moduleId: item.id,
            child: Builder(builder: (context) => item.builder(context, ref)),
          );
        }
      }
    }
    return const Center(child: Text('Bölüm bulunamadı'));
  }
}

class _DesktopShell extends StatefulWidget {
  const _DesktopShell({
    required this.groups,
    required this.session,
    required this.ref,
  });

  final List<_AdminNavGroup> groups;
  final ActorSession session;
  final WidgetRef ref;

  @override
  State<_DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<_DesktopShell> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    if (widget.groups.isNotEmpty && widget.groups.first.items.isNotEmpty) {
      _selected = widget.groups.first.items.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          _TopBar(title: 'Yönetici Paneli', actorId: widget.session.actorId),
      body: Row(
        children: [
          SizedBox(
            width: 280,
            child: Material(
              color: AppColors.surface,
              child: ListView(
                children: [
                  for (final group in widget.groups)
                    ExpansionTile(
                      leading: Icon(group.icon),
                      title: Text(group.label, style: AppTypography.labelLarge),
                      initiallyExpanded: true,
                      children: [
                        for (final item in group.items)
                          ListTile(
                            contentPadding:
                                const EdgeInsets.only(left: AppSpacing.xl),
                            leading: Icon(item.icon, size: 20),
                            title: Text(item.label),
                            selected: item.id == _selected,
                            selectedTileColor:
                                AppColors.primary.withValues(alpha: 0.08),
                            onTap: () => setState(() => _selected = item.id),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _ContentPane(
              groups: widget.groups,
              selectedId: _selected,
              ref: widget.ref,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabletShell extends StatefulWidget {
  const _TabletShell({
    required this.groups,
    required this.session,
    required this.ref,
  });

  final List<_AdminNavGroup> groups;
  final ActorSession session;
  final WidgetRef ref;

  @override
  State<_TabletShell> createState() => _TabletShellState();
}

class _TabletShellState extends State<_TabletShell> {
  int _groupIndex = 0;
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final groups = widget.groups;
    final activeGroup = groups.isEmpty ? null : groups[_groupIndex];
    return Scaffold(
      appBar:
          _TopBar(title: 'Yönetici Paneli', actorId: widget.session.actorId),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _groupIndex,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (index) {
              setState(() {
                _groupIndex = index;
                _selected = null;
              });
            },
            destinations: [
              for (final group in groups)
                NavigationRailDestination(
                  icon: Icon(group.icon),
                  label: Text(group.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          if (activeGroup != null)
            SizedBox(
              width: 220,
              child: ListView(
                children: [
                  for (final item in activeGroup.items)
                    ListTile(
                      leading: Icon(item.icon, size: 20),
                      title: Text(item.label),
                      selected: item.id == _selected,
                      onTap: () => setState(() => _selected = item.id),
                    ),
                ],
              ),
            ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _ContentPane(
              groups: groups,
              selectedId: _selected,
              ref: widget.ref,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileShell extends StatefulWidget {
  const _MobileShell({
    required this.groups,
    required this.session,
    required this.ref,
  });

  final List<_AdminNavGroup> groups;
  final ActorSession session;
  final WidgetRef ref;

  @override
  State<_MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<_MobileShell> {
  String? _selected;
  String _selectedLabel = 'Yönetici Paneli';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _TopBar(
        title: _selectedLabel,
        actorId: widget.session.actorId,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              for (final group in widget.groups)
                ExpansionTile(
                  leading: Icon(group.icon),
                  title: Text(group.label, style: AppTypography.labelLarge),
                  children: [
                    for (final item in group.items)
                      ListTile(
                        contentPadding:
                            const EdgeInsets.only(left: AppSpacing.xl),
                        leading: Icon(item.icon, size: 20),
                        title: Text(item.label),
                        onTap: () {
                          setState(() {
                            _selected = item.id;
                            _selectedLabel = item.label;
                          });
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
      body: _ContentPane(
        groups: widget.groups,
        selectedId: _selected,
        ref: widget.ref,
      ),
    );
  }
}
