import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/data/package_preparation_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/fulfillment/package_checklist_item.dart';
import 'package:abakus_one_v2/features/orders/domain/fulfillment/package_preparation_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/advance_package_preparation.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/attach_package_photo.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/complete_quality_control.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/return_to_kitchen.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/start_package_preparation.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/update_package_checklist.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_pos_authorization_policy.dart';

void main() {
  test(
      'the full happy-path lifecycle: start -> checklist -> pack -> QC -> deliver',
      () async {
    final repository = InMemoryPackagePreparationRepository();
    final orderId = OrderId('order-1');

    final started = await StartPackagePreparation(repository: repository)(
      orderId: orderId,
      checklist: const [
        PackageChecklistItem(
            category: PackageChecklistCategory.drink, description: 'Kola'),
      ],
    );
    expect(started.status, PackagePreparationStatus.received);

    final checked = await UpdatePackageChecklist(repository: repository)(
      orderId: orderId,
      checklistIndex: 0,
      isChecked: true,
    );
    expect(checked.checklist.single.isChecked, isTrue);

    var current = checked;
    for (final next in [
      PackagePreparationStatus.pendingAcceptance,
      PackagePreparationStatus.accepted,
      PackagePreparationStatus.preparing,
      PackagePreparationStatus.readyForPacking,
      PackagePreparationStatus.packing,
      PackagePreparationStatus.packed,
    ]) {
      current = await AdvancePackagePreparation(repository: repository)(
        orderId: orderId,
        newStatus: next,
        performedByStaffId: 'staff-1',
        at: DateTime(2026, 7, 29),
      );
    }
    expect(current.status, PackagePreparationStatus.packed);
    expect(current.preparedByStaffId, 'staff-1');
    expect(current.preparationCompletedAt, DateTime(2026, 7, 29));

    final qcd = await CompleteQualityControl(repository: repository)(
      orderId: orderId,
      performedByStaffId: 'staff-2',
      at: DateTime(2026, 7, 29, 1),
    );
    expect(qcd.qualityControlledByStaffId, 'staff-2');
    expect(qcd.status, PackagePreparationStatus.packed);

    final withPhoto = await AttachPackagePhoto(repository: repository)(
      orderId: orderId,
      assetPath: '/tmp/package.jpg',
    );
    expect(withPhoto.photoAssetPath, '/tmp/package.jpg');

    final delivered = await AdvancePackagePreparation(repository: repository)(
      orderId: orderId,
      newStatus: PackagePreparationStatus.delivered,
      performedByStaffId: 'staff-1',
      at: DateTime(2026, 7, 29, 2),
    );
    expect(delivered.status, PackagePreparationStatus.delivered);
    // preparedByStaffId/preparationCompletedAt persist even once the
    // status has moved past `packed`.
    expect(delivered.preparedByStaffId, 'staff-1');
  });

  test('AdvancePackagePreparation rejects an invalid transition', () async {
    final repository = InMemoryPackagePreparationRepository();
    final orderId = OrderId('order-1');
    await StartPackagePreparation(repository: repository)(orderId: orderId);

    expect(
      () => AdvancePackagePreparation(repository: repository)(
        orderId: orderId,
        newStatus: PackagePreparationStatus.packed,
        performedByStaffId: 'staff-1',
        at: DateTime(2026, 7, 29),
      ),
      throwsA(isA<InvalidPackagePreparationTransitionViolation>()),
    );
  });

  test(
      'ReturnToKitchen requires no authorization when the package never reached packed',
      () async {
    final repository = InMemoryPackagePreparationRepository();
    final orderId = OrderId('order-1');
    await StartPackagePreparation(repository: repository)(orderId: orderId);
    await AdvancePackagePreparation(repository: repository)(
      orderId: orderId,
      newStatus: PackagePreparationStatus.pendingAcceptance,
      performedByStaffId: 'staff-1',
      at: DateTime(2026, 7, 29),
    );
    await AdvancePackagePreparation(repository: repository)(
      orderId: orderId,
      newStatus: PackagePreparationStatus.accepted,
      performedByStaffId: 'staff-1',
      at: DateTime(2026, 7, 29),
    );
    await AdvancePackagePreparation(repository: repository)(
      orderId: orderId,
      newStatus: PackagePreparationStatus.preparing,
      performedByStaffId: 'staff-1',
      at: DateTime(2026, 7, 29),
    );
    await AdvancePackagePreparation(repository: repository)(
      orderId: orderId,
      newStatus: PackagePreparationStatus.exception,
      performedByStaffId: 'staff-1',
      at: DateTime(2026, 7, 29),
    );
    final policy =
        FakePosAuthorizationPolicy(const AuthorizationResult(granted: false));

    final result = await ReturnToKitchen(
      authorizationPolicy: policy,
      repository: repository,
    )(orderId: orderId, reason: 'Yanlış ürün', performedByStaffId: 'staff-1');

    expect(result.status, PackagePreparationStatus.preparing);
    expect(policy.callCount, 0);
  });

  test(
      'ReturnToKitchen requires authorization once the package had already reached packed (completion override)',
      () async {
    final repository = InMemoryPackagePreparationRepository();
    final orderId = OrderId('order-1');
    await StartPackagePreparation(repository: repository)(orderId: orderId);
    for (final next in [
      PackagePreparationStatus.pendingAcceptance,
      PackagePreparationStatus.accepted,
      PackagePreparationStatus.preparing,
      PackagePreparationStatus.readyForPacking,
      PackagePreparationStatus.packing,
      PackagePreparationStatus.packed,
      PackagePreparationStatus.exception,
    ]) {
      await AdvancePackagePreparation(repository: repository)(
        orderId: orderId,
        newStatus: next,
        performedByStaffId: 'staff-1',
        at: DateTime(2026, 7, 29),
      );
    }

    final denied = ReturnToKitchen(
      authorizationPolicy:
          FakePosAuthorizationPolicy(const AuthorizationResult(granted: false)),
      repository: repository,
    );
    expect(
      () => denied(
          orderId: orderId,
          reason: 'Bozuk paket',
          performedByStaffId: 'staff-1'),
      throwsA(isA<AuthorizationDeniedViolation>()),
    );

    final granted = ReturnToKitchen(
      authorizationPolicy:
          FakePosAuthorizationPolicy(const AuthorizationResult(granted: true)),
      repository: repository,
    );
    final result = await granted(
        orderId: orderId, reason: 'Bozuk paket', performedByStaffId: 'staff-1');
    expect(result.status, PackagePreparationStatus.preparing);
    expect(result.correctionReason, 'Bozuk paket');
  });
}
