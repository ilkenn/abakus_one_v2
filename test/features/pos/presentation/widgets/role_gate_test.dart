import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorized_action.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/actor_session_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/widgets/role_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpGate(
    WidgetTester tester, {
    ActorSession? session,
    required Widget gate,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (session != null)
            actorSessionProvider.overrideWith((ref) => session),
        ],
        child: MaterialApp(home: gate),
      ),
    );
  }

  group('RoleGate', () {
    testWidgets('denies with no active session', (tester) async {
      await pumpGate(
        tester,
        gate: RoleGate.forRoles(
          const {StaffRole.manager},
          child: const Text('protected content'),
        ),
      );

      expect(find.text('protected content'), findsNothing);
      expect(find.text('Bu ekrana erişim yetkiniz yok.'), findsOneWidget);
    });

    testWidgets('allows when the session holds a permitted role',
        (tester) async {
      await pumpGate(
        tester,
        session: const ActorSession(
          actorId: 'manager-1',
          roles: {StaffRole.manager},
          activeRole: StaffRole.manager,
        ),
        gate: RoleGate.forRoles(
          const {StaffRole.manager},
          child: const Text('protected content'),
        ),
      );

      expect(find.text('protected content'), findsOneWidget);
    });

    testWidgets(
        'denies when the session lacks the permitted role — '
        'deep-link access is protected', (tester) async {
      await pumpGate(
        tester,
        session: const ActorSession(
          actorId: 'courier-1',
          roles: {StaffRole.courier},
          activeRole: StaffRole.courier,
        ),
        gate: RoleGate.forRoles(
          const {StaffRole.manager, StaffRole.admin},
          child: const Text('protected content'),
        ),
      );

      expect(find.text('protected content'), findsNothing);
      expect(find.text('Bu ekrana erişim yetkiniz yok.'), findsOneWidget);
    });

    testWidgets('forAction gates using RolePermissionMap directly',
        (tester) async {
      await pumpGate(
        tester,
        session: const ActorSession(
          actorId: 'staff-1',
          roles: {StaffRole.staff},
          activeRole: StaffRole.staff,
        ),
        gate: RoleGate.forAction(
          PosAuthorizedAction.voidPayment, // admin-only
          child: const Text('protected content'),
        ),
      );

      expect(find.text('protected content'), findsNothing);
    });
  });
}
