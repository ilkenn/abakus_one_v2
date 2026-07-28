import 'package:abakus_one_v2/core/utils/clock_provider.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/restaurant/data/channel_operation_policy_repository.dart';
import 'package:abakus_one_v2/features/restaurant/data/restaurant_operations_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/restaurant/domain/models/channel_operational_state.dart';
import 'package:abakus_one_v2/features/restaurant/presentation/providers/restaurant_operations_dependencies_provider.dart';
import 'package:abakus_one_v2/features/restaurant/presentation/screens/channel_operation_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../pos/test_support/fake_clock.dart';
import '../../../pos/test_support/fake_pos_authorization_policy.dart';

void main() {
  Future<
      ({
        InMemoryChannelOperationPolicyRepository policyRepository,
      })> pumpScreen(
    WidgetTester tester, {
    required AuthorizationResult emergencyAuthorization,
  }) async {
    // Every channel card must be simultaneously reachable without scrolling
    // (a plain ListView only builds elements within its cache extent) — a
    // tall viewport is simpler and more robust here than scrolling each
    // assertion into view individually.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final policyRepository = InMemoryChannelOperationPolicyRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 7, 29))),
          channelOperationPolicyRepositoryProvider
              .overrideWithValue(policyRepository),
          restaurantOperationsAuditEntryRepositoryProvider.overrideWithValue(
              InMemoryRestaurantOperationsAuditEntryRepository()),
        ],
        child: MaterialApp(
          home: ChannelOperationSettingsScreen(
            branchId: 'branch-1',
            authorizationPolicy:
                FakePosAuthorizationPolicy(emergencyAuthorization),
            staffId: 'staff-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (policyRepository: policyRepository);
  }

  testWidgets('shows a card per order channel, defaulting to open/automatic',
      (tester) async {
    await pumpScreen(
      tester,
      emergencyAuthorization: const AuthorizationResult(granted: true),
    );

    for (final channel in OrderChannel.values) {
      expect(find.text(channel.name), findsOneWidget);
    }
  });

  testWidgets('tapping a busy chip updates the channel operational state',
      (tester) async {
    final repos = await pumpScreen(
      tester,
      emergencyAuthorization: const AuthorizationResult(granted: true),
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'busy').first);
    await tester.pumpAndSettle();

    final policy = await repos.policyRepository
        .findCurrent('branch-1', OrderChannel.dineInQr);
    expect(policy!.operationalState, ChannelOperationalState.busy);
  });

  testWidgets('emergency stop succeeds when authorized', (tester) async {
    final repos = await pumpScreen(
      tester,
      emergencyAuthorization: const AuthorizationResult(granted: true),
    );

    await tester
        .tap(find.widgetWithText(ElevatedButton, 'Teslimatı Acil Durdur'));
    await tester.pumpAndSettle();

    expect(find.textContaining('acil durduruldu'), findsOneWidget);
    final policy = await repos.policyRepository
        .findCurrent('branch-1', OrderChannel.delivery);
    expect(policy!.operationalState, ChannelOperationalState.emergencyClosed);
  });

  testWidgets('emergency stop shows a denial message when not authorized',
      (tester) async {
    await pumpScreen(
      tester,
      emergencyAuthorization:
          const AuthorizationResult(granted: false, reason: 'Yetkisiz'),
    );

    await tester
        .tap(find.widgetWithText(ElevatedButton, 'Teslimatı Acil Durdur'));
    await tester.pumpAndSettle();

    expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
  });
}
