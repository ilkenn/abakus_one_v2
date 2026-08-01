import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/presentation/screens/admin_shell_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_session_expired_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_unauthorized_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/audit_center_screen.dart';
import 'package:abakus_one_v2/features/crm/presentation/screens/customer_segmentation_admin_screen.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/actor_session_provider.dart';

void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    ActorSession? session,
    Size size = const Size(1400, 900),
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
    await tester.tap(find.text('Denetim'));
    await tester.pumpAndSettle();

    expect(find.byType(AuditCenterScreen), findsOneWidget);
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
