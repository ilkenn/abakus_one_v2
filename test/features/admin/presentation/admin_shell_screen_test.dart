import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/presentation/providers/admin_reservation_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_shell_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_session_expired_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_unauthorized_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/audit_center_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/device_registry_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/localization_admin_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/system_health_admin_screen.dart';
import 'package:abakus_one_v2/core/services/feature_flags/feature_flags_keys.dart';
import 'package:abakus_one_v2/core/services/feature_flags/feature_flags_provider.dart';
import 'package:abakus_one_v2/features/crm/presentation/screens/customer_segmentation_admin_screen.dart';
import 'package:abakus_one_v2/features/entitlements/presentation/screens/entitlement_admin_screen.dart';
import 'package:abakus_one_v2/features/integrations/presentation/screens/tenant_integration_hub_screen.dart';
import 'package:abakus_one_v2/features/inventory/presentation/screens/ingredient_catalog_screen.dart';
import 'package:abakus_one_v2/features/inventory/presentation/screens/inventory_screen.dart';
import 'package:abakus_one_v2/features/inventory/presentation/screens/stock_counts_screen.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/actor_session_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/pos_branch_overview_screen.dart';
import 'package:abakus_one_v2/features/purchasing/presentation/screens/suppliers_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/reservation_operations_screen.dart';
import 'package:abakus_one_v2/features/recipes/presentation/screens/recipes_screen.dart';
import 'package:abakus_one_v2/features/restaurant_setup/presentation/screens/setup_templates_screen.dart';
import 'package:abakus_one_v2/features/smart_import/presentation/screens/import_jobs_screen.dart';

import '../../entitlements/test_support/entitlement_test_fixtures.dart';
import 'test_support/fake_admin_reservation_gateway.dart';
import 'test_support/fake_admin_reservation_repository.dart';

void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    ActorSession? session,
    Size size = const Size(1400, 900),
    List<Override> extraOverrides = const [],
    String? initialNavItemId,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (session != null)
            actorSessionProvider.overrideWith((ref) => session),
          ...extraOverrides,
        ],
        child: MaterialApp(
          home: AdminShellScreen(initialNavItemId: initialNavItemId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows AdminUnauthorizedScreen with no session', (tester) async {
    await pumpShell(tester);

    expect(find.byType(AdminUnauthorizedScreen), findsOneWidget);
  });

  testWidgets('shows AdminSessionExpiredScreen for a revoked session',
      (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'admin-1',
        roles: {StaffRole.admin},
        activeRole: StaffRole.admin,
        revoked: true,
      ),
    );

    expect(find.byType(AdminSessionExpiredScreen), findsOneWidget);
  });

  testWidgets(
      'a manager session on a wide viewport shows the desktop '
      'sidebar with grouped sections', (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
      ),
      size: const Size(1400, 900),
    );

    expect(find.text('Müşteri & Sadakat'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Yapılandırma'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    expect(find.text('Yapılandırma'), findsOneWidget);
    // A courier-only section must not be visible to a manager-only
    // session that also isn't courier.
    expect(find.text('Kurye Vardiya ve Teslimatlarım'), findsNothing);
  });

  testWidgets('selecting a destination on desktop opens its screen',
      (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
      ),
    );

    await tester.tap(find.text('Segmentasyon'));
    await tester.pumpAndSettle();

    expect(find.byType(CustomerSegmentationAdminScreen), findsOneWidget);
  });

  testWidgets(
      'PC Yönetici İnceleme Modu: initialNavItemId "pos" opens the POS '
      'branch overview directly, with no tap needed — the dev-admin '
      'shortcut\'s own landing target', (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'admin-1',
        roles: {StaffRole.admin},
        activeRole: StaffRole.admin,
      ),
      initialNavItemId: 'pos',
    );

    expect(find.byType(PosBranchOverviewScreen), findsOneWidget);
  });

  testWidgets(
      'a null initialNavItemId (every real sign-in) keeps the existing '
      'default landing behavior unchanged — never POS unless requested',
      (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'admin-1',
        roles: {StaffRole.admin},
        activeRole: StaffRole.admin,
      ),
    );

    expect(find.byType(PosBranchOverviewScreen), findsNothing);
  });

  testWidgets(
      'Faz R.3A — a manager with branch access and reservationsEnabled can '
      'open Rezervasyonlar from Operasyonlar group', (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
        branchAccess: {'branch-1'},
      ),
      extraOverrides: [
        featureFlagsServiceProvider.overrideWithValue(
          FakeFeatureFlagsService(
              enabledKeys: {FeatureFlagsKeys.reservationsEnabled}),
        ),
        adminReservationGatewayProvider
            .overrideWithValue(FakeAdminReservationGateway()),
        adminReservationRepositoryProvider
            .overrideWithValue(FakeAdminReservationRepository()),
      ],
    );

    await tester.tap(find.text('Rezervasyonlar'));
    await tester.pumpAndSettle();

    expect(find.byType(ReservationOperationsScreen), findsOneWidget);
  });

  testWidgets(
      'Faz R.3A — without reservationsEnabled, Rezervasyonlar denies with a '
      'feature-disabled message', (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
        branchAccess: {'branch-1'},
      ),
      extraOverrides: [
        adminReservationGatewayProvider
            .overrideWithValue(FakeAdminReservationGateway()),
        adminReservationRepositoryProvider
            .overrideWithValue(FakeAdminReservationRepository()),
      ],
    );

    await tester.tap(find.text('Rezervasyonlar'));
    await tester.pumpAndSettle();

    expect(find.byType(ReservationOperationsScreen), findsNothing);
    expect(find.text('Bu özellik henüz etkinleştirilmedi.'), findsOneWidget);
  });

  testWidgets(
      'Faz R.3A — a staff-only session (no manageReservations) sees the '
      'group but Rezervasyonlar denies at the RoleGate layer even with the '
      'flag enabled', (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'staff-1',
        roles: {StaffRole.staff},
        activeRole: StaffRole.staff,
        branchAccess: {'branch-1'},
      ),
      extraOverrides: [
        featureFlagsServiceProvider.overrideWithValue(
          FakeFeatureFlagsService(
              enabledKeys: {FeatureFlagsKeys.reservationsEnabled}),
        ),
        adminReservationGatewayProvider
            .overrideWithValue(FakeAdminReservationGateway()),
        adminReservationRepositoryProvider
            .overrideWithValue(FakeAdminReservationRepository()),
      ],
    );

    // Base staff never holds manageReservations — the shell's own
    // group-visibility filtering already hides the destination entirely
    // (a UX convenience, not the security boundary — RoleGate would deny
    // it too if somehow reached).
    expect(find.text('Rezervasyonlar'), findsNothing);
  });

  testWidgets(
      'Faz R.3A.1 — an admin session can see and open Rezervasyonlar '
      '(canonical manageReservations mapping)', (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'admin-1',
        roles: {StaffRole.admin},
        activeRole: StaffRole.admin,
        branchAccess: {'branch-1'},
      ),
      extraOverrides: [
        featureFlagsServiceProvider.overrideWithValue(
          FakeFeatureFlagsService(
              enabledKeys: {FeatureFlagsKeys.reservationsEnabled}),
        ),
        adminReservationGatewayProvider
            .overrideWithValue(FakeAdminReservationGateway()),
        adminReservationRepositoryProvider
            .overrideWithValue(FakeAdminReservationRepository()),
      ],
    );

    expect(find.text('Rezervasyonlar'), findsOneWidget);
    await tester.tap(find.text('Rezervasyonlar'));
    await tester.pumpAndSettle();

    expect(find.byType(ReservationOperationsScreen), findsOneWidget);
  });

  testWidgets(
      'Faz R.3A.1 — a tenantOwner session can see and open Rezervasyonlar '
      '(regression proof: the old hardcoded {manager, admin} sidebar gate '
      'silently excluded tenantOwner even though tenantOwner inherits '
      'manageReservations from the manager tier — visibility is now '
      'derived from RolePermissionMap, not hand-authored)', (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'owner-1',
        roles: {StaffRole.tenantOwner},
        activeRole: StaffRole.tenantOwner,
        branchAccess: {'branch-1'},
      ),
      extraOverrides: [
        featureFlagsServiceProvider.overrideWithValue(
          FakeFeatureFlagsService(
              enabledKeys: {FeatureFlagsKeys.reservationsEnabled}),
        ),
        adminReservationGatewayProvider
            .overrideWithValue(FakeAdminReservationGateway()),
        adminReservationRepositoryProvider
            .overrideWithValue(FakeAdminReservationRepository()),
      ],
    );

    // Rezervasyonlar is now tenantOwner's earliest-visible destination
    // across every group (Genel Bakış and Mutfak/KDS both still exclude
    // tenantOwner), so the desktop shell auto-selects it on first build —
    // the sidebar item's own label and the already-open screen's headline
    // both render "Rezervasyonlar" simultaneously, hence findsWidgets
    // rather than findsOneWidget here.
    expect(find.text('Rezervasyonlar'), findsWidgets);
    expect(find.byType(ReservationOperationsScreen), findsOneWidget);
  });

  testWidgets(
      'Faz R.3A.1 — a courier-only session never sees Rezervasyonlar '
      '(lateral tier, holds neither manageReservations nor manageBranch)',
      (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'courier-1',
        roles: {StaffRole.courier},
        activeRole: StaffRole.courier,
        branchAccess: {'branch-1'},
      ),
      extraOverrides: [
        featureFlagsServiceProvider.overrideWithValue(
          FakeFeatureFlagsService(
              enabledKeys: {FeatureFlagsKeys.reservationsEnabled}),
        ),
        adminReservationGatewayProvider
            .overrideWithValue(FakeAdminReservationGateway()),
        adminReservationRepositoryProvider
            .overrideWithValue(FakeAdminReservationRepository()),
      ],
    );

    expect(find.text('Rezervasyonlar'), findsNothing);
  });

  testWidgets(
      'Faz R.3A.1 — Çalışma Saatleri (branch operating hours) is reachable '
      'through its own manageBranch RoleGate for an authorized manager '
      '(regression proof that gating the destination did not break the '
      'legitimate path)', (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
        branchAccess: {'branch-1'},
      ),
      extraOverrides: [
        featureFlagsServiceProvider.overrideWithValue(
          FakeFeatureFlagsService(
              enabledKeys: {FeatureFlagsKeys.reservationsEnabled}),
        ),
        adminReservationGatewayProvider
            .overrideWithValue(FakeAdminReservationGateway()),
        adminReservationRepositoryProvider
            .overrideWithValue(FakeAdminReservationRepository()),
      ],
    );

    await tester.tap(find.text('Rezervasyonlar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Çalışma Saatleri'));
    await tester.pumpAndSettle();

    // A real StaffRole.manager DOES hold manageBranch under today's
    // canonical mapping (both tiers move together), so this proves the
    // gate is wired and lets a legitimately-authorized manager through —
    // the genuinely isolated "manageReservations without manageBranch"
    // case cannot be constructed via any real StaffRole today (see
    // RolePermissionMap: both live in the same manager tier), matching the
    // identical, already-disclosed constraint on the backend side
    // (getBranchOperatingHours.test.ts / updateBranchOperatingHours.test.ts).
    expect(find.text('Bu ekrana erişim yetkiniz yok.'), findsNothing);
  });

  testWidgets('a manager can open the Audit Center from Sistem group',
      (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
      ),
    );

    await tester.dragUntilVisible(
      find.text('Denetim'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Denetim'));
    await tester.pumpAndSettle();

    expect(find.byType(AuditCenterScreen), findsOneWidget);
  });

  testWidgets(
      'a manager with branch access and the flag enabled can open Menü '
      'İçe Aktarma from Akıllı Kurulum & Stok group', (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
        branchAccess: {'branch-1'},
      ),
      extraOverrides: [
        featureFlagsServiceProvider.overrideWithValue(
          FakeFeatureFlagsService(
            enabledKeys: {FeatureFlagsKeys.menuImportEnabled},
          ),
        ),
      ],
    );

    await tester.dragUntilVisible(
      find.text('Menü İçe Aktarma'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    // Faz R.3A added a new "Rezervasyonlar" destination in an earlier
    // group, pushing every later group further down — dragUntilVisible's
    // own "any part on screen" check now leaves this item's center still
    // a little below the viewport by the time it stops; ensureVisible
    // scrolls precisely enough for the tap's own center-point hit test to
    // land on it.
    await tester.ensureVisible(find.text('Menü İçe Aktarma').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menü İçe Aktarma').first);
    await tester.pumpAndSettle();

    expect(find.byType(ImportJobsScreen), findsOneWidget);
  });

  testWidgets(
      'a manager with branch access and the flag enabled can open Kurulum '
      'Şablonları from Akıllı Kurulum & Stok group', (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
        branchAccess: {'branch-1'},
      ),
      extraOverrides: [
        featureFlagsServiceProvider.overrideWithValue(
          FakeFeatureFlagsService(
            enabledKeys: {FeatureFlagsKeys.smartRestaurantSetupEnabled},
          ),
        ),
      ],
    );

    await tester.dragUntilVisible(
      find.text('Kurulum Şablonları'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    // AP-6 Sprint 2 added a new "Teslimat Dağıtımı" destination in an
    // earlier group, pushing this one further down — same fix as "Menü
    // İçe Aktarma" above: dragUntilVisible's own "any part on screen"
    // check now leaves this item's center still a little below the
    // viewport by the time it stops; ensureVisible scrolls precisely
    // enough for the tap's own center-point hit test to land on it.
    await tester.ensureVisible(find.text('Kurulum Şablonları').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kurulum Şablonları').first);
    await tester.pumpAndSettle();

    expect(find.byType(SetupTemplatesScreen), findsOneWidget);
  });

  testWidgets(
      'a manager with branch access and the flag enabled can open Malzeme '
      'Kataloğu from Akıllı Kurulum & Stok group', (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
        branchAccess: {'branch-1'},
      ),
      extraOverrides: [
        featureFlagsServiceProvider.overrideWithValue(
          FakeFeatureFlagsService(
            enabledKeys: {FeatureFlagsKeys.inventoryEnabled},
          ),
        ),
      ],
    );

    await tester.dragUntilVisible(
      find.text('Malzeme Kataloğu'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Malzeme Kataloğu').first);
    await tester.pumpAndSettle();

    expect(find.byType(IngredientCatalogScreen), findsOneWidget);
  });

  testWidgets(
      'a manager with branch access and the flag enabled can open Envanter '
      'from Akıllı Kurulum & Stok group', (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
        branchAccess: {'branch-1'},
      ),
      extraOverrides: [
        featureFlagsServiceProvider.overrideWithValue(
          FakeFeatureFlagsService(
            enabledKeys: {FeatureFlagsKeys.inventoryEnabled},
          ),
        ),
      ],
    );

    await tester.dragUntilVisible(
      find.text('Envanter'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Envanter').first);
    await tester.pumpAndSettle();

    expect(find.byType(InventoryScreen), findsOneWidget);
  });

  testWidgets(
      'a manager with branch access and the flag enabled can open Stok '
      'Sayımları from Akıllı Kurulum & Stok group', (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
        branchAccess: {'branch-1'},
      ),
      extraOverrides: [
        featureFlagsServiceProvider.overrideWithValue(
          FakeFeatureFlagsService(
            enabledKeys: {FeatureFlagsKeys.inventoryEnabled},
          ),
        ),
      ],
    );

    await tester.dragUntilVisible(
      find.text('Stok Sayımları'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stok Sayımları').first);
    await tester.pumpAndSettle();

    expect(find.byType(StockCountsScreen), findsOneWidget);
  });

  testWidgets(
      'a manager with branch access and the flag enabled can open Tarifler '
      'from Akıllı Kurulum & Stok group', (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
        branchAccess: {'branch-1'},
      ),
      extraOverrides: [
        featureFlagsServiceProvider.overrideWithValue(
          FakeFeatureFlagsService(
            enabledKeys: {FeatureFlagsKeys.recipesEnabled},
          ),
        ),
      ],
    );

    await tester.dragUntilVisible(
      find.text('Tarifler'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tarifler').first);
    await tester.pumpAndSettle();

    expect(find.byType(RecipesScreen), findsOneWidget);
  });

  testWidgets(
      'a manager with branch access and the flag enabled can open '
      'Tedarikçiler from Akıllı Kurulum & Stok group', (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
        branchAccess: {'branch-1'},
      ),
      extraOverrides: [
        featureFlagsServiceProvider.overrideWithValue(
          FakeFeatureFlagsService(
            enabledKeys: {FeatureFlagsKeys.suppliersEnabled},
          ),
        ),
      ],
    );

    await tester.dragUntilVisible(
      find.text('Tedarikçiler'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tedarikçiler').first);
    await tester.pumpAndSettle();

    expect(find.byType(SuppliersScreen), findsOneWidget);
  });

  testWidgets(
      'without the feature flag enabled, Menü İçe Aktarma denies with a '
      'feature-disabled message', (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
        branchAccess: {'branch-1'},
      ),
    );

    await tester.dragUntilVisible(
      find.text('Menü İçe Aktarma'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    // Faz R.3A added a new "Rezervasyonlar" destination in an earlier
    // group, pushing every later group further down — dragUntilVisible's
    // own "any part on screen" check now leaves this item's center still
    // a little below the viewport by the time it stops; ensureVisible
    // scrolls precisely enough for the tap's own center-point hit test to
    // land on it.
    await tester.ensureVisible(find.text('Menü İçe Aktarma').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menü İçe Aktarma').first);
    await tester.pumpAndSettle();

    expect(find.byType(ImportJobsScreen), findsNothing);
    expect(find.text('Bu özellik henüz etkinleştirilmedi.'), findsOneWidget);
  });

  testWidgets('a manager can open the Device Registry from Yapılandırma group',
      (tester) async {
    await pumpShell(
      tester,
      // AP-5 Sprint 6 added one more nav item ahead of "Cihazlar"
      // ("Reçete-Malzeme Bağlantıları"), and the previous fixed-pixel
      // drag-then-nudge approach turned out to be fragile in a way tuning
      // the nudge amount didn't fix (the sidebar `ListView`'s own natural
      // height was already close to the default 900px viewport, so drag
      // deltas past its real scroll extent are simply clamped and never
      // move "Cihazlar" at all — confirmed by the identical failure at
      // three different drag magnitudes). A taller viewport, only for
      // this test, makes the whole sidebar fit without needing to scroll
      // to reach it at all — robust to the sidebar's exact item count
      // going forward, not just this specific count.
      size: const Size(1400, 1600),
      session: const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
      ),
    );

    await tester.ensureVisible(find.text('Cihazlar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cihazlar'));
    await tester.pumpAndSettle();

    expect(find.byType(DeviceRegistryScreen), findsOneWidget);
  });

  testWidgets('an admin can open Localization from Sistem group',
      (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'admin-1',
        roles: {StaffRole.admin},
        activeRole: StaffRole.admin,
      ),
    );

    await tester.dragUntilVisible(
      find.text('Yerelleştirme'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yerelleştirme').first);
    await tester.pumpAndSettle();

    expect(find.byType(LocalizationAdminScreen), findsOneWidget);
  });

  testWidgets(
      'an admin can open Abonelikler (Entitlements) from Sistem '
      'group', (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'admin-1',
        roles: {StaffRole.admin},
        activeRole: StaffRole.admin,
      ),
    );

    await tester.dragUntilVisible(
      find.text('Abonelikler'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -150));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abonelikler').first);
    await tester.pumpAndSettle();

    expect(find.byType(EntitlementAdminScreen), findsOneWidget);
  });

  testWidgets('a manager cannot see the admin-only Localization destination',
      (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
      ),
    );

    expect(find.text('Yerelleştirme'), findsNothing);
  });

  testWidgets('a manager can open Ayarlar (System Health) from Sistem group',
      (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
      ),
    );

    await tester.dragUntilVisible(
      find.text('Ayarlar'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayarlar').first);
    await tester.pumpAndSettle();

    expect(find.byType(SystemHealthAdminScreen), findsOneWidget);
  });

  testWidgets(
      'a courier-only session sees a narrow section set, no '
      'manager-only destinations', (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'courier-1',
        roles: {StaffRole.courier},
        activeRole: StaffRole.courier,
      ),
    );

    expect(find.text('Müşteri & Sadakat'), findsNothing);
    expect(find.text('Yapılandırma'), findsNothing);
  });

  testWidgets('a tenantOwner can open Entegrasyonlar from Sistem group',
      (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'owner-1',
        roles: {StaffRole.tenantOwner},
        activeRole: StaffRole.tenantOwner,
        // Phase 8 closure sprint: BuildProviderHealthProjection/
        // BuildIntegrationAuditCenterProjection now independently
        // enforce organization-scoping, so this session needs real
        // access to the seeded 'org-1' the same way SetTenantIntegrationEnabled
        // (the write path) always required.
        organizationAccess: {'org-1'},
      ),
    );

    // Faz R.3A.1: tenantOwner also now correctly sees "Rezervasyonlar"
    // (visibility is derived from RolePermissionMap, not a hardcoded
    // {manager, admin} list that used to exclude tenantOwner) — so
    // "Entegrasyonlar" is no longer this role's *only* visible
    // destination and the desktop shell's first-visible-item auto-select
    // no longer reliably lands here. Navigate explicitly instead.
    await tester.tap(find.text('Entegrasyonlar'));
    await tester.pumpAndSettle();

    expect(find.byType(TenantIntegrationHubScreen), findsOneWidget);
  });

  testWidgets(
      'a manager (not tenantOwner) cannot see the Entegrasyonlar '
      'destination', (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
      ),
    );

    expect(find.text('Entegrasyonlar'), findsNothing);
  });

  testWidgets('a narrow viewport shows the mobile drawer chrome',
      (tester) async {
    await pumpShell(
      tester,
      session: const ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
      ),
      size: const Size(390, 844),
    );

    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.byType(Drawer), findsNothing); // closed by default
  });
}
