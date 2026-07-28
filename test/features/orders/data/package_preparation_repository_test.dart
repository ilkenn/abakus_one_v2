import 'package:abakus_one_v2/features/orders/data/package_preparation_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/fulfillment/package_preparation.dart';
import 'package:abakus_one_v2/features/orders/domain/fulfillment/package_preparation_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('save keeps every revision; findCurrentByOrderId returns the latest',
      () async {
    final repository = InMemoryPackagePreparationRepository();
    final orderId = OrderId('order-1');
    await repository.save(PackagePreparation(
      orderId: orderId,
      status: PackagePreparationStatus.received,
      revision: 1,
    ));
    await repository.save(PackagePreparation(
      orderId: orderId,
      status: PackagePreparationStatus.pendingAcceptance,
      revision: 2,
    ));

    final current = await repository.findCurrentByOrderId(orderId);
    final history = await repository.findHistoryByOrderId(orderId);

    expect(current!.revision, 2);
    expect(history.map((p) => p.revision), [1, 2]);
  });
}
