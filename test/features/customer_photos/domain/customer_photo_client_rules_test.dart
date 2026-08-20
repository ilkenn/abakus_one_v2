import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/customer_photos/domain/customer_photo_client_rules.dart';
import 'package:abakus_one_v2/shared/models/customer_photo.dart';
import 'package:abakus_one_v2/shared/models/customer_photo_status.dart';

void main() {
  CustomerPhoto photo({
    String id = 'p1',
    CustomerPhotoStatus status = CustomerPhotoStatus.approved,
    DateTime? uploadedAt,
    String? purpose,
  }) {
    return CustomerPhoto(
      id: id,
      customerId: 'customer-uid-1',
      organizationId: 'org-1',
      photoRef: 'tenants/org-1/customerPhotos/customer-uid-1/$id',
      status: status,
      uploadedAt: uploadedAt ?? DateTime(2026, 8, 1),
      revision: 1,
      purpose: purpose,
    );
  }

  group('resolveCustomerHeroPhoto', () {
    test('no photos at all -> null (caller renders initials)', () {
      final resolved = resolveCustomerHeroPhoto(
        galleryPhotos: const [],
        selectedProfilePhotoRef: null,
      );
      expect(resolved, isNull);
    });

    test(
        'approved + matching the canonical selectedProfilePhotoRef -> approvedSelected',
        () {
      final approved = photo(
        id: 'p1',
        status: CustomerPhotoStatus.approved,
      );
      final resolved = resolveCustomerHeroPhoto(
        galleryPhotos: [approved],
        selectedProfilePhotoRef: approved.photoRef,
      );
      expect(resolved?.photo.id, 'p1');
      expect(resolved?.presentation,
          CustomerHeroPhotoPresentation.approvedSelected);
    });

    test(
        'an approved photo NOT matching selectedProfilePhotoRef is never chosen',
        () {
      final approved = photo(id: 'p1', status: CustomerPhotoStatus.approved);
      final resolved = resolveCustomerHeroPhoto(
        galleryPhotos: [approved],
        selectedProfilePhotoRef: 'some/other/path',
      );
      expect(resolved, isNull);
    });

    test(
        'isSelectedAsProfilePhoto on the photo itself is never consulted — only the projection ref matters',
        () {
      final selectedFlagOnly = CustomerPhoto(
        id: 'p1',
        customerId: 'customer-uid-1',
        organizationId: 'org-1',
        photoRef: 'tenants/org-1/customerPhotos/customer-uid-1/p1',
        status: CustomerPhotoStatus.approved,
        isSelectedAsProfilePhoto: true,
        uploadedAt: DateTime(2026, 8, 1),
        revision: 1,
      );
      final resolved = resolveCustomerHeroPhoto(
        galleryPhotos: [selectedFlagOnly],
        selectedProfilePhotoRef: null,
      );
      expect(resolved, isNull,
          reason:
              'a stale/mirrored isSelectedAsProfilePhoto flag must never substitute for the canonical projection ref');
    });

    test('a pendingReview photo is owner-private and always wins', () {
      final pending =
          photo(id: 'p1', status: CustomerPhotoStatus.pendingReview);
      final resolved = resolveCustomerHeroPhoto(
        galleryPhotos: [pending],
        selectedProfilePhotoRef: null,
      );
      expect(resolved?.photo.id, 'p1');
      expect(resolved?.presentation,
          CustomerHeroPhotoPresentation.pendingOwnerPrivate);
    });

    test('an underReview photo is owner-private', () {
      final underReview =
          photo(id: 'p1', status: CustomerPhotoStatus.underReview);
      final resolved = resolveCustomerHeroPhoto(
        galleryPhotos: [underReview],
        selectedProfilePhotoRef: null,
      );
      expect(resolved?.photo.id, 'p1');
      expect(resolved?.presentation,
          CustomerHeroPhotoPresentation.underReviewOwnerPrivate);
    });

    test('a rejected photo is never returned as the hero photo', () {
      final rejected = photo(id: 'p1', status: CustomerPhotoStatus.rejected);
      final resolved = resolveCustomerHeroPhoto(
        galleryPhotos: [rejected],
        selectedProfilePhotoRef: rejected.photoRef,
      );
      expect(resolved, isNull);
    });

    test('a removed photo is never returned as the hero photo', () {
      final removed = photo(id: 'p1', status: CustomerPhotoStatus.removed);
      final resolved = resolveCustomerHeroPhoto(
        galleryPhotos: [removed],
        selectedProfilePhotoRef: removed.photoRef,
      );
      expect(resolved, isNull);
    });

    test(
        'a pending photo overrides an already-approved-and-selected photo — pending always wins',
        () {
      final approvedSelected =
          photo(id: 'approved-1', status: CustomerPhotoStatus.approved);
      final pending = photo(
        id: 'pending-1',
        status: CustomerPhotoStatus.pendingReview,
        uploadedAt: DateTime(2026, 8, 2),
      );
      final resolved = resolveCustomerHeroPhoto(
        galleryPhotos: [approvedSelected, pending],
        selectedProfilePhotoRef: approvedSelected.photoRef,
      );
      expect(resolved?.photo.id, 'pending-1');
      expect(resolved?.presentation,
          CustomerHeroPhotoPresentation.pendingOwnerPrivate);
    });

    test(
        'when multiple pending/underReview photos exist, the newest by uploadedAt wins',
        () {
      final older = photo(
        id: 'older',
        status: CustomerPhotoStatus.pendingReview,
        uploadedAt: DateTime(2026, 8, 1),
      );
      final middle = photo(
        id: 'middle',
        status: CustomerPhotoStatus.underReview,
        uploadedAt: DateTime(2026, 8, 3),
      );
      final newest = photo(
        id: 'newest',
        status: CustomerPhotoStatus.pendingReview,
        uploadedAt: DateTime(2026, 8, 5),
      );
      final resolved = resolveCustomerHeroPhoto(
        galleryPhotos: [older, newest, middle],
        selectedProfilePhotoRef: null,
      );
      expect(resolved?.photo.id, 'newest');
    });

    test(
        'rejected/removed photos are ignored even when several other photos exist',
        () {
      final rejected = photo(id: 'r1', status: CustomerPhotoStatus.rejected);
      final removed = photo(id: 'r2', status: CustomerPhotoStatus.removed);
      final approved = photo(id: 'a1', status: CustomerPhotoStatus.approved);
      final resolved = resolveCustomerHeroPhoto(
        galleryPhotos: [rejected, removed, approved],
        selectedProfilePhotoRef: approved.photoRef,
      );
      expect(resolved?.photo.id, 'a1');
      expect(resolved?.presentation,
          CustomerHeroPhotoPresentation.approvedSelected);
    });
  });
  group('resolveCustomerPhotoContentType', () {
    test('prefers a non-empty mimeType (Web) over the file extension', () {
      expect(
        resolveCustomerPhotoContentType(
            mimeType: 'image/png', fileName: 'photo.heic'),
        'image/png',
      );
    });

    test('falls back to the file extension when mimeType is null (Android/iOS)',
        () {
      expect(
        resolveCustomerPhotoContentType(
            mimeType: null, fileName: 'IMG_0001.JPG'),
        'image/jpeg',
      );
      expect(
        resolveCustomerPhotoContentType(mimeType: null, fileName: 'photo.png'),
        'image/png',
      );
      expect(
        resolveCustomerPhotoContentType(mimeType: null, fileName: 'photo.heic'),
        'image/heic',
      );
      expect(
        resolveCustomerPhotoContentType(mimeType: null, fileName: 'photo.webp'),
        'image/webp',
      );
    });

    test('falls back to the file extension when mimeType is empty', () {
      expect(
        resolveCustomerPhotoContentType(mimeType: '', fileName: 'photo.png'),
        'image/png',
      );
    });

    test('an unrecognized extension resolves to null (unsupported)', () {
      expect(
        resolveCustomerPhotoContentType(
            mimeType: null, fileName: 'document.pdf'),
        isNull,
      );
    });

    test('no extension at all resolves to null', () {
      expect(
        resolveCustomerPhotoContentType(
            mimeType: null, fileName: 'noextension'),
        isNull,
      );
    });
  });

  group('isSupportedCustomerPhotoContentType', () {
    test('accepts any image/* — mirrors storage.rules\' own pattern exactly',
        () {
      expect(isSupportedCustomerPhotoContentType('image/png'), isTrue);
      expect(isSupportedCustomerPhotoContentType('image/jpeg'), isTrue);
      expect(isSupportedCustomerPhotoContentType('image/heic'), isTrue);
    });

    test('rejects a non-image content type', () {
      expect(isSupportedCustomerPhotoContentType('application/pdf'), isFalse);
      expect(isSupportedCustomerPhotoContentType('video/mp4'), isFalse);
    });

    test('rejects null', () {
      expect(isSupportedCustomerPhotoContentType(null), isFalse);
    });
  });

  group('customerPhotoStatusLabel', () {
    test(
        'maps every status to a customer-safe Turkish label, never staff terminology',
        () {
      expect(customerPhotoStatusLabel(CustomerPhotoStatus.pendingReview),
          'Onay Bekliyor');
      expect(customerPhotoStatusLabel(CustomerPhotoStatus.underReview),
          'İnceleniyor');
      expect(
          customerPhotoStatusLabel(CustomerPhotoStatus.approved), 'Onaylandı');
      expect(customerPhotoStatusLabel(CustomerPhotoStatus.rejected),
          'Onaylanmadı');
      expect(
          customerPhotoStatusLabel(CustomerPhotoStatus.removed), 'Kaldırıldı');
    });

    test('no label mentions internal/staff terminology', () {
      for (final status in CustomerPhotoStatus.values) {
        final label = customerPhotoStatusLabel(status);
        expect(label.toLowerCase(), isNot(contains('staff')));
        expect(label.toLowerCase(), isNot(contains('reviewer')));
        expect(label.toLowerCase(), isNot(contains('grant')));
        expect(label.toLowerCase(), isNot(contains('audit')));
      }
    });
  });

  test(
      'kMaxCustomerPhotoUploadBytes mirrors storage.rules\' own 5 MB cap exactly',
      () {
    expect(kMaxCustomerPhotoUploadBytes, 5 * 1024 * 1024);
  });

  test(
      'the customer photo client rules file never imports dart:io — the shared upload path must stay web-compatible',
      () {
    final source = File(
      'lib/features/customer_photos/domain/customer_photo_client_rules.dart',
    ).readAsStringSync();
    expect(
      RegExp('''^import\\s+['"]dart:io['"]''', multiLine: true)
          .hasMatch(source),
      isFalse,
    );
  });
}
