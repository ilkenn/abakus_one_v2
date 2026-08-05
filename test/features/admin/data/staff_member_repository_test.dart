import 'package:abakus_one_v2/features/admin/data/staff_member_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/staff/staff_member.dart';
import 'package:abakus_one_v2/features/admin/domain/staff/staff_member_status.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryStaffMemberRepository (development/debug behavior)', () {
    test('a saved member is enumerable via findAll and findById', () async {
      final repository = InMemoryStaffMemberRepository();
      final member = StaffMember(
        id: 'staff-1',
        displayName: 'Ada Admin',
        roles: const {StaffRole.admin},
        status: StaffMemberStatus.active,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      );

      await repository.save(member);

      expect((await repository.findAll()).single.displayName, 'Ada Admin');
      expect((await repository.findById('staff-1'))?.displayName, 'Ada Admin');
    });
  });

  group(
      'ProductionUnavailableStaffMemberRepository (Phase 8 closure sprint '
      '— release builds)', () {
    const repository = ProductionUnavailableStaffMemberRepository();

    test('findAll exposes zero member metadata — no accounts', () async {
      expect(await repository.findAll(), isEmpty);
    });

    test(
        'findById never resolves any member — no names, roles, or '
        'statuses leak', () async {
      expect(await repository.findById('staff-1'), isNull);
    });

    test('findByBranch never resolves any member', () async {
      expect(await repository.findByBranch('branch-1'), isEmpty);
    });

    test(
        'save is unavailable — the roster can never be populated in a '
        'release build either', () async {
      final member = StaffMember(
        id: 'staff-1',
        displayName: 'Ada Admin',
        roles: const {StaffRole.admin},
        status: StaffMemberStatus.active,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      );

      expect(() => repository.save(member), throwsA(isA<StateError>()));
    });
  });
}
