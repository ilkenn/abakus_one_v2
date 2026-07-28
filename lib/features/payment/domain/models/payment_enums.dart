/// The outcome of a single [PaymentProviderAdapter] call — distinct from
/// `PaymentSessionStatus` (`features/pos/domain/models/
/// payment_session_status.dart`), which tracks a whole collection
/// session's lifecycle, not one provider call's result.
enum PaymentStatus { pending, success, failed, notConfigured }
