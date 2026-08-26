import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/presentation/widgets/module_readiness_gate.dart';

void main() {
  group('ModuleReadinessRegistry', () {
    test('a not-yet-backend-wired module id resolves demoOnly', () {
      expect(
        ModuleReadinessRegistry.statusOf('pos'),
        ModuleImplementationStatus.demoOnly,
      );
      expect(
        ModuleReadinessRegistry.statusOf('marketplace'),
        ModuleImplementationStatus.demoOnly,
      );
    });

    test('an id not in the demo-only set resolves productionReady', () {
      expect(
        ModuleReadinessRegistry.statusOf('someUnrelatedModuleId'),
        ModuleImplementationStatus.productionReady,
      );
    });
  });

  group('ModuleReadinessGate', () {
    testWidgets(
        'a productionReady module renders its child directly, with no DEMO badge',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ModuleReadinessGate(
            moduleId: 'someUnrelatedModuleId',
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
  });
}
