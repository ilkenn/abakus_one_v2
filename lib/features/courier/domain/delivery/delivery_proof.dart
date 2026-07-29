import 'delivery_proof_type.dart';

/// One immutable, append-only proof-of-delivery record. [referenceToken]
/// is an opaque string (e.g. a confirmation code, or a future secure-
/// storage object key) — never raw photo/signature bytes.
class DeliveryProof {
  const DeliveryProof({
    required this.id,
    required this.deliveryId,
    required this.type,
    this.referenceToken,
    this.note,
    required this.recordedByStaffId,
    required this.recordedAt,
  });

  final String id;
  final String deliveryId;
  final DeliveryProofType type;
  final String? referenceToken;
  final String? note;
  final String recordedByStaffId;
  final DateTime recordedAt;
}
