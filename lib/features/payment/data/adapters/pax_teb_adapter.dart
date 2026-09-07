import '../../../../shared/models/money.dart';
import '../../domain/models/payment_enums.dart';
import '../../domain/models/payment_request.dart';
import '../../domain/models/payment_result.dart';
import 'payment_provider_adapter.dart';

/// AP-4 hardware-unblocking sprint — the physical PAX A910SF terminal
/// running TEB's own POS Android application, triggered on-device via an
/// explicit Intent rather than an HTTP call (the shape every other
/// [PaymentProviderAdapter] implementation in this directory uses).
///
/// **Deliberately still a stub, exactly like the other 9 adapters in this
/// directory.** `docs/payment_cash_fiscal_architecture.md` §14/§21 — one of
/// this project's six canonical architecture documents, ranked above
/// `CLAUDE.md` itself — locks the PAX A910SF integration as a
/// `CONTROLLED_EXTERNAL_DEPENDENCY`: "no vendor protocol detail is written
/// without official vendor documentation," and requires an "official PAX
/// SDK + integration guide" plus a real-hardware acceptance test before any
/// production transaction. No official TEB/PAX Intent specification
/// (action string, package name, extras schema, or result-parsing
/// contract) has been supplied — inventing one here would mean shipping
/// code that either throws `ActivityNotFoundException` against the real
/// terminal or silently misreads its response, which is worse than an
/// honest "not configured" for something that moves money. This class
/// exists so `PaymentService`/`PaymentMethodSeedData.creditCard` have a
/// real routing target to plug a working implementation into later,
/// without any caller-facing shape change.
class PaxTebTerminalAdapter implements PaymentProviderAdapter {
  @override
  Future<PaymentResult> processPayment(PaymentRequest request) async {
    return const PaymentResult(
      transactionId: '',
      status: PaymentStatus.notConfigured,
      errorMessage:
          'PAX A910SF / TEB POS entegrasyonu henüz yapılandırılmadı.',
    );
  }

  @override
  Future<PaymentResult> refundPayment(
    String transactionId,
    Money amount,
  ) async {
    return const PaymentResult(
      transactionId: '',
      status: PaymentStatus.notConfigured,
      errorMessage:
          'PAX A910SF / TEB POS entegrasyonu henüz yapılandırılmadı.',
    );
  }
}
