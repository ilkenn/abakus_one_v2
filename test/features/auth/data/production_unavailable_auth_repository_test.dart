import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/development_local_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/production_unavailable_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';

void main() {
  const repository = ProductionUnavailableAuthRepository();
  const phoneNumber = '+905321234567';

  test('loadSession her zaman null doner - sahte oturum olusturulmaz',
      () async {
    expect(await repository.loadSession(), isNull);
  });

  test('requestOtp AuthServiceUnavailableException firlatir', () async {
    await expectLater(
      repository.requestOtp(phoneNumber),
      throwsA(isA<AuthServiceUnavailableException>()),
    );
  });

  test(
      'verifyOtp, development kodu (123456) gonderilse bile '
      'basari uretmez - AuthServiceUnavailableException firlatir', () async {
    await expectLater(
      repository.verifyOtp(
        phoneNumber: phoneNumber,
        code: DevelopmentLocalAuthRepository.developmentOtpCode,
      ),
      throwsA(isA<AuthServiceUnavailableException>()),
    );
  });

  test('saveSession/clearSession guvenli sekilde no-op calisir', () async {
    await repository.saveSession(
      AuthSession(
        phoneNumber: phoneNumber,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      ),
    );
    await repository.clearSession();
    // Hicbir exception firlatilmadan tamamlanmasi yeterli.
  });
}
