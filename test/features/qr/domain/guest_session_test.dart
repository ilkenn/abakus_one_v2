import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/qr/domain/models/guest_session.dart';

GuestSession buildGuestSession({
  String? currentCartId = 'cart_1',
  String? currentOrderId,
  String? authenticatedUserId,
  GuestSessionStatus status = GuestSessionStatus.active,
}) {
  return GuestSession(
    id: 'guest_1',
    tableSessionId: 'session_1',
    branchId: 'branch_1',
    tableId: 'table_1',
    detectedLanguageCode: 'tr',
    selectedLanguageCode: 'tr',
    currentCartId: currentCartId,
    currentOrderId: currentOrderId,
    authenticatedUserId: authenticatedUserId,
    createdAt: DateTime(2026, 6, 1, 12, 0),
    lastSeenAt: DateTime(2026, 6, 1, 12, 0),
    status: status,
  );
}

void main() {
  test('GuestSessionStatus beklenen tum durumlari icerir', () {
    expect(GuestSessionStatus.values, [
      GuestSessionStatus.active,
      GuestSessionStatus.claimed,
      GuestSessionStatus.expired,
      GuestSessionStatus.closed,
    ]);
  });

  test('yeni misafir oturumu anonimdir', () {
    final guest = buildGuestSession();
    expect(guest.isAnonymous, isTrue);
    expect(guest.authenticatedUserId, isNull);
  });

  group('claim', () {
    test('kullanici kimligini baglar ve durumu claimed yapar', () {
      final guest = buildGuestSession();
      final claimedAt = DateTime(2026, 6, 1, 12, 10);

      final claimed = guest.claim(userId: 'user_42', at: claimedAt);

      expect(claimed.authenticatedUserId, 'user_42');
      expect(claimed.status, GuestSessionStatus.claimed);
      expect(claimed.isAnonymous, isFalse);
      expect(claimed.lastSeenAt, claimedAt);
    });

    test('sepet ve masa baglamini kaybetmeden hesaba baglanir', () {
      final guest = buildGuestSession(
        currentCartId: 'cart_99',
        currentOrderId: 'order_7',
      );

      final claimed = guest.claim(
        userId: 'user_42',
        at: DateTime(2026, 6, 1, 12, 10),
      );

      expect(claimed.currentCartId, 'cart_99');
      expect(claimed.currentOrderId, 'order_7');
      expect(claimed.tableId, guest.tableId);
      expect(claimed.tableSessionId, guest.tableSessionId);
      expect(claimed.branchId, guest.branchId);
    });
  });

  test('touched yalnizca lastSeenAt gunceller', () {
    final guest = buildGuestSession();
    final newTime = DateTime(2026, 6, 1, 12, 20);

    final touched = guest.touched(newTime);

    expect(touched.lastSeenAt, newTime);
    expect(touched.currentCartId, guest.currentCartId);
    expect(touched.status, guest.status);
  });

  test('closed() durumu kapatir', () {
    final guest = buildGuestSession();
    final closedAt = DateTime(2026, 6, 1, 13, 0);

    final closed = guest.closed(at: closedAt);

    expect(closed.status, GuestSessionStatus.closed);
    expect(closed.lastSeenAt, closedAt);
  });
}
