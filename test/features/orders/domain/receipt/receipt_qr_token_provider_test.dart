import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/receipt/receipt_qr_token_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'UnavailableReceiptQrTokenProvider always throws, never fabricates a token',
      () async {
    const provider = UnavailableReceiptQrTokenProvider();

    expect(
      () => provider.issueToken(OrderId('order-1')),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
