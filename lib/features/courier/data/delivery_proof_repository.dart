import '../domain/delivery/delivery_proof.dart';

/// Append-only storage for [DeliveryProof] — no update/delete method.
abstract interface class DeliveryProofRepository {
  Future<void> append(DeliveryProof proof);
  Future<List<DeliveryProof>> findByDeliveryId(String deliveryId);
}

class InMemoryDeliveryProofRepository implements DeliveryProofRepository {
  final List<DeliveryProof> _proofs = [];

  @override
  Future<void> append(DeliveryProof proof) async {
    _proofs.add(proof);
  }

  @override
  Future<List<DeliveryProof>> findByDeliveryId(String deliveryId) async {
    return List.unmodifiable(
      _proofs.where((p) => p.deliveryId == deliveryId),
    );
  }
}
