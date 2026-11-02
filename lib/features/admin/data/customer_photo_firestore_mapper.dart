import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../../../shared/models/customer_photo.dart';
import '../../../shared/models/customer_photo_status.dart';

/// Maps a real `customerPhotos/{photoId}` document (written by
/// `finalizeCustomerPhotoUpload`/`moderateCustomerPhoto`, Cloud Functions)
/// to/from [CustomerPhoto] — field names verified against those two
/// functions' own write shapes, never guessed.
abstract final class CustomerPhotoFirestoreMapper {
  CustomerPhotoFirestoreMapper._();

  static CustomerPhoto fromFirestore(String id, Map<String, dynamic> data) {
    return CustomerPhoto(
      id: id,
      customerId: data['customerId'] as String,
      organizationId: data['organizationId'] as String,
      photoRef: data['photoRef'] as String,
      status: CustomerPhotoStatus.values
          .firstWhere((s) => s.name == data['status']),
      isSelectedAsProfilePhoto:
          data['isSelectedAsProfilePhoto'] as bool? ?? false,
      uploadedAt: (data['uploadedAt'] as fs.Timestamp).toDate(),
      reviewedByStaffId: data['reviewedByStaffId'] as String?,
      reviewedAt: (data['reviewedAt'] as fs.Timestamp?)?.toDate(),
      rejectionReason: data['rejectionReason'] as String?,
      revision: data['revision'] as int,
      purpose: data['purpose'] as String?,
    );
  }
}
