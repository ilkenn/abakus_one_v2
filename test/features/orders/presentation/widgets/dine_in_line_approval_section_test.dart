import 'package:abakus_one_v2/features/orders/application/use_cases/submit_customer_order.dart';
import 'package:abakus_one_v2/features/orders/data/canonical_order_repository.dart';
import 'package:abakus_one_v2/features/orders/data/dine_in_counter_proposal_gateway.dart';
import 'package:abakus_one_v2/features/orders/domain/identity/order_identity.dart';
import 'package:abakus_one_v2/features/orders/domain/models/dine_in_counter_proposal.dart';
import 'package:abakus_one_v2/features/orders/domain/models/dine_in_line_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_line_approval_state.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/dine_in_counter_proposal_dependencies_provider.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/orders_provider.dart';
import 'package:abakus_one_v2/features/orders/presentation/widgets/dine_in_line_approval_section.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../pos/test_support/fake_clock.dart';

class _FakeDineInCounterProposalGateway
    implements DineInCounterProposalGateway {
  int callCount = 0;
  bool? lastAccept;
  int? lastLineIndex;
  RespondToDineInCounterProposalException? errorToThrow;

  @override
  Future<RespondToDineInCounterProposalResult> respond({
    required String orderId,
    required int lineIndex,
    required bool accept,
  }) async {
    callCount += 1;
    lastAccept = accept;
    lastLineIndex = lineIndex;
    final error = errorToThrow;
    if (error != null) throw error;
    return RespondToDineInCounterProposalResult(
      orderId: orderId,
      lineIndex: lineIndex,
      status: accept ? 'accepted' : 'rejected',
      idempotent: false,
    );
  }
}

Future<Order> _buildDineInOrder({
  required InMemoryCanonicalOrderRepository repository,
}) async {
  return SubmitCustomerOrder(
    clock: FakeClock(DateTime(2026, 8, 5, 18, 30)),
    identityProvider: InMemoryOrderIdentityProvider(),
    repository: repository,
    branchId: 'branch-1',
    restaurantId: 'restaurant-1',
  ).call(
    cartItems: const [
      CartItem(
          id: 'p1', name: 'Klasik Bowl', desc: '', price: 100.0, quantity: 1),
    ],
    customerId: 'uid-1',
    channel: OrderChannel.dineInQr,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required InMemoryCanonicalOrderRepository repository,
  required String orderId,
  required OrderChannel channel,
  required _FakeDineInCounterProposalGateway gateway,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        canonicalOrderRepositoryProvider.overrideWithValue(repository),
        dineInCounterProposalGatewayProvider.overrideWithValue(gateway),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: DineInLineApprovalSection(orderId: orderId, channel: channel),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'renders nothing for a non-dineInQr channel',
    (tester) async {
      final repository = InMemoryCanonicalOrderRepository();
      final order = await _buildDineInOrder(repository: repository);
      await repository.submitOrder(order);

      await _pump(
        tester,
        repository: repository,
        orderId: order.id.value,
        channel: OrderChannel.takeaway,
        gateway: _FakeDineInCounterProposalGateway(),
      );

      expect(find.byType(DineInLineApprovalSection), findsOneWidget);
      expect(find.textContaining('Onay bekliyor'), findsNothing);
    },
  );

  testWidgets(
    'renders nothing once every line is accepted (nothing needs attention)',
    (tester) async {
      final repository = InMemoryCanonicalOrderRepository();
      final order = await _buildDineInOrder(repository: repository);
      await repository.submitOrder(order);

      await _pump(
        tester,
        repository: repository,
        orderId: order.id.value,
        channel: OrderChannel.dineInQr,
        gateway: _FakeDineInCounterProposalGateway(),
      );

      expect(find.textContaining('Onay bekliyor'), findsNothing);
      expect(find.textContaining('Değişiklik Önerisi'), findsNothing);
    },
  );

  testWidgets(
    'shows a pendingApproval notice chip for a line awaiting cashier decision',
    (tester) async {
      final repository = InMemoryCanonicalOrderRepository();
      final order = await _buildDineInOrder(repository: repository);
      final withState = order.copyWith(lineApprovalStates: const [
        OrderLineApprovalState(
          lineIndex: 0,
          status: DineInLineStatus.pendingApproval,
        ),
      ]);
      await repository.submitOrder(withState);

      await _pump(
        tester,
        repository: repository,
        orderId: order.id.value,
        channel: OrderChannel.dineInQr,
        gateway: _FakeDineInCounterProposalGateway(),
      );

      expect(find.text('Onay bekliyor'), findsOneWidget);
      expect(find.text('Klasik Bowl'), findsOneWidget);
    },
  );

  testWidgets(
    'shows a full counter-proposal card with Kabul Et/Reddet for a '
    'proposedChange line, and Kabul Et calls the gateway with accept:true',
    (tester) async {
      final repository = InMemoryCanonicalOrderRepository();
      final order = await _buildDineInOrder(repository: repository);
      final proposal = DineInCounterProposal(
        proposalVersion: 1,
        proposedProductId: 'p2',
        proposedProductName: 'Vegan Bowl',
        proposedModifiers: const [],
        proposedQuantity: 1,
        proposedUnitPrice: Money.fromWhole(80, Currency.tryLira),
        proposedLineTotal: Money.fromWhole(80, Currency.tryLira),
        differenceFromOriginal: Money.fromWhole(-20, Currency.tryLira),
        reasonCode: 'outOfStock',
        reasonMessage: 'Seçtiğiniz ürün tükendi, bu ürünü öneriyoruz.',
        proposedByStaffUid: 'staff-uid-1',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        status: DineInCounterProposalStatus.pending,
      );
      final withProposal = order.copyWith(lineApprovalStates: [
        OrderLineApprovalState(
          lineIndex: 0,
          status: DineInLineStatus.proposedChange,
          counterProposal: proposal,
        ),
      ]);
      await repository.submitOrder(withProposal);

      final gateway = _FakeDineInCounterProposalGateway();
      await _pump(
        tester,
        repository: repository,
        orderId: order.id.value,
        channel: OrderChannel.dineInQr,
        gateway: gateway,
      );

      expect(find.text('Değişiklik Önerisi'), findsOneWidget);
      expect(find.textContaining('Vegan Bowl'), findsOneWidget);
      expect(find.text('Seçtiğiniz ürün tükendi, bu ürünü öneriyoruz.'),
          findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Kabul Et'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Reddet'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Kabul Et'));
      await tester.pumpAndSettle();

      expect(gateway.callCount, 1);
      expect(gateway.lastAccept, true);
      expect(gateway.lastLineIndex, 0);
    },
  );

  testWidgets(
    'Reddet calls the gateway with accept:false',
    (tester) async {
      final repository = InMemoryCanonicalOrderRepository();
      final order = await _buildDineInOrder(repository: repository);
      final proposal = DineInCounterProposal(
        proposalVersion: 1,
        proposedProductId: 'p2',
        proposedProductName: 'Vegan Bowl',
        proposedModifiers: const [],
        proposedQuantity: 1,
        proposedUnitPrice: Money.fromWhole(80, Currency.tryLira),
        proposedLineTotal: Money.fromWhole(80, Currency.tryLira),
        differenceFromOriginal: Money.fromWhole(-20, Currency.tryLira),
        reasonCode: 'outOfStock',
        reasonMessage: 'Seçtiğiniz ürün tükendi.',
        proposedByStaffUid: 'staff-uid-1',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        status: DineInCounterProposalStatus.pending,
      );
      final withProposal = order.copyWith(lineApprovalStates: [
        OrderLineApprovalState(
          lineIndex: 0,
          status: DineInLineStatus.proposedChange,
          counterProposal: proposal,
        ),
      ]);
      await repository.submitOrder(withProposal);

      final gateway = _FakeDineInCounterProposalGateway();
      await _pump(
        tester,
        repository: repository,
        orderId: order.id.value,
        channel: OrderChannel.dineInQr,
        gateway: gateway,
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Reddet'));
      await tester.pumpAndSettle();

      expect(gateway.callCount, 1);
      expect(gateway.lastAccept, false);
    },
  );

  testWidgets(
    'a gateway rejection shows the server error message, not a crash',
    (tester) async {
      final repository = InMemoryCanonicalOrderRepository();
      final order = await _buildDineInOrder(repository: repository);
      final proposal = DineInCounterProposal(
        proposalVersion: 2,
        proposedProductId: 'p2',
        proposedProductName: 'Vegan Bowl',
        proposedModifiers: const [],
        proposedQuantity: 1,
        proposedUnitPrice: Money.fromWhole(80, Currency.tryLira),
        proposedLineTotal: Money.fromWhole(80, Currency.tryLira),
        differenceFromOriginal: Money.fromWhole(-20, Currency.tryLira),
        reasonCode: 'outOfStock',
        reasonMessage: 'Seçtiğiniz ürün tükendi.',
        proposedByStaffUid: 'staff-uid-1',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        status: DineInCounterProposalStatus.pending,
      );
      final withProposal = order.copyWith(lineApprovalStates: [
        OrderLineApprovalState(
          lineIndex: 0,
          status: DineInLineStatus.proposedChange,
          counterProposal: proposal,
        ),
      ]);
      await repository.submitOrder(withProposal);

      final gateway = _FakeDineInCounterProposalGateway()
        ..errorToThrow = const RespondToDineInCounterProposalException(
          'aborted',
          'Bu öneri artık geçerli değil.',
        );
      await _pump(
        tester,
        repository: repository,
        orderId: order.id.value,
        channel: OrderChannel.dineInQr,
        gateway: gateway,
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Kabul Et'));
      await tester.pumpAndSettle();

      expect(find.text('Bu öneri artık geçerli değil.'), findsOneWidget);
    },
  );
}
