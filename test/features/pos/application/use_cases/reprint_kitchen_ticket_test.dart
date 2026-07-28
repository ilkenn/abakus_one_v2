import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/reprint_kitchen_ticket.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_ticket_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_header.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_print_provider.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_pos_authorization_policy.dart';

void main() {
  test('reprints a ticket marked as a copy when authorized', () async {
    final repository = InMemoryKitchenTicketRepository();
    await repository.save(KitchenTicket(
      id: 'ticket-1',
      orderId: OrderId('order-1'),
      branchId: 'branch-1',
      type: KitchenTicketType.initial,
      header: KitchenTicketHeader(
        restaurantName: 'Abaküs',
        branchName: 'Kadıköy',
        channelLabel: 'Masa',
        orderNumber: 'A-001',
        orderTypeLabel: 'Masa',
        receivedAt: DateTime(2026, 7, 29),
      ),
      lines: const [],
      firedAt: DateTime(2026, 7, 29),
      revision: 1,
    ));
    final useCase = ReprintKitchenTicket(
      authorizationPolicy:
          FakePosAuthorizationPolicy(const AuthorizationResult(granted: true)),
      repository: repository,
      printProvider: const NoOpKitchenTicketPrintProvider(),
    );

    final result =
        await useCase(ticketId: 'ticket-1', performedByStaffId: 'staff-1');

    expect(result.isCopy, isTrue);
    expect(result.revision, 2);
  });

  test('throws AuthorizationDeniedViolation when denied', () async {
    final repository = InMemoryKitchenTicketRepository();
    await repository.save(KitchenTicket(
      id: 'ticket-1',
      orderId: OrderId('order-1'),
      branchId: 'branch-1',
      type: KitchenTicketType.initial,
      header: KitchenTicketHeader(
        restaurantName: 'Abaküs',
        branchName: 'Kadıköy',
        channelLabel: 'Masa',
        orderNumber: 'A-001',
        orderTypeLabel: 'Masa',
        receivedAt: DateTime(2026, 7, 29),
      ),
      lines: const [],
      firedAt: DateTime(2026, 7, 29),
      revision: 1,
    ));
    final useCase = ReprintKitchenTicket(
      authorizationPolicy:
          FakePosAuthorizationPolicy(const AuthorizationResult(granted: false)),
      repository: repository,
      printProvider: const NoOpKitchenTicketPrintProvider(),
    );

    expect(
      () => useCase(ticketId: 'ticket-1', performedByStaffId: 'staff-1'),
      throwsA(isA<AuthorizationDeniedViolation>()),
    );
  });
}
