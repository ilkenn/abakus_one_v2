import 'package:abakus_one_v2/features/integrations/domain/webhook_signature_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UnverifiedWebhookSignatureVerifier', () {
    test('always returns false, fail-closed, regardless of input', () {
      const verifier = UnverifiedWebhookSignatureVerifier();

      expect(
        verifier.verify(
          payload: '{"event":"order.created"}',
          signature: 'sig-1',
          secret: 'secret-1',
        ),
        isFalse,
      );
      expect(
        verifier.verify(payload: '', signature: '', secret: ''),
        isFalse,
      );
    });
  });
}
