import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/admin/application/identity/customer_photo_id_generator.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/moderate_customer_photo.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/select_customer_profile_photo.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/submit_customer_photo.dart';
import 'package:abakus_one_v2/features/admin/data/admin_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/admin/data/customer_photo_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/customer/customer_photo.dart';
import 'package:abakus_one_v2/features/admin/domain/customer/customer_photo_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/admin_test_fixtures.dart';

void main() {
  group('SubmitCustomerPhoto', () {
    test(
        'the first 10 eligible photos are accepted — CustomerPhoto.'
        'maxEligiblePhotos', () async {
      final repository = InMemoryCustomerPhotoRepository();
      final useCase = SubmitCustomerPhoto(
        idGenerator: SequentialCustomerPhotoIdGenerator(),
        repository: repository,
      );

      for (var i = 0; i < CustomerPhoto.maxEligiblePhotos; i++) {
        final photo = await useCase(
          customerId: 'customer-1',
          organizationId: 'org-1',
          photoRef: 'ref-$i',
          uploadedAt: DateTime(2026, 1, 1),
        );
        expect(photo.status, CustomerPhotoStatus.pendingReview);
      }

      final stored = await repository.findByCustomerId('customer-1');
      expect(stored.length, CustomerPhoto.maxEligiblePhotos);
    });

    test('the 11th eligible photo is rejected — maximum 10', () async {
      final repository = InMemoryCustomerPhotoRepository();
      final useCase = SubmitCustomerPhoto(
        idGenerator: SequentialCustomerPhotoIdGenerator(),
        repository: repository,
      );
      for (var i = 0; i < CustomerPhoto.maxEligiblePhotos; i++) {
        await useCase(
          customerId: 'customer-1',
          organizationId: 'org-1',
          photoRef: 'ref-$i',
          uploadedAt: DateTime(2026, 1, 1),
        );
      }

      expect(
        () => useCase(
          customerId: 'customer-1',
          organizationId: 'org-1',
          photoRef: 'ref-11',
          uploadedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<CustomerPhotoLimitReachedViolation>()),
      );
    });

    test('rejected/removed photos never consume the allowance', () async {
      final repository = InMemoryCustomerPhotoRepository();
      await repository.save(CustomerPhoto(
        id: 'photo-1',
        customerId: 'customer-1',
        organizationId: 'org-1',
        photoRef: 'ref-1',
        status: CustomerPhotoStatus.rejected,
        uploadedAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final useCase = SubmitCustomerPhoto(
        idGenerator: SequentialCustomerPhotoIdGenerator(),
        repository: repository,
      );

      final photo = await useCase(
        customerId: 'customer-1',
        organizationId: 'org-1',
        photoRef: 'ref-2',
        uploadedAt: DateTime(2026, 1, 1),
      );

      expect(photo.status, CustomerPhotoStatus.pendingReview);
    });

    test(
        'a full allowance of rejected/removed photos still leaves 10 '
        'eligible slots free', () async {
      final repository = InMemoryCustomerPhotoRepository();
      for (var i = 0; i < 12; i++) {
        await repository.save(CustomerPhoto(
          id: 'stale-photo-$i',
          customerId: 'customer-1',
          organizationId: 'org-1',
          photoRef: 'stale-ref-$i',
          status: i.isEven
              ? CustomerPhotoStatus.rejected
              : CustomerPhotoStatus.removed,
          uploadedAt: DateTime(2026, 1, 1),
          revision: 1,
        ));
      }
      final useCase = SubmitCustomerPhoto(
        idGenerator: SequentialCustomerPhotoIdGenerator(),
        repository: repository,
      );

      for (var i = 0; i < CustomerPhoto.maxEligiblePhotos; i++) {
        final photo = await useCase(
          customerId: 'customer-1',
          organizationId: 'org-1',
          photoRef: 'fresh-ref-$i',
          uploadedAt: DateTime(2026, 1, 1),
        );
        expect(photo.status, CustomerPhotoStatus.pendingReview);
      }
    });
  });

  group('ModerateCustomerPhoto', () {
    test('rejecting a selected profile photo clears the selection', () async {
      final repository = InMemoryCustomerPhotoRepository();
      await repository.save(CustomerPhoto(
        id: 'photo-1',
        customerId: 'customer-1',
        organizationId: 'org-1',
        photoRef: 'ref-1',
        status: CustomerPhotoStatus.approved,
        isSelectedAsProfilePhoto: true,
        uploadedAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final useCase = ModerateCustomerPhoto(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final result = await useCase(
        photoId: 'photo-1',
        moderationAction: CustomerPhotoModerationAction.reject,
        rejectionReason: 'Uygunsuz içerik',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(result.status, CustomerPhotoStatus.rejected);
      expect(result.isSelectedAsProfilePhoto, isFalse);
      expect(result.rejectionReason, 'Uygunsuz içerik');
    });

    test('an unauthorized actor cannot moderate a photo', () async {
      final repository = InMemoryCustomerPhotoRepository();
      await repository.save(CustomerPhoto(
        id: 'photo-1',
        customerId: 'customer-1',
        organizationId: 'org-1',
        photoRef: 'ref-1',
        uploadedAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final useCase = ModerateCustomerPhoto(
        authorizationPolicy: const DenyAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          photoId: 'photo-1',
          moderationAction: CustomerPhotoModerationAction.approve,
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });

  group('SelectCustomerProfilePhoto', () {
    test('throws when the photo is not approved', () async {
      final repository = InMemoryCustomerPhotoRepository();
      await repository.save(CustomerPhoto(
        id: 'photo-1',
        customerId: 'customer-1',
        organizationId: 'org-1',
        photoRef: 'ref-1',
        status: CustomerPhotoStatus.pendingReview,
        uploadedAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final useCase = SelectCustomerProfilePhoto(repository: repository);

      expect(
        () => useCase(photoId: 'photo-1'),
        throwsA(isA<CustomerPhotoNotApprovedViolation>()),
      );
    });

    test(
        'selecting a new photo deselects the previous one — 0-or-1 '
        'invariant', () async {
      final repository = InMemoryCustomerPhotoRepository();
      await repository.save(CustomerPhoto(
        id: 'photo-1',
        customerId: 'customer-1',
        organizationId: 'org-1',
        photoRef: 'ref-1',
        status: CustomerPhotoStatus.approved,
        isSelectedAsProfilePhoto: true,
        uploadedAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      await repository.save(CustomerPhoto(
        id: 'photo-2',
        customerId: 'customer-1',
        organizationId: 'org-1',
        photoRef: 'ref-2',
        status: CustomerPhotoStatus.approved,
        uploadedAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final useCase = SelectCustomerProfilePhoto(repository: repository);

      await useCase(photoId: 'photo-2');

      final photo1 = await repository.findById('photo-1');
      final photo2 = await repository.findById('photo-2');
      expect(photo1!.isSelectedAsProfilePhoto, isFalse);
      expect(photo2!.isSelectedAsProfilePhoto, isTrue);
    });
  });
}
