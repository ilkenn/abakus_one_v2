import '../models/order_id.dart';
import 'package_checklist_item.dart';
import 'package_preparation_status.dart';

/// One [Order]'s package/delivery-preparation record — packaging
/// checklist, preparer/QC identity, timestamps, and an optional photo,
/// tracked independently of [OrderStatus] (see
/// `PackagePreparationStatus`'s own doc comment for why).
///
/// **Append-only**: never mutated in place — every change produces a new
/// instance with the same [orderId] and an incremented [revision];
/// `PackagePreparationRepository.save` always appends (mirrors
/// `OrderClosure`).
class PackagePreparation {
  const PackagePreparation({
    required this.orderId,
    required this.status,
    this.checklist = const [],
    this.orderNotes = '',
    this.preparedByStaffId,
    this.qualityControlledByStaffId,
    this.preparationCompletedAt,
    this.qualityControlCompletedAt,
    this.photoAssetPath,
    this.correctionReason,
    required this.revision,
  });

  final OrderId orderId;
  final PackagePreparationStatus status;
  final List<PackageChecklistItem> checklist;

  /// Free-text instruction carried onto the package record — distinct
  /// from `Order.kitchenNote`; this is what the *packer*, not the cook,
  /// needs to see.
  final String orderNotes;

  final String? preparedByStaffId;
  final String? qualityControlledByStaffId;
  final DateTime? preparationCompletedAt;
  final DateTime? qualityControlCompletedAt;

  /// Local asset/file path of an optional package photograph — no upload
  /// or cloud-storage integration exists this sprint; a `null` value is
  /// the honest default, not a gap to silently fill.
  final String? photoAssetPath;

  /// Reason recorded when `ReturnToKitchen` sends this package back from
  /// [PackagePreparationStatus.exception] — `null` unless that has
  /// actually happened.
  final String? correctionReason;

  /// Optimistic-concurrency counter — starts at 1.
  final int revision;

  PackagePreparation copyWith({
    PackagePreparationStatus? status,
    List<PackageChecklistItem>? checklist,
    String? orderNotes,
    String? preparedByStaffId,
    String? qualityControlledByStaffId,
    DateTime? preparationCompletedAt,
    DateTime? qualityControlCompletedAt,
    String? photoAssetPath,
    String? correctionReason,
    int? revision,
  }) {
    return PackagePreparation(
      orderId: orderId,
      status: status ?? this.status,
      checklist: checklist ?? this.checklist,
      orderNotes: orderNotes ?? this.orderNotes,
      preparedByStaffId: preparedByStaffId ?? this.preparedByStaffId,
      qualityControlledByStaffId:
          qualityControlledByStaffId ?? this.qualityControlledByStaffId,
      preparationCompletedAt:
          preparationCompletedAt ?? this.preparationCompletedAt,
      qualityControlCompletedAt:
          qualityControlCompletedAt ?? this.qualityControlCompletedAt,
      photoAssetPath: photoAssetPath ?? this.photoAssetPath,
      correctionReason: correctionReason ?? this.correctionReason,
      revision: revision ?? this.revision,
    );
  }
}
