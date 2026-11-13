import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/data/staff_account_gateway.dart';
import 'package:abakus_one_v2/features/admin/data/staff_member_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/staff/staff_member.dart';
import 'package:abakus_one_v2/features/admin/domain/staff/staff_member_status.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/staff_detail_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/staff_management_screen.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/actor_session_provider.dart';

import '../test_support/admin_test_fixtures.dart';

/// Records every command and mirrors the effect into the in-memory roster,
/// like the real callables would. [refuseWith] makes the next call fail.
class _FakeStaffAccountGateway implements StaffAccountGateway {
  _FakeStaffAccountGateway(this.repository);

  final InMemoryStaffMemberRepository repository;
  final List<String> calls = [];
  String? lastPassword;
  Set<StaffRole>? lastRoles;
  Set<String>? lastBranches;
  String? refuseWith;

  void _maybeRefuse() {
    final message = refuseWith;
    if (message != null) {
      refuseWith = null;
      throw StaffAccountException(message);
    }
  }

  /// What the server would answer: a manager's new account waits for an
  /// admin/owner (ADR-085 stage 1).
  bool pendingOnCreate = false;

  @override
  Future<bool> createStaffAccount({
    required String organizationId,
    required String firstName,
    required String lastName,
    required String phoneNumber,
    required String password,
    required Set<StaffRole> roles,
    required Set<String> branchAccess,
  }) async {
    calls.add('create:$phoneNumber');
    _maybeRefuse();
    lastPassword = password;
    lastRoles = roles;
    lastBranches = branchAccess;
    await repository.save(StaffMember(
      id: 'uid-$phoneNumber',
      authUid: 'uid-$phoneNumber',
      displayName: '$firstName $lastName',
      phoneNumber: phoneNumber,
      roles: roles,
      branchAccess: branchAccess,
      status: pendingOnCreate
          ? StaffMemberStatus.pendingApproval
          : StaffMemberStatus.active,
      createdAt: DateTime(2026, 11, 13),
      revision: 1,
    ));
    return pendingOnCreate;
  }

  @override
  Future<void> setStaffPassword({
    required String organizationId,
    required String targetUid,
    required String password,
  }) async {
    calls.add('password:$targetUid');
    _maybeRefuse();
    lastPassword = password;
  }

  @override
  Future<void> updateStaffMember({
    required String organizationId,
    required String targetUid,
    Set<StaffRole>? roles,
    bool? active,
  }) async {
    calls.add('update:$targetUid');
    _maybeRefuse();
    final member = (await repository.findById(targetUid))!;
    await repository.save(member.copyWith(
      roles: roles,
      status: active == null
          ? null
          : (active ? StaffMemberStatus.active : StaffMemberStatus.suspended),
      revision: member.revision + 1,
    ));
  }
}

const _manager = ActorSession(
  actorId: 'manager-1',
  roles: {StaffRole.manager},
  activeRole: StaffRole.manager,
  branchAccess: {'branch-1'},
);

const _admin = ActorSession(
  actorId: 'admin-1',
  roles: {StaffRole.admin},
  activeRole: StaffRole.admin,
  branchAccess: {'branch-1'},
);

void main() {
  late InMemoryStaffMemberRepository repository;
  late _FakeStaffAccountGateway gateway;

  Future<void> pumpScreen(WidgetTester tester,
      {ActorSession session = _manager}) async {
    repository = InMemoryStaffMemberRepository();
    gateway = _FakeStaffAccountGateway(repository);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffMemberRepositoryProvider.overrideWithValue(repository),
          staffAccountGatewayProvider.overrideWithValue(gateway),
          actorSessionProvider.overrideWith((ref) => session),
        ],
        child: const MaterialApp(
          home: StaffManagementScreen(
            authorizationPolicy: AllowAllAdminPolicy(),
            performedByStaffId: 'manager-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> addStaff(WidgetTester tester, {bool pickRole = true}) async {
    await tester.tap(find.byTooltip('Personel Ekle'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('staffFirstNameField')), 'Ayşe');
    await tester.enterText(
        find.byKey(const Key('staffLastNameField')), 'Yılmaz');
    await tester.enterText(
        find.byKey(const Key('staffPhoneField')), '5321234567');
    await tester.enterText(
        find.byKey(const Key('staffPasswordField')), 'dogru-sifre-123');
    if (pickRole) {
      await tester.tap(find.byKey(const Key('staffRoleChip-cashier')));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.byKey(const Key('staffCreateSaveButton')));
    await tester.tap(find.byKey(const Key('staffCreateSaveButton')));
    await tester.pumpAndSettle();
  }

  testWidgets('an empty roster offers "Personel Ekle"', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Personel Yönetimi'), findsOneWidget);
    expect(find.text('Henüz personel yok.'), findsOneWidget);
  });

  testWidgets(
      '"Personel Ekle" creates an active account with name, phone, password, '
      'role and branch, and lists it', (tester) async {
    await pumpScreen(tester, session: _admin);
    await addStaff(tester);

    expect(gateway.calls, ['create:+905321234567']);
    expect(gateway.lastPassword, 'dogru-sifre-123');
    expect(gateway.lastRoles, {StaffRole.cashier});
    expect(gateway.lastBranches, {'branch-1'});
    expect(find.text('Ayşe Yılmaz'), findsOneWidget);
    expect(
        find.textContaining('+905321234567 · Kasiyer · Aktif'), findsOneWidget);
  });

  testWidgets('the form requires a role and an 8+ character password',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byTooltip('Personel Ekle'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('staffPasswordField')), 'kisa');
    await tester.ensureVisible(find.byKey(const Key('staffCreateSaveButton')));
    await tester.tap(find.byKey(const Key('staffCreateSaveButton')));
    await tester.pumpAndSettle();

    expect(gateway.calls, isEmpty);
    expect(find.text('Şifre en az 8 karakter olmalı'), findsOneWidget);
    expect(find.text('En az bir rol seçin'), findsOneWidget);
  });

  testWidgets('a manager is offered only cashier/courier-level roles',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byTooltip('Personel Ekle'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('staffRoleChip-cashier')), findsOneWidget);
    expect(find.byKey(const Key('staffRoleChip-courier')), findsOneWidget);
    expect(find.byKey(const Key('staffRoleChip-manager')), findsNothing);
    expect(find.byKey(const Key('staffRoleChip-admin')), findsNothing);
  });

  testWidgets('a refused command shows its Turkish reason', (tester) async {
    await pumpScreen(tester);
    gateway.refuseWith = 'Bu telefon numarası zaten personel olarak kayıtlı.';
    await addStaff(tester);

    expect(find.text('Bu telefon numarası zaten personel olarak kayıtlı.'),
        findsOneWidget);
    expect(find.text('Ayşe Yılmaz'), findsNothing);
  });

  testWidgets(
      'ADR-085 stage 1: an account a manager adds waits for an admin/owner, '
      'and the manager is never offered "Pasife Al"', (tester) async {
    await pumpScreen(tester);
    gateway.pendingOnCreate = true;
    await addStaff(tester);

    expect(
        find.text(
            'Ayşe Yılmaz eklendi. Yönetici onayından sonra aktif olacak.'),
        findsOneWidget);
    expect(find.textContaining('Kasiyer · Yönetici Onayı Bekliyor'),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('staffActions-uid-+905321234567')));
    await tester.pumpAndSettle();
    expect(find.text('Şifre Değiştir'), findsOneWidget);
    expect(find.text('Pasife Al'), findsNothing);
    expect(find.text('Aktifleştir'), findsNothing);
  });

  testWidgets('an admin changes a password and suspends the member',
      (tester) async {
    await pumpScreen(tester, session: _admin);
    await addStaff(tester);

    await tester.tap(find.byKey(const Key('staffActions-uid-+905321234567')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Şifre Değiştir'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('staffNewPasswordField')), 'yeni-sifre-456');
    await tester.enterText(
        find.byKey(const Key('staffRepeatPasswordField')), 'yeni-sifre-456');
    await tester.tap(find.byKey(const Key('staffPasswordSaveButton')));
    await tester.pumpAndSettle();
    expect(gateway.calls.last, 'password:uid-+905321234567');
    expect(gateway.lastPassword, 'yeni-sifre-456');

    await tester.tap(find.byKey(const Key('staffActions-uid-+905321234567')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pasife Al'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kasiyer · Pasif'), findsOneWidget);
  });

  testWidgets('tapping a staff member opens StaffDetailScreen', (tester) async {
    await pumpScreen(tester);
    await addStaff(tester);

    await tester.tap(find.text('Ayşe Yılmaz'));
    await tester.pumpAndSettle();

    expect(find.byType(StaffDetailScreen), findsOneWidget);
  });
}
