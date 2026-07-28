import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/pos_order_line_draft_id_generator.dart';

/// The [PosOrderLineDraftIdGenerator] currently in use —
/// [SequentialPosOrderLineDraftIdGenerator] today. Mirrors
/// `clockProvider`/`orderIdentityProvider`'s existing shape: nothing that
/// depends on this contract ever depends on the concrete implementation
/// directly, so tests can override this one provider with a fake.
final posOrderLineDraftIdGeneratorProvider =
    Provider<PosOrderLineDraftIdGenerator>((ref) {
  return SequentialPosOrderLineDraftIdGenerator();
});
