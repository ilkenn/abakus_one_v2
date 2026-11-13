import 'package:abakus_one_v2/features/admin/presentation/screens/admin_shell_screen.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:flutter_test/flutter_test.dart';

/// ADR-085 phase C — each role sees only its own screens in the panel.
/// Pins the menu per role so a later change cannot silently widen it.
void main() {
  List<String> menu(Set<StaffRole> roles) =>
      AdminShellScreen.visibleNavItemIds(roles);

  const managementOnly = [
    'staff',
    'cash',
    'menu',
    'reports',
    'settings',
    'branches',
    'devices',
    'customers',
    'loyalty',
  ];

  test('a cashier sees only the POS', () {
    expect(menu({StaffRole.cashier}), ['pos']);
  });

  test('a packing lead sees only the kitchen (KDS) and delivery dispatch', () {
    expect(menu({StaffRole.packingLead}), ['kitchen', 'delivery-dispatch']);
  });

  test('a courier gets no panel menu at all (Kurye Ekranım instead)', () {
    expect(menu({StaffRole.courier}), isEmpty);
  });

  test('a courier who is also a cashier still never sees the overview', () {
    expect(menu({StaffRole.courier, StaffRole.cashier}), ['pos']);
  });

  test('counter staff see POS and kitchen, never management screens', () {
    final items = menu({StaffRole.staff});
    expect(items, containsAll(['overview', 'kitchen', 'orders', 'pos']));
    for (final id in managementOnly) {
      expect(items, isNot(contains(id)), reason: id);
    }
  });

  test('a manager sees management, POS, KDS, courier and report screens', () {
    final items = menu({StaffRole.manager});
    expect(
      items,
      containsAll([
        'overview',
        'kitchen',
        'delivery-dispatch',
        'courier-report',
        'orders',
        'pos',
        'cash',
        'staff',
        'menu',
        'reports',
      ]),
    );
    expect(items, isNot(contains('entitlements')));
    expect(items, isNot(contains('localization')));
    expect(items, isNot(contains('integrations')));
  });

  test('an admin sees everything a manager sees, plus admin screens', () {
    final manager = menu({StaffRole.manager});
    final admin = menu({StaffRole.admin});
    expect(admin, containsAll(manager));
    expect(admin, containsAll(['entitlements', 'localization']));
    expect(admin, isNot(contains('integrations')));
  });

  test('an owner sees everything an admin sees, plus owner screens', () {
    final admin = menu({StaffRole.admin});
    final owner = menu({StaffRole.tenantOwner});
    expect(owner, containsAll(admin));
    expect(owner, contains('integrations'));
  });

  test('every counter role lands on a screen it can actually see', () {
    for (final role in [
      StaffRole.staff,
      StaffRole.cashier,
      StaffRole.packingLead,
    ]) {
      expect(
          menu({role}), contains(AdminShellScreen.roleLandingNavItemId(role)),
          reason: role.name);
    }
  });

  test('effectiveVisibilityRoles: an owner counts as admin, nobody else does',
      () {
    expect(effectiveVisibilityRoles({StaffRole.tenantOwner}),
        {StaffRole.tenantOwner, StaffRole.admin});
    expect(effectiveVisibilityRoles({StaffRole.manager}), {StaffRole.manager});
  });
}
