# Abaküs — Feature Status

Durum değerleri:

```text
NOT_STARTED
IN_PROGRESS
BLOCKED
READY_FOR_REVIEW
DONE
```

## Özellikler

| Özellik | Durum | Not |
|---|---|---|
| Table QR Ordering — Domain Foundation | IN_PROGRESS | `Restaurant`/`Branch`/`RestaurantTable`/`TableQrCode`/`TableSession`/`GuestSession`/`TableQrResolutionResult` modelleri ve `OrderChannel` eklendi. Backend, QR tarama, sipariş gönderimi ve müşteri arayüzü kasıtlı olarak bu fazın dışında bırakıldı. Bkz. `docs/table_qr_architecture.md`.
| Order Lifecycle & Reliability Foundation | IN_PROGRESS | `OrderStatus` durum makinesi, `OrderItemSnapshot`, `OrderCancellationInfo`, `OrderTimestamps`, `OrderAuditEntry`, idempotency alanları (`requestId`/`createdDeviceId`/`createdSessionId`) `OrderModel`'e geriye dönük uyumlu şekilde eklendi. Backend, ödeme, mutfak/POS entegrasyonu ve UI geçişi kasıtlı olarak bu fazın dışında bırakıldı. Bkz. `docs/order_lifecycle_architecture.md`.