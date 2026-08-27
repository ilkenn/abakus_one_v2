import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/presentation/widgets/module_readiness_gate.dart';

/// AP-2 final wiring — every real `AdminShellScreen` nav-item id, copied
/// verbatim from that file's own `_AdminNavItem(id: '...')` literals. Used
/// to assert full coverage: every one of these ids must have a registry
/// entry, and no entry may exist for an id that doesn't. Unchanged from the
/// prior AP-2 closure correction — the destination COUNT stays 31/31; only
/// the two devices/entitlements wired this pass changed classification.
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

    test('exactly 31 registered destinations — the count stays 31/31', () {
      expect(ModuleReadinessRegistry.registeredModuleIds.length, 31);
      expect(_realAdminShellNavItemIds.length, 31);
    });
  });

  group('ModuleImplementationMaturity classification (source-verified)', () {
    test(
        'staff and reservations are the only two implementationComplete destinations',
        () {
      final complete = _realAdminShellNavItemIds.where((id) =>
          ModuleReadinessRegistry.readinessOf(id).maturity ==
          ModuleImplementationMaturity.implementationComplete);
      expect(complete.toSet(), {'staff', 'reservations'});
    });

    test(
        'devices and entitlements reached backendWiredEmulatorVerified this pass — real backend, real wiring, not yet full polish',
        () {
      for (final id in ['devices', 'entitlements']) {
        expect(
          ModuleReadinessRegistry.readinessOf(id).maturity,
          ModuleImplementationMaturity.backendWiredEmulatorVerified,
          reason: '"$id" should be backendWiredEmulatorVerified',
        );
      }
    });

    test(
        'photo-moderation and audit remain partiallyImplementedUnsafe — a real backend exists elsewhere but these exact viewer screens are not wired to it (disclosed AP-3+ scope)',
        () {
      for (final id in ['photo-moderation', 'audit']) {
        expect(
          ModuleReadinessRegistry.readinessOf(id).maturity,
          ModuleImplementationMaturity.partiallyImplementedUnsafe,
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
          ModuleReadinessRegistry.readinessOf(id).maturity,
          ModuleImplementationMaturity.notImplemented,
          reason: '"$id" should be notImplemented',
        );
        expect(
          ModuleReadinessRegistry.readinessOf(id).deployment,
          ModuleDeploymentAvailability.disabled,
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
        'an unregistered/unknown module id fails closed to notImplemented/disabled, never productionReady',
        () {
      expect(
        ModuleReadinessRegistry.statusOf(
            'someUnrelatedModuleIdNeverRegistered'),
        ModuleImplementationStatus.demoOnly,
      );
      final readiness = ModuleReadinessRegistry.readinessOf(
          'someUnrelatedModuleIdNeverRegistered');
      expect(readiness.maturity, ModuleImplementationMaturity.notImplemented);
      expect(readiness.deployment, ModuleDeploymentAvailability.disabled);
    });
  });

  group(
      'deployment-availability axis — release/deployment readiness consistency',
      () {
    test(
        'no destination is ever ModuleDeploymentAvailability.production or .staging — nothing is deployed anywhere yet (CLAUDE.md §5)',
        () {
      for (final id in _realAdminShellNavItemIds) {
        final deployment = ModuleReadinessRegistry.readinessOf(id).deployment;
        expect(
          deployment,
          isNot(ModuleDeploymentAvailability.production),
          reason: '"$id" must not claim production deployment before AP-8',
        );
        expect(deployment, isNot(ModuleDeploymentAvailability.staging));
      }
    });

    test(
        'every destination resolves demoOnly (release-gated) today, including implementationComplete ones — maturity alone can never clear the gate without production deployment',
        () {
      for (final id in _realAdminShellNavItemIds) {
        expect(
          ModuleReadinessRegistry.statusOf(id),
          ModuleImplementationStatus.demoOnly,
          reason:
              '"$id" must stay release-gated: deployment availability is never production pre-AP-8',
        );
      }
    });
  });

  group('ModuleReadinessGate', () {
    testWidgets(
        'an implementationComplete module (staff) renders its child directly in dev/test builds, with no DEMO badge',
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
        'a backendWiredEmulatorVerified module (devices) renders its child directly in dev/test builds, with no DEMO badge',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ModuleReadinessGate(
            moduleId: 'devices',
            child: Text('devices screen content'),
          ),
        ),
      );

      expect(find.text('devices screen content'), findsOneWidget);
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
