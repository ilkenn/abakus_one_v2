import '../../data/pos_order_repository.dart';

/// Discards a [PosOrderSession] — deletes its saved draft, if any. The
/// controller is responsible for clearing its own in-memory session state
/// back to `idle`; this use case only owns the repository side effect.
class CancelPosOrderSession {
  const CancelPosOrderSession({required PosOrderRepository repository})
      : _repository = repository;

  final PosOrderRepository _repository;

  Future<void> call(String draftId) => _repository.deleteDraft(draftId);
}
