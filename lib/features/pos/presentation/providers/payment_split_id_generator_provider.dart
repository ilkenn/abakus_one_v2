import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/payment_split_id_generator.dart';

/// The [PaymentSplitIdGenerator] currently in use —
/// [SequentialPaymentSplitIdGenerator] today. Mirrors
/// `posOrderLineDraftIdGeneratorProvider`'s existing shape.
final paymentSplitIdGeneratorProvider =
    Provider<PaymentSplitIdGenerator>((ref) {
  return SequentialPaymentSplitIdGenerator();
});
