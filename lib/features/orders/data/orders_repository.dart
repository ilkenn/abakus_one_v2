import '../domain/models/order_item_snapshot.dart';
import '../domain/models/order_model.dart';
import '../domain/models/order_status.dart';

/// Source of an authenticated customer's orders.
///
/// `OrdersNotifier` depends only on this interface, never on
/// [LocalOrdersRepository] directly — swapping in a real backend later
/// (a REST/GraphQL-backed implementation) means writing one new class and
/// changing `ordersRepositoryProvider`'s single override; nothing in the
/// notifier, providers, or UI has to change.
abstract class OrdersRepository {
  /// The orders to seed app state with on startup. A real implementation
  /// would fetch the signed-in customer's orders from a backend; today
  /// there is no backend, so [LocalOrdersRepository] returns fixed demo
  /// data instead — see its own doc comment.
  List<OrderModel> loadInitialOrders();
}

/// Explicitly local/mock [OrdersRepository] — the only implementation that
/// exists today, since there is no backend yet. Returns a fixed set of
/// demo orders spanning every terminal/non-terminal customer-facing state
/// (pending, preparing, delivered, cancelled) so the order-history and
/// active-order-tracking screens have something realistic to render without
/// requiring a fresh checkout first.
///
/// This class — not `OrdersNotifier` — is where that demo data lives, so
/// the notifier itself stays backend-agnostic (see [OrdersRepository]).
class LocalOrdersRepository implements OrdersRepository {
  const LocalOrdersRepository();

  @override
  List<OrderModel> loadInitialOrders() {
    return const [
      OrderModel(
        id: 'ORD-2026-001',
        date: '12.07.2026',
        totalAmount: 194.0,
        status: 'Teslim Edildi',
        lifecycleStatus: OrderStatus.completed,
        orderNote: 'Lütfen acı sosu bol olsun.',
        serviceMaterialsPreference: 'Malzeme İstemiyor',
        deliveryTimingType: 'immediate',
        estimatedMinutes: 35,
        items: [
          OrderItemSnapshot(
            productId: 'prod_mexifit_bowl',
            productName: 'Mexifit Bowl',
            quantity: 1,
            unitPrice: 194.0,
          ),
        ],
        overallRating: 5,
        tasteRating: 5,
        packagingRating: 4,
        deliveryRating: 5,
        reviewComment: 'Çok lezzetliydi, teşekkürler!',
        reviewedAt: '13.07.2026',
        courierRating: 5,
        courierWasPolite: true,
        courierWasOnTime: true,
        courierCommunicationWasGood: true,
        packageWasHandledCarefully: true,
        courierReviewComment: 'Hızlı ve nazik kurye.',
      ),
      OrderModel(
        id: 'ORD-2026-002',
        date: '15.07.2026',
        totalAmount: 265.0,
        status: 'Hazırlanıyor',
        lifecycleStatus: OrderStatus.preparing,
        orderNote: 'Zile basmayın lütfen, bebek uyuyor.',
        ringBell: false,
        leaveAtDoor: true,
        leaveAtDoorLocation: 'Kapının önü',
        serviceMaterialsPreference: 'Malzeme İstiyor',
        deliveryTimingType: 'immediate',
        estimatedMinutes: 30,
        items: [
          OrderItemSnapshot(
            productId: 'prod_falafel_bowl',
            productName: 'Falafel Bowl',
            quantity: 2,
            unitPrice: 132.5,
          ),
        ],
      ),
      OrderModel(
        id: 'ORD-2026-003',
        date: '18.07.2026',
        totalAmount: 310.0,
        status: 'Onay Bekliyor',
        lifecycleStatus: OrderStatus.pendingConfirmation,
        orderNote: 'Bahçe katı girişindeyim.',
        serviceMaterialsPreference: 'Malzeme İstemiyor',
        deliveryTimingType: 'scheduled',
        scheduledDeliveryDateTime: '19.07.2026 14:30',
        estimatedMinutes: 40,
        items: [
          OrderItemSnapshot(
            productId: 'prod_abakus_burger',
            productName: 'Abaküs Burger',
            quantity: 1,
            unitPrice: 310.0,
          ),
        ],
      ),
    ];
  }
}
