import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copyWith only changes the given fields and preserves openedAt', () {
    final check = Check(
      id: 'check-1',
      tableSessionId: 'tsession-1',
      branchId: 'branch-1',
      status: CheckStatus.open,
      posOrderSessionId: 'check-1-session',
      openedAt: DateTime(2026, 7, 29),
      revision: 1,
    );

    final submitted = check.copyWith(
      status: CheckStatus.submitted,
      orderId: OrderId('order-1'),
      revision: 2,
    );

    expect(submitted.status, CheckStatus.submitted);
    expect(submitted.orderId, OrderId('order-1'));
    expect(submitted.revision, 2);
    expect(submitted.id, check.id);
    expect(submitted.openedAt, check.openedAt);
    expect(submitted.posOrderSessionId, check.posOrderSessionId);
  });

  test('withGuestAdded is idempotent and bumps the revision', () {
    final check = Check(
      id: 'check-1',
      tableSessionId: 'tsession-1',
      branchId: 'branch-1',
      status: CheckStatus.open,
      openedAt: DateTime(2026, 7, 29),
      revision: 1,
    );

    final withGuest = check.withGuestAdded('guest-1');
    final withSameGuestAgain = withGuest.withGuestAdded('guest-1');

    expect(withGuest.guestSessionIds, ['guest-1']);
    expect(withGuest.revision, 2);
    expect(withSameGuestAgain.guestSessionIds, ['guest-1']);
    expect(withSameGuestAgain.revision, 2);
  });
}
