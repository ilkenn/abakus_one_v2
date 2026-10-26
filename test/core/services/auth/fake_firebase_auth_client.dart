import 'package:abakus_one_v2/features/auth/data/repositories/firebase_auth_client.dart';

/// A deterministic, in-memory [FirebaseAuthClient] fake — no real Firebase
/// SDK involved. [verifyPhoneNumber] mints a stable, predictable
/// verificationId from [phoneNumber] so tests can assert on it without
/// needing real Firebase Auth Emulator connectivity. Shared by the
/// customer phone-OTP flow's own test and
/// `FirebaseStaffAuthRepository`'s phone-sign-in tests — the second real
/// consumer is what promotes this from an inline fake to a shared
/// test-support file, mirroring `FakeEmailPasswordAuthClient`'s own
/// convention one directory over.
class FakeFirebaseAuthClient implements FirebaseAuthClient {
  FakeFirebaseAuthClient({this.validSmsCode = '123456'});

  final String validSmsCode;

  final Map<String, String> _verificationIdsByPhoneNumber = {};
  bool throwOnVerify = false;
  bool signOutCalled = false;
  int verifyCallCount = 0;

  @override
  Future<String> verifyPhoneNumber(String phoneNumber) async {
    verifyCallCount++;
    if (throwOnVerify) {
      throw const FirebaseAuthClientException(
          'invalid-phone-number', 'Bad number.');
    }
    final verificationId = 'verification-id-for-$phoneNumber';
    _verificationIdsByPhoneNumber[phoneNumber] = verificationId;
    return verificationId;
  }

  @override
  Future<FirebaseAuthResult> confirmSmsCode({
    required String verificationId,
    required String smsCode,
  }) async {
    if (!_verificationIdsByPhoneNumber.containsValue(verificationId)) {
      throw const FirebaseAuthClientException(
          'invalid-verification-id', 'Unknown or expired challenge.');
    }
    if (smsCode != validSmsCode) {
      throw const FirebaseAuthClientException(
          'invalid-verification-code', 'Wrong code.');
    }
    final phoneNumber = _verificationIdsByPhoneNumber.entries
        .firstWhere((entry) => entry.value == verificationId)
        .key;
    return FirebaseAuthResult(
      uid: 'fake-phone-uid-$phoneNumber',
      phoneNumber: phoneNumber,
    );
  }

  @override
  Future<void> signOut() async => signOutCalled = true;
}
