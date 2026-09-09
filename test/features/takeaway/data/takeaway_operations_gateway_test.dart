import 'package:abakus_one_v2/features/takeaway/data/takeaway_operations_gateway.dart';
import 'package:abakus_one_v2/features/takeaway/domain/models/branch_takeaway_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UnavailableTakeawayOperationsGateway fails closed', () async {
    const gateway = UnavailableTakeawayOperationsGateway();
    await expectLater(
      gateway.updateTakeawayOperationStatus(
        organizationId: 'org-1',
        branchId: 'branch-1',
        status: TakeawayOperationStatus.active,
      ),
      throwsA(isA<TakeawayOperationsException>()),
    );
  });
}
