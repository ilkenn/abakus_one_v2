import '../router/app_routes.dart';

/// 2026-11-12 (Faz 3c) — where a tapped courier-pool push opens (ADR-078).
/// The data keys come from `functions/src/courierNotifications.ts`.
///
/// - `courierPoolRequest` (staff) → the Admin shell's delivery-dispatch
///   board, where the "Havuz Talepleri" panel lives.
/// - `courierAssigned` / `courierReserved` / `courierRequestRejected`
///   (courier) → the staff shell, which opens "Kurye Ekranım" for a
///   courier session.
abstract final class CourierPushTapRouter {
  CourierPushTapRouter._();

  static const courierTypes = {
    'courierPoolRequest',
    'courierAssigned',
    'courierReserved',
    'courierRequestRejected',
  };

  static bool handles(Map<String, dynamic> data) =>
      courierTypes.contains(data['type']);

  static String? resolveRoute(Map<String, dynamic> data) {
    return switch (data['type']) {
      'courierPoolRequest' => '${AppRoutes.admin}?nav=delivery-dispatch',
      'courierAssigned' ||
      'courierReserved' ||
      'courierRequestRejected' =>
        AppRoutes.admin,
      _ => null,
    };
  }
}
