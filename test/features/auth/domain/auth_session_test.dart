import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';

void main() {
  test('suresi gelecekte olan oturum expired degildir', () {
    final session = AuthSession(
      phoneNumber: '+905321234567',
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
    expect(session.isExpired, isFalse);
  });

  test('suresi gecmiste olan oturum expired kabul edilir', () {
    final session = AuthSession(
      phoneNumber: '+905321234567',
      createdAt: DateTime.now().subtract(const Duration(days: 31)),
      expiresAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    expect(session.isExpired, isTrue);
  });

  test('toJson/tryFromJson round-trip ayni degerleri korur', () {
    final original = AuthSession(
      phoneNumber: '+905321234567',
      createdAt: DateTime.utc(2026, 7, 22),
      expiresAt: DateTime.utc(2026, 8, 21),
    );
    final restored = AuthSession.tryFromJson(original.toJson());

    expect(restored, isNotNull);
    expect(restored!.phoneNumber, original.phoneNumber);
    expect(restored.createdAt, original.createdAt);
    expect(restored.expiresAt, original.expiresAt);
  });

  test('zorunlu alan eksikse tryFromJson null doner (uygulama cokmez)', () {
    expect(AuthSession.tryFromJson({'phoneNumber': '+905321234567'}), isNull);
  });

  test('bozuk tarih string\'i icin tryFromJson null doner', () {
    expect(
      AuthSession.tryFromJson({
        'phoneNumber': '+905321234567',
        'createdAt': 'not-a-date',
        'expiresAt': 'not-a-date',
      }),
      isNull,
    );
  });
}
