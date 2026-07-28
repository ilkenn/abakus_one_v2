/// Lifecycle of a [PaymentVoid] request — a manually-recorded method
/// (cash/bank transfer/gift voucher) can void synchronously
/// (`pending -> completed` in one step, no provider round trip), while a
/// provider-processed split needs an actual reversal call, so `pending`
/// is a real, observable intermediate state, not just a formality.
enum PaymentVoidStatus { pending, completed, rejected }
