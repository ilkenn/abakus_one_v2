import '../models/order_id.dart';

/// A secure, opaque token identifying an order for a receipt's QR code —
/// mirrors `TableQrCode.opaqueToken`'s own shape and rationale: identity
/// must be resolved server-side, never derivable from the token itself.
class ReceiptQrToken {
  const ReceiptQrToken({required this.value, required this.expiresAt});

  final String value;
  final DateTime expiresAt;
}

/// Issues a [ReceiptQrToken] identifying [orderId] — **contract only**,
/// no implementation exists this sprint.
///
/// This codebase's own established pattern
/// (`TableQrCode`/`TableQrResolutionResult`, `docs/table_qr_architecture.md`
/// §10) is that a security-sensitive token is always backend-issued —
/// nothing client-side generates or derives one. With no backend, only
/// this contract can honestly exist; [UnavailableReceiptQrTokenProvider]
/// is the safe default (mirrors `UnavailableExchangeRateProvider`).
/// Rendering the resulting token as an actual QR image additionally needs
/// a QR-image-rendering package (none is a dependency today) — a new-
/// dependency decision explicitly left for separate approval, matching
/// the `flutter_svg` precedent declined in Phase 3 Sprint 3C.
abstract interface class ReceiptQrTokenProvider {
  Future<ReceiptQrToken> issueToken(OrderId orderId);
}

/// The only implementation this sprint — always throws, an honest
/// "not available" stand-in rather than fabricating a token client-side.
class UnavailableReceiptQrTokenProvider implements ReceiptQrTokenProvider {
  const UnavailableReceiptQrTokenProvider();

  @override
  Future<ReceiptQrToken> issueToken(OrderId orderId) {
    throw UnsupportedError(
      'Receipt QR token issuance requires a backend — none exists yet.',
    );
  }
}
