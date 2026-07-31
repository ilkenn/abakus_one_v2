import 'package:abakus_one_v2/features/crm/presentation/screens/customer_segmentation_admin_screen.dart';
import 'package:abakus_one_v2/features/feedback/presentation/screens/feedback_admin_screen.dart';
import 'package:abakus_one_v2/features/navigation/presentation/screens/operations_hub_screen.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/actor_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpHub(WidgetTester tester, {ActorSession? session}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (session != null)
            actorSessionProvider.overrideWith((ref) => session),
        ],
        child: const MaterialApp(home: OperationsHubScreen()),
      ),
    );
  }

  group('OperationsHubScreen', () {
    testWidgets('a session with no staff-tier role is denied entirely',
        (tester) async {
      await pumpHub(tester);
      await tester.pump();

      expect(find.text('İşlem Merkezi'), findsNothing);
      expect(find.text('Bu ekrana erişim yetkiniz yok.'), findsOneWidget);
    });

    testWidgets('a manager session sees every section', (tester) async {
      await pumpHub(
        tester,
        session: const ActorSession(
          actorId: 'manager-1',
          roles: {StaffRole.manager},
          activeRole: StaffRole.manager,
        ),
      );
      await tester.pump();

      expect(find.text('Kurye Operasyonları'), findsOneWidget);
      expect(find.text('CRM / Sadakat'), findsOneWidget);
      expect(find.text('Geri Bildirim'), findsOneWidget);
    });

    testWidgets(
        'a manager can open Müşteri Segmentasyonu (authorized role → '
        'allowed)', (tester) async {
      await pumpHub(
        tester,
        session: const ActorSession(
          actorId: 'manager-1',
          roles: {StaffRole.manager},
          activeRole: StaffRole.manager,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Müşteri Segmentasyonu'));
      await tester.pumpAndSettle();

      expect(find.byType(CustomerSegmentationAdminScreen), findsOneWidget);
      // The pushed screen is itself real content, not a denial screen.
      expect(find.text('Bu ekrana erişim yetkiniz yok.'), findsNothing);
    });

    testWidgets(
        'a courier-only session tapping into a manager-gated destination '
        'is blocked at the destination screen (unauthorized role → '
        'blocked)', (tester) async {
      await pumpHub(
        tester,
        session: const ActorSession(
          actorId: 'courier-1',
          roles: {StaffRole.courier},
          activeRole: StaffRole.courier,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Müşteri Segmentasyonu'));
      await tester.pumpAndSettle();

      expect(find.byType(CustomerSegmentationAdminScreen), findsNothing);
      expect(find.text('Bu ekrana erişim yetkiniz yok.'), findsOneWidget);
    });

    testWidgets('a manager can open Geri Bildirim Yönetimi', (tester) async {
      await pumpHub(
        tester,
        session: const ActorSession(
          actorId: 'manager-1',
          roles: {StaffRole.manager},
          activeRole: StaffRole.manager,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Geri Bildirim Yönetimi'));
      await tester.pumpAndSettle();

      expect(find.byType(FeedbackAdminScreen), findsOneWidget);
    });

    testWidgets(
        'a courier-only session cannot reach a manager-gated screen '
        '(role switching baseline)', (tester) async {
      const courierOnly = ActorSession(
        actorId: 'dual-1',
        roles: {StaffRole.courier},
        activeRole: StaffRole.courier,
      );
      await pumpHub(tester, session: courierOnly);
      await tester.pump();

      await tester.tap(find.text('Müşteri Segmentasyonu'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomerSegmentationAdminScreen), findsNothing);
      expect(find.text('Bu ekrana erişim yetkiniz yok.'), findsOneWidget);
    });

    testWidgets(
        'switching the same actor to also hold manager makes the '
        'manager-gated screen reachable (role switching changes active '
        'permissions correctly)', (tester) async {
      const dualRole = ActorSession(
        actorId: 'dual-1',
        roles: {StaffRole.courier, StaffRole.manager},
        activeRole: StaffRole.manager,
      );
      await pumpHub(tester, session: dualRole);
      await tester.pump();

      await tester.tap(find.text('Müşteri Segmentasyonu'));
      await tester.pumpAndSettle();

      expect(find.byType(CustomerSegmentationAdminScreen), findsOneWidget);
      expect(find.text('Bu ekrana erişim yetkiniz yok.'), findsNothing);
    });
  });
}
