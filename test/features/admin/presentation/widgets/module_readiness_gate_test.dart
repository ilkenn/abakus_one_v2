import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/presentation/widgets/module_readiness_gate.dart';

/// AP-2 closure correction — every real `AdminShellScreen` nav-item id,
/// copied verbatim from that file's own `_AdminNavItem(id: '...')`
/// literals. Used to assert full coverage: every one of these ids must
/// have a registry entry, and no entry may exist for an id that doesn't.
const List<String> _realAdminShellNavItemIds = [
  'overview',
  'kitchen',
  'reservations',
  'dispatch',
  'orders',
  'pos',
  'cash',
  'customer-360',
  'photo-moderation',
  'customers',
  'loyalty',
  'campaigns',
  'surveys',
  'feedback',
  'menu',
  'staff',
  'branches',
  'devices',
  'setup-templates',
  'menu-import',
  'ingredient-catalog',
  'inventory',
  'stock-counts',
  'recipes',
  'suppliers',
  'reports',
  'audit',
  'localization',
  'settings',
  'entitlements',
  'integrations',
];

void main() {
  group('ModuleReadinessRegistry coverage', () {
    test('every real AdminShellScreen nav-item id has a registry entry', () {
      for (final id in _realAdminShellNavItemIds) {
        expect(
          ModuleReadinessRegistry.registeredModuleIds.contains(id),
          isTrue,
          reason: '"$id" is a real AdminShellScreen destination with no '
              'registry entry',
        );
      }
    });

    test('the registry has no entries for ids that are not real destinations',
        () {
      expect(
        ModuleReadinessRegistry.registeredModuleIds
            .difference(_realAdminShellNavItemIds.toSet()),
        isEmpty,
      );
    });
  });

  group('ModuleReadinessRegistry classification (source-verified)', () {
    test('staff and reservations are the only two productionReady destinations',
        () {
      final productionReady = _realAdminShellNavItemIds.where((id) =>
          ModuleReadinessRegistry.statusOf(id) ==
          ModuleImplementationStatus.productionReady);
      expect(productionReady.toSet(), {'staff', 'reservations'});
    });

    test(
        'photo-moderation, devices, audit, entitlements are classified '
        'partiallyImplementedUnsafe — a real backend exists elsewhere but '
        'these exact screens are not wired to it', () {
      for (final id in [
        'photo-moderation',
        'devices',
        'audit',
        'entitlements',
      ]) {
        expect(
          ModuleReadinessRegistry.classificationOf(id),
          ModuleReadinessClassification.partiallyImplementedUnsafe,
          reason: '"$id" should be partiallyImplementedUnsafe',
        );
        // Still fails closed exactly like demoOnly for the gate's own binary decision.
        expect(
          ModuleReadinessRegistry.statusOf(id),
          ModuleImplementationStatus.demoOnly,
        );
      }
    });

    test(
        'orders, pos, cash, menu, reports are classified notImplemented — '
        'AdminComingSoonView, no working screen exists at all', () {
      for (final id in ['orders', 'pos', 'cash', 'menu', 'reports']) {
        expect(
          ModuleReadinessRegistry.classificationOf(id),
          ModuleReadinessClassification.notImplemented,
          reason: '"$id" should be notImplemented',
        );
      }
    });

    test('stock/CRM/marketplace destinations are all release-gated (demoOnly)',
        () {
      for (final id in [
        'inventory',
        'stock-counts', // stock
        'customers', 'loyalty', 'campaigns', 'surveys', // CRM
        'integrations', // marketplace
      ]) {
        expect(
          ModuleReadinessRegistry.statusOf(id),
          ModuleImplementationStatus.demoOnly,
          reason: '"$id" should be release-gated',
        );
      }
    });

    test(
        'an unregistered/unknown module id fails closed to demoOnly, never productionReady',
        () {
      expect(
        ModuleReadinessRegistry.statusOf(
            'someUnrelatedModuleIdNeverRegistered'),
        ModuleImplementationStatus.demoOnly,
      );
      expect(
        ModuleReadinessRegistry.classificationOf(
            'someUnrelatedModuleIdNeverRegistered'),
        ModuleReadinessClassification.notImplemented,
      );
    });
  });

  group('ModuleReadinessGate', () {
    testWidgets(
        'a productionReady module (staff) renders its child directly, with no DEMO badge',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ModuleReadinessGate(
            moduleId: 'staff',
            child: Text('real content'),
          ),
        ),
      );

      expect(find.text('real content'), findsOneWidget);
      expect(find.text('DEMO'), findsNothing);
    });

    testWidgets(
        'a demoOnly module remains reachable in a debug/test build, but is clearly labeled DEMO',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ModuleReadinessGate(
            moduleId: 'pos',
            child: Text('pos screen content'),
          ),
        ),
      );

      // kReleaseMode is always false under `flutter test` — this exercises
      // the debug-mode branch (visible DEMO badge, module still reachable),
      // never the release fail-closed branch, which is a compile-time
      // (kReleaseMode) constant this test harness cannot flip.
      expect(find.text('pos screen content'), findsOneWidget);
      expect(find.text('DEMO'), findsOneWidget);
    });

    testWidgets(
        'an unregistered module id also gets the DEMO badge in debug — fails closed, never silently visible',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ModuleReadinessGate(
            moduleId: 'someBrandNewDestinationNobodyRegisteredYet',
            child: Text('new screen content'),
          ),
        ),
      );

      expect(find.text('new screen content'), findsOneWidget);
      expect(find.text('DEMO'), findsOneWidget);
    });
  });
}
