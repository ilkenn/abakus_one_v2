import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/actor_session_provider.dart';
import 'package:abakus_one_v2/features/smart_import/presentation/screens/import_jobs_screen.dart';

import '../../entitlements/test_support/entitlement_test_fixtures.dart';

void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    ActorSession? session,
    Size size = const Size(1400, 900),
    List<Override> extraOverrides = const [],
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
        child: const MaterialApp(home: AdminShellScreen()),
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
    await tester.tap(find.text('Menü İçe Aktarma').first);
    await tester.pumpAndSettle();

    expect(find.byType(ImportJobsScreen), findsOneWidget);
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
    await tester.tap(find.text('Menü İçe Aktarma').first);
    await tester.pumpAndSettle();

    expect(find.byType(ImportJobsScreen), findsNothing);
    expect(find.text('Bu özellik henüz etkinleştirilmedi.'), findsOneWidget);
  });

  testWidgets('a manager can open the Device Registry from Yapılandırma group',
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
      find.text('Cihazlar'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    // dragUntilVisible stops as soon as the finder matches, even if only
    // partially scrolled into the viewport — nudge further so the tap's
    // hit-test point lands inside the 900px-tall test viewport.
    await tester.drag(find.byType(ListView).first, const Offset(0, -100));
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
