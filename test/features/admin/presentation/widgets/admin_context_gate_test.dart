import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/bootstrap/firebase_ready_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/widgets/admin_context_gate.dart';
import 'package:abakus_one_v2/features/navigation/presentation/providers/current_branch_provider.dart';

/// AP-2 closure correction — the real multi-organization/multi-branch
/// context switcher test matrix. [resolvedActorContextProvider] is
/// overridden directly with a fixed `List<Map<String, dynamic>>` (the
/// exact wire shape `resolveActorContext` itself returns) so every
/// scenario here is deterministic and needs no live Firebase connection —
/// [AdminContextGate] itself is what's under test, not the callable.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required List<Override> overrides,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseReadyProvider.overrideWithValue(true),
          ...overrides,
        ],
        child: const MaterialApp(
          home: AdminContextGate(child: Text('real admin content')),
        ),
      ),
    );
    await tester.pump();
  }

  Override fixedContext(List<Map<String, dynamic>> orgs) {
    return resolvedActorContextProvider.overrideWith((ref) async => orgs);
  }

  testWidgets('Firebase not ready: renders child directly, no gate at all',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [firebaseReadyProvider.overrideWithValue(false)],
        child: const MaterialApp(
          home: AdminContextGate(child: Text('real admin content')),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('real admin content'), findsOneWidget);
  });

  testWidgets('loading state shows a LoadingView', (tester) async {
    // A never-completing Completer, not a Timer-based delay — avoids
    // leaving a pending Timer behind when the test (and its widget tree)
    // finishes before any resolution was ever needed.
    final neverCompletes = Completer<List<Map<String, dynamic>>>();
    addTearDown(() {
      if (!neverCompletes.isCompleted) neverCompletes.complete(const []);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseReadyProvider.overrideWithValue(true),
          resolvedActorContextProvider
              .overrideWith((ref) => neverCompletes.future),
        ],
        child: const MaterialApp(
          home: AdminContextGate(child: Text('real admin content')),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('real admin content'), findsNothing);
  });

  testWidgets('error state shows an ErrorView with a working retry',
      (tester) async {
    var attempt = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseReadyProvider.overrideWithValue(true),
          resolvedActorContextProvider.overrideWith((ref) async {
            attempt += 1;
            if (attempt == 1) throw Exception('network error');
            return [
              {
                'organizationId': 'org-1',
                'roles': ['admin'],
                'branchIds': ['branch-1'],
              },
            ];
          }),
        ],
        child: const MaterialApp(
          home: AdminContextGate(child: Text('real admin content')),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Tekrar Dene'), findsOneWidget);
    expect(find.text('real admin content'), findsNothing);

    await tester.tap(find.text('Tekrar Dene'));
    await tester.pump();
    await tester.pump();

    expect(find.text('real admin content'), findsOneWidget);
  });

  testWidgets(
      'empty organizations (revoked/never-granted) shows a clear "no access" state, never the stale default',
      (tester) async {
    await pump(tester, overrides: [fixedContext(const [])]);

    expect(find.textContaining('erişilebilir bir işletme bulunamadı'),
        findsOneWidget);
    expect(find.text('real admin content'), findsNothing);
  });

  testWidgets(
      'exactly one organization and one branch: auto-selects silently, no picker shown',
      (tester) async {
    final container = ProviderContainer(overrides: [
      firebaseReadyProvider.overrideWithValue(true),
      fixedContext(const [
        {
          'organizationId': 'org-solo',
          'roles': ['admin'],
          'branchIds': ['branch-solo'],
        },
      ]),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AdminContextGate(child: Text('real admin content')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('real admin content'), findsOneWidget);
    expect(container.read(currentOrganizationIdProvider), 'org-solo');
    expect(container.read(currentBranchIdProvider), 'branch-solo');
  });

  testWidgets(
      'multiple organizations: shows an explicit organization picker, never auto-selects',
      (tester) async {
    await pump(tester, overrides: [
      fixedContext(const [
        {
          'organizationId': 'org-a',
          'roles': ['admin'],
          'branchIds': ['branch-a1'],
        },
        {
          'organizationId': 'org-b',
          'roles': ['manager'],
          'branchIds': ['branch-b1'],
        },
      ]),
    ]);

    expect(find.text('İşletme Seçin'), findsOneWidget);
    expect(find.text('org-a'), findsOneWidget);
    expect(find.text('org-b'), findsOneWidget);
    expect(find.text('real admin content'), findsNothing);
  });

  testWidgets(
      'selecting an organization with multiple branches then shows an explicit branch picker',
      (tester) async {
    final container = ProviderContainer(overrides: [
      firebaseReadyProvider.overrideWithValue(true),
      fixedContext(const [
        {
          'organizationId': 'org-multi-branch',
          'roles': ['admin'],
          'branchIds': ['branch-x', 'branch-y'],
        },
      ]),
      currentOrganizationIdProvider.overrideWith((ref) => 'org-multi-branch'),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AdminContextGate(child: Text('real admin content')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Şube Seçin'), findsOneWidget);
    expect(find.text('branch-x'), findsOneWidget);
    expect(find.text('branch-y'), findsOneWidget);
  });

  testWidgets(
      'a revoked organization (previously active, no longer in the real access list) with exactly one remaining option auto-switches to it',
      (tester) async {
    final container = ProviderContainer(overrides: [
      firebaseReadyProvider.overrideWithValue(true),
      fixedContext(const [
        {
          'organizationId': 'org-still-valid',
          'roles': ['admin'],
          'branchIds': ['branch-1'],
        },
      ]),
      // Simulates a stale prior selection for an org this actor no longer has access to.
      currentOrganizationIdProvider.overrideWith((ref) => 'org-revoked'),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AdminContextGate(child: Text('real admin content')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('real admin content'), findsOneWidget);
    expect(container.read(currentOrganizationIdProvider), 'org-still-valid');
  });

  testWidgets(
      'a revoked branch (previously active, no longer in the org\'s real branchIds) with multiple remaining options forces an explicit re-pick — never silently falls back',
      (tester) async {
    final container = ProviderContainer(overrides: [
      firebaseReadyProvider.overrideWithValue(true),
      fixedContext(const [
        {
          'organizationId': 'org-1',
          'roles': ['admin'],
          'branchIds': ['branch-remaining-1', 'branch-remaining-2'],
        },
      ]),
      currentOrganizationIdProvider.overrideWith((ref) => 'org-1'),
      currentBranchIdProvider.overrideWith((ref) => 'branch-revoked'),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AdminContextGate(child: Text('real admin content')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Şube Seçin'), findsOneWidget);
    expect(find.text('real admin content'), findsNothing);
  });

  testWidgets(
      'cross-tenant leakage: content only ever renders once a real, currently-valid org+branch is resolved — an org the actor lost access to never leaks through',
      (tester) async {
    final container = ProviderContainer(overrides: [
      firebaseReadyProvider.overrideWithValue(true),
      fixedContext(const [
        {
          'organizationId': 'org-legit',
          'roles': ['admin'],
          'branchIds': ['branch-legit'],
        },
      ]),
      currentOrganizationIdProvider
          .overrideWith((ref) => 'org-attacker-forged'),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AdminContextGate(child: Text('real admin content')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Auto-corrected to the one real org the actor actually has, never
    // rendering content under the forged/stale selection.
    expect(container.read(currentOrganizationIdProvider), 'org-legit');
    expect(find.text('real admin content'), findsOneWidget);
  });
}
