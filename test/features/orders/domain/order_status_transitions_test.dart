import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';

void main() {
  test('OrderStatus beklenen tum durumlari icerir', () {
    expect(OrderStatus.values, [
      OrderStatus.created,
      OrderStatus.pendingConfirmation,
      OrderStatus.confirmed,
      OrderStatus.preparing,
      OrderStatus.ready,
      OrderStatus.outForDelivery,
      OrderStatus.served,
      OrderStatus.completed,
      OrderStatus.cancelled,
      OrderStatus.rejected,
      OrderStatus.refunded,
      // AP-6 Sprint 1.
      OrderStatus.scheduled,
      // AP-6 Sprint 3.
      OrderStatus.readyForPickup,
    ]);
  });

  group('gecerli gecisler', () {
    const validTransitions = [
      [OrderStatus.created, OrderStatus.pendingConfirmation],
      [OrderStatus.created, OrderStatus.cancelled],
      [OrderStatus.created, OrderStatus.rejected],
      [OrderStatus.pendingConfirmation, OrderStatus.confirmed],
      [OrderStatus.pendingConfirmation, OrderStatus.rejected],
      [OrderStatus.confirmed, OrderStatus.preparing],
      [OrderStatus.preparing, OrderStatus.ready],
      [OrderStatus.ready, OrderStatus.outForDelivery],
      [OrderStatus.ready, OrderStatus.served],
      [OrderStatus.ready, OrderStatus.completed],
      [OrderStatus.outForDelivery, OrderStatus.served],
      [OrderStatus.served, OrderStatus.completed],
      [OrderStatus.completed, OrderStatus.refunded],
      // AP-6 Sprint 1.
      [OrderStatus.scheduled, OrderStatus.confirmed],
      [OrderStatus.scheduled, OrderStatus.rejected],
      [OrderStatus.scheduled, OrderStatus.cancelled],
      // AP-6 Sprint 3.
      [OrderStatus.readyForPickup, OrderStatus.outForDelivery],
      [OrderStatus.readyForPickup, OrderStatus.cancelled],
      [OrderStatus.readyForPickup, OrderStatus.rejected],
    ];

    for (final pair in validTransitions) {
      test('${pair[0].name} -> ${pair[1].name} gecerlidir', () {
        expect(OrderStatusTransitions.canTransition(pair[0], pair[1]), isTrue);
      });
    }
  });

  group('gecersiz gecisler', () {
    const invalidTransitions = [
      // Terminal durumlardan cikis olamaz.
      [OrderStatus.cancelled, OrderStatus.pendingConfirmation],
      [OrderStatus.rejected, OrderStatus.confirmed],
      [OrderStatus.refunded, OrderStatus.completed],
      // Asamalar atlanamaz.
      [OrderStatus.created, OrderStatus.preparing],
      [OrderStatus.confirmed, OrderStatus.ready],
      [OrderStatus.pendingConfirmation, OrderStatus.preparing],
      // Servis edilmis siparis artik iptal edilemez (iade akisina gider).
      [OrderStatus.served, OrderStatus.cancelled],
      [OrderStatus.completed, OrderStatus.cancelled],
      // Geriye donus olamaz.
      [OrderStatus.preparing, OrderStatus.confirmed],
      [OrderStatus.ready, OrderStatus.preparing],
      // scheduled asamalari atlayamaz (AP-6 Sprint 1).
      [OrderStatus.scheduled, OrderStatus.preparing],
      [OrderStatus.scheduled, OrderStatus.ready],
      // readyForPickup asamalari atlayamaz (AP-6 Sprint 3) — kendi mutfagimiz
      // bu siparisi hic gormedigi icin preparing/ready gecisi olamaz.
      [OrderStatus.readyForPickup, OrderStatus.preparing],
      [OrderStatus.readyForPickup, OrderStatus.ready],
    ];

    for (final pair in invalidTransitions) {
      test('${pair[0].name} -> ${pair[1].name} gecersizdir', () {
        expect(
          OrderStatusTransitions.canTransition(pair[0], pair[1]),
          isFalse,
        );
      });
    }

    test('bir duruma kendisine gecis gecersizdir', () {
      expect(
        OrderStatusTransitions.canTransition(
          OrderStatus.confirmed,
          OrderStatus.confirmed,
        ),
        isFalse,
      );
    });
  });

  group('terminal durumlar', () {
    test('cancelled/rejected/refunded terminaldir', () {
      expect(OrderStatusTransitions.isTerminal(OrderStatus.cancelled), isTrue);
      expect(OrderStatusTransitions.isTerminal(OrderStatus.rejected), isTrue);
      expect(OrderStatusTransitions.isTerminal(OrderStatus.refunded), isTrue);
    });

    test('created/confirmed/preparing terminal degildir', () {
      expect(OrderStatusTransitions.isTerminal(OrderStatus.created), isFalse);
      expect(
        OrderStatusTransitions.isTerminal(OrderStatus.confirmed),
        isFalse,
      );
      expect(
        OrderStatusTransitions.isTerminal(OrderStatus.preparing),
        isFalse,
      );
    });
  });

  test('allowedNextStates gecerli hedef kumesini doner', () {
    expect(
      OrderStatusTransitions.allowedNextStates(OrderStatus.ready),
      {
        OrderStatus.outForDelivery,
        OrderStatus.served,
        OrderStatus.completed,
        OrderStatus.cancelled,
      },
    );
    expect(
      OrderStatusTransitions.allowedNextStates(OrderStatus.cancelled),
      isEmpty,
    );
  });
}
