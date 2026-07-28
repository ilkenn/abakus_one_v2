import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/domain/mappers/cart_to_order_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/pos/application/identity/kitchen_ticket_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/fire_kitchen_ticket.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_ticket_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_print_provider.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_type.dart';
import 'package:abakus_one_v2/features/pos/domain/receipts/receipt_print_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

class _RecordingPrintProvider implements KitchenTicketPrintProvider {
  int printCount = 0;

  @override
  Future<ReceiptPrintResult> print(KitchenTicket ticket) async {
    printCount += 1;
    return const ReceiptPrintResult(status: ReceiptPrintResultStatus.success);
  }
}

void main() {
  test('builds, persists, and attempts to print a new ticket', () async {
    final order = CartToOrderMapper.map(
      orderId: OrderId('order-1'),
      orderNumber: OrderNumber('A-001'),
      cartItems: const [
        CartItem(
            id: 'p1',
            name: 'Mexifit Bowl',
            desc: '',
            price: 194.0,
            quantity: 1),
      ],
      channel: OrderChannel.dineInStaff,
      branchId: 'branch-1',
      restaurantId: 'restaurant-abakus',
      now: DateTime(2026, 7, 29),
    );
    final repository = InMemoryKitchenTicketRepository();
    final printProvider = _RecordingPrintProvider();
    final useCase = FireKitchenTicket(
      clock: FakeClock(DateTime(2026, 7, 29, 12)),
      idGenerator: SequentialKitchenTicketIdGenerator(),
      repository: repository,
      printProvider: printProvider,
    );

    final ticket = await useCase(
      order: order,
      type: KitchenTicketType.initial,
      restaurantName: 'Abaküs',
      branchName: 'Kadıköy',
    );

    expect(await repository.findById(ticket.id), ticket);
    expect(printProvider.printCount, 1);
  });
}
