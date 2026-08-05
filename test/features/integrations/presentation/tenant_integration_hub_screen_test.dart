import 'package:abakus_one_v2/features/integrations/presentation/screens/tenant_integration_hub_screen.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/actor_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/integration_test_fixtures.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // BuildProviderHealthProjection/BuildIntegrationAuditCenterProjection
          // now independently authorize themselves (Phase 8 closure sprint)
          // via the real posAuthorizationPolicyProvider — override it here
          // the same way the screen's own write-path AllowAllIntegrationPolicy
          // already permits everything, so the read path isn't denied by
          // the default "no active session" policy.
          posAuthorizationPolicyProvider
              .overrideWithValue(const AllowAllIntegrationPolicy()),
        ],
        child: const MaterialApp(
          home: TenantIntegrationHubScreen(
            organizationId: 'org-1',
            authorizationPolicy: AllowAllIntegrationPolicy(),
            performedByStaffId: 'staff-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists every registered provider, initially disabled',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Yemeksepeti'), findsOneWidget);
    expect(find.text('iyzico'), findsOneWidget);
    expect(find.byType(Switch), findsWidgets);
  });

  testWidgets('toggling a provider enables it and records an audit entry',
      (tester) async {
    await pumpScreen(tester);

    final switchFinder = find.byType(Switch).first;
    expect(tester.widget<Switch>(switchFinder).value, isFalse);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);

    await tester.dragUntilVisible(
      find.textContaining('enabled for organization'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    expect(find.textContaining('enabled for organization'), findsOneWidget);
  });

  testWidgets('shows an empty state when there is no recent activity yet',
      (tester) async {
    await pumpScreen(tester);

    await tester.dragUntilVisible(
      find.text('Henüz bir entegrasyon etkinliği yok.'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    expect(find.text('Henüz bir entegrasyon etkinliği yok.'), findsOneWidget);
  });
}
