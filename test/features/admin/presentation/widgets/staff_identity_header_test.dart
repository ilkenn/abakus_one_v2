import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/data/own_staff_name_repository.dart';
import 'package:abakus_one_v2/features/admin/presentation/widgets/staff_identity_header.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/actor_session_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/widgets/role_gate.dart';

class _FakeNames implements OwnStaffNameRepository {
  const _FakeNames(this.name);
  final String? name;

  @override
  Future<String?> ownName({
    required String organizationId,
    required String uid,
  }) async =>
      name;
}

ActorSession _session(Set<StaffRole> roles) => ActorSession(
      actorId: 'uid-1',
      roles: roles,
      activeRole: roles.first,
      branchAccess: const {'branch-1'},
    );

void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester,
    ActorSession session, {
    String? name = 'Ayşe Yılmaz',
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        actorSessionProvider.overrideWith((ref) => session),
        ownStaffNameRepositoryProvider.overrideWithValue(_FakeNames(name)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: StaffRolePreviewBanner(
            child: Column(
              children: [
                StaffIdentityHeader(session: session),
                Expanded(
                  child: RoleGate.forRoles(
                    const {StaffRole.admin},
                    child: const Text('Personel Yönetimi'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(StaffIdentityHeader)));
  }

  testWidgets('the sidebar header shows name, surname and role',
      (tester) async {
    await pump(tester, _session({StaffRole.manager}));

    expect(find.text('Ayşe Yılmaz'), findsOneWidget);
    expect(find.text('Müdür'), findsOneWidget);
    expect(find.byKey(const Key('staffRolePreviewMenu')), findsNothing,
        reason: 'only an admin/owner may preview roles');
  });

  testWidgets('without a stored name the header names the role',
      (tester) async {
    await pump(tester, _session({StaffRole.cashier}), name: null);

    expect(find.byKey(const Key('staffIdentityName')), findsOneWidget);
    expect(find.text('Kasiyer'), findsNWidgets(2));
  });

  testWidgets(
      'an owner previews Kasiyer: admin-only screens close, one tap returns',
      (tester) async {
    final container = await pump(tester, _session({StaffRole.tenantOwner}));
    expect(find.text('Sahip'), findsOneWidget);
    expect(find.text('Personel Yönetimi'), findsOneWidget);

    await tester.tap(find.byKey(const Key('staffRolePreviewMenu')));
    await tester.pumpAndSettle();
    for (final label in ['Müdür', 'Kasiyer', 'Kurye', 'Paketleme']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('staffRolePreview-cashier')));
    await tester.pumpAndSettle();

    expect(container.read(staffRolePreviewProvider), StaffRole.cashier);
    expect(find.text('Rol önizlemesi: Kasiyer'), findsOneWidget);
    expect(find.text('Personel Yönetimi'), findsNothing);
    expect(find.text('Bu ekrana erişim yetkiniz yok.'), findsOneWidget);
    expect(container.read(actorSessionProvider)!.roles, {StaffRole.tenantOwner},
        reason: 'the real session never changes');

    await tester.tap(find.byKey(const Key('staffRolePreviewExit')));
    await tester.pumpAndSettle();
    expect(container.read(staffRolePreviewProvider), isNull);
    expect(find.text('Personel Yönetimi'), findsOneWidget);
  });

  test('a preview never applies to a non-admin session', () {
    final container = ProviderContainer(overrides: [
      actorSessionProvider.overrideWith((ref) => _session({StaffRole.manager})),
    ]);
    addTearDown(container.dispose);
    container.read(staffRolePreviewProvider.notifier).state = StaffRole.courier;

    expect(container.read(visibleActorSessionProvider)!.roles,
        {StaffRole.manager});
  });

  test('an admin preview narrows to exactly that role', () {
    final container = ProviderContainer(overrides: [
      actorSessionProvider.overrideWith((ref) => _session({StaffRole.admin})),
    ]);
    addTearDown(container.dispose);
    container.read(staffRolePreviewProvider.notifier).state =
        StaffRole.packingLead;

    final visible = container.read(visibleActorSessionProvider)!;
    expect(visible.roles, {StaffRole.packingLead});
    expect(visible.activeRole, StaffRole.packingLead);
    expect(visible.actorId, 'uid-1');
  });
}
