import '../../../../core/utils/clock.dart';
import '../../domain/models/pos_order_session.dart';

/// Updates a [PosOrderSession]'s order-level [PosOrderSession.customerNote]
/// / [PosOrderSession.kitchenNote] — distinct from any individual line's
/// own note. Doesn't affect [PosOrderSession.pricing], so no totals
/// recalculation is needed.
class UpdatePosOrderNotes {
  const UpdatePosOrderNotes({required Clock clock}) : _clock = clock;

  final Clock _clock;

  PosOrderSession call({
    required PosOrderSession session,
    String? customerNote,
    String? kitchenNote,
  }) {
    return session.copyWith(
      customerNote: customerNote,
      kitchenNote: kitchenNote,
      lastUpdatedAt: _clock.now(),
    );
  }
}
