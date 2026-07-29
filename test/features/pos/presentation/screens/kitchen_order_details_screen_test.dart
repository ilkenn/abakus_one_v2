import 'package:abakus_one_v2/features/pos/data/kitchen_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_projection_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_ticket_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kds_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kitchen_ticket_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/kitchen_order_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_pos_authorization_policy.dart';
import '../../test_support/kds_test_fixtures.dart';

void main() {
  Future<InMemoryKitchenProjectionRepository> pumpScreen(
    WidgetTester tester, {
    AuthorizationResult? authorization,
  }) async {
    final ticketRepository = InMemoryKitchenTicketRepository();
    await ticketRepository.save(buildTestKitchenTicket());
    final projectionRepository = InMemoryKitchenProjectionRepository();
    await projectionRepository.save(buildTestKitchenWorkItem());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kitchenTicketRepositoryProvider.overrideWithValue(ticketRepository),
          kitchenProjectionRepositoryProvider
              .overrideWithValue(projectionRepository),
          kitchenAuditEntryRepositoryProvider
              .overrideWithValue(InMemoryKitchenAuditEntryRepository()),
        ],
        child: MaterialApp(
          home: KitchenOrderDetailsScreen(
            kitchenTicketId: 'ticket-1',
            authorizationPolicy: authorization == null
                ? null
                : FakePosAuthorizationPolicy(authorization),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return projectionRepository;
  }

  testWidgets('shows the line and its current status', (tester) async {
    await pumpScreen(tester);

    expect(find.textContaining('Ürün 0'), findsOneWidget);
    expect(find.textContaining('queued'), findsOneWidget);
  });

  testWidgets('advancing the line calls TransitionKitchenWorkItem',
      (tester) async {
    final projectionRepository = await pumpScreen(tester,
        authorization: const AuthorizationResult(granted: true));

    await tester.tap(find.widgetWithText(ElevatedButton, 'İlerlet'));
    await tester.pumpAndSettle();

    final item = await projectionRepository.findById('work-1');
    expect(item!.status, KitchenLineStatus.acknowledged);
  });

  testWidgets(
      'without an authorization policy, advancing surfaces a '
      'message', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'İlerlet'));
    await tester.pumpAndSettle();

    expect(find.text('Yetki politikası tanımlı değil.'), findsOneWidget);
  });
}
