import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:http/http.dart' as http;

/// AP-4 Wave E — shared real-emulator fixture helpers for Flutter
/// integration tests, mirroring `functions/src/test/*.test.ts`'s own
/// established `callCallable`/`signUpAnonymously`/`newStaffMember`/
/// `activeDeviceSession` pattern, ported to Dart. Uses `package:http`
/// (never `dart:io`'s `HttpClient`, which has no working implementation
/// on Flutter Web — same fix already applied in
/// `emulator_verification_code_client.dart`).
///
/// **Two identity mechanisms, used for different purposes**:
/// - The app's own `FirebaseAuth.instance` sign-in (real, via
///   `signInWithEmailAndPassword`) — this is what the actual widget tree
///   under test authenticates as; every real `httpsCallable` the app
///   itself makes carries this identity.
/// - Raw HTTP with a manually-obtained bearer token (this file's
///   `callCallableRaw`/`signUpEmailPassword`) — used ONLY for fixture
///   setup that needs a SECOND identity the Flutter app is never itself
///   signed in as (e.g. a distinct approver for a device-registration
///   request, since self-approval is server-rejected and
///   `FirebaseAuth.instance` can only hold one signed-in user at a time).
///   Never used for anything the widget-under-test itself should be
///   doing — that always goes through the real gateway classes so the
///   real UI code path is what's actually exercised.
class EmulatorFixtures {
  EmulatorFixtures({
    // Unlike the Node backend suite's own fixture helpers (which
    // deliberately target `demo-abakus-one-emulator`, `.firebaserc`'s
    // default project — a legitimate, self-consistent, backend-only
    // convention), this class exists to set up fixtures for the REAL
    // Flutter app under test, which always resolves to a real, provisioned
    // Firebase project (`abakus-one-dev` under `AppEnvironment.development`
    // — see `lib/firebase_options_development.dart`). Defaulting to the
    // Node convention here caused every raw-HTTP callable this class makes
    // to target the wrong project namespace once the emulator is (correctly)
    // started with `--project=abakus-one-dev` to match the app itself —
    // confirmed via a `Failed to fetch` against
    // `.../demo-abakus-one-emulator/us-central1/registerStaffMember` in a
    // real `flutter drive` run (AP-4 Wave F, 2026-09-04).
    this.projectId = 'abakus-one-dev',
    this.functionsHost = 'http://127.0.0.1:5001',
    this.authHost = 'http://127.0.0.1:9099',
  });

  final String projectId;
  final String functionsHost;
  final String authHost;

  String _fn(String name) => '$functionsHost/$projectId/us-central1/$name';

  /// Raw HTTP callable invocation with an explicit bearer token — mirrors
  /// the Functions callable HTTP protocol Node's own tests use directly.
  Future<Map<String, dynamic>> callCallableRaw(
    String name,
    Map<String, dynamic> data, {
    String? idToken,
  }) async {
    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse(_fn(name)),
            headers: {
              'Content-Type': 'application/json',
              if (idToken != null) 'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'data': data}),
          )
          .timeout(const Duration(seconds: 30));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        final error = body['error'] as Map<String, dynamic>?;
        throw EmulatorFixtureException(
          error?['status'] as String? ?? 'UNKNOWN',
          error?['message'] as String? ?? 'Callable "$name" failed.',
        );
      }
      return (body['result'] as Map<String, dynamic>?) ?? const {};
    } finally {
      client.close();
    }
  }

  Future<({String idToken, String refreshToken, String uid})>
      signUpEmailPassword(String email, String password) async {
    final client = http.Client();
    try {
      final response = await client.post(
        Uri.parse('$authHost/identitytoolkit.googleapis.com/v1/accounts:'
            'signUp?key=fake-api-key'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
            {'email': email, 'password': password, 'returnSecureToken': true}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['idToken'] == null) {
        // EMAIL_EXISTS on a re-run — sign in instead, same account.
        final signInResponse = await client.post(
          Uri.parse('$authHost/identitytoolkit.googleapis.com/v1/accounts:'
              'signInWithPassword?key=fake-api-key'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
            'returnSecureToken': true,
          }),
        );
        final signInBody =
            jsonDecode(signInResponse.body) as Map<String, dynamic>;
        return (
          idToken: signInBody['idToken'] as String,
          refreshToken: signInBody['refreshToken'] as String,
          uid: signInBody['localId'] as String,
        );
      }
      return (
        idToken: body['idToken'] as String,
        refreshToken: body['refreshToken'] as String,
        uid: body['localId'] as String,
      );
    } finally {
      client.close();
    }
  }

  /// A second, distinct staff actor — purely to APPROVE a device
  /// registration request the app's own signed-in admin cannot approve
  /// for itself (self-approval is rejected server-side, an already-tested
  /// real rule). Never signed into `FirebaseAuth.instance` — every call
  /// this actor makes goes through [callCallableRaw] with its own token.
  Future<String> createApproverActor({
    required String organizationId,
    required String branchId,
    required String adminIdToken,
  }) async {
    final random = DateTime.now().microsecondsSinceEpoch;
    final email = 'approver-$random@abakus.e2e';
    final signUp = await signUpEmailPassword(email, 'E2ePass2026!');
    // registerStaffMember creates the initial ROLELESS membership document
    // — assignStaffRole (below) requires one to already exist, and there
    // is no way to create it directly from a Dart client (memberships has
    // no client write path at all; only real callables ever write it).
    await callCallableRaw(
      'registerStaffMember',
      {'organizationId': organizationId, 'email': email},
      idToken: adminIdToken,
    );
    await callCallableRaw(
      'assignStaffRole',
      {
        'organizationId': organizationId,
        'targetUid': signUp.uid,
        'role': 'manager'
      },
      idToken: adminIdToken,
    );
    await callCallableRaw(
      'grantStaffBranchAccess',
      {
        'organizationId': organizationId,
        'targetUid': signUp.uid,
        'branchId': branchId
      },
      idToken: adminIdToken,
    );
    // The role/branch grants above landed as Firestore membership writes,
    // not as custom claims on the token this actor already holds — that
    // token was issued before either grant, so it still carries no
    // organizationAccess/roles/branchAccess at all. syncOwnStaffClaims
    // resolves the real claims from Firestore, then a token refresh is
    // what actually makes them show up on THIS token going forward
    // (mirrors every Node backend test's own identical two-step dance).
    await callCallableRaw('syncOwnStaffClaims', const {},
        idToken: signUp.idToken);
    return refreshIdToken(signUp.refreshToken);
  }

  Future<String> refreshIdToken(String refreshToken) async {
    final client = http.Client();
    try {
      final response = await client.post(
        Uri.parse(
            '$authHost/securetoken.googleapis.com/v1/token?key=fake-api-key'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['id_token'] as String;
    } finally {
      client.close();
    }
  }

  /// Registers, approves, challenges, and issues a real trusted-device
  /// session for the CURRENTLY signed-in `FirebaseAuth` user (the app's
  /// own admin/staff identity), using [approverIdToken] (a distinct
  /// actor, see [createApproverActor]) to respond to the approval
  /// request. Returns the real `deviceId`/`deviceSessionId` the app's
  /// `PosDeviceContext` should be constructed from.
  Future<({String deviceId, String deviceSessionId})>
      issueDeviceSessionForCurrentUser({
    required String organizationId,
    required String branchId,
    required String approverIdToken,
  }) async {
    final currentUser = fb_auth.FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw StateError('No signed-in FirebaseAuth user to issue a device '
          'session for.');
    }
    final callable = functions.FirebaseFunctions.instance;

    // A real key pair genuinely must be generated and used — the
    // emulator-backed `requestDeviceRegistration`/`issueDeviceSession`
    // pair verifies a real signature over the real server-issued nonce;
    // there is no shortcut that skips real cryptographic verification.
    final keyPair = await _generateEd25519KeyPair();

    final registration = await callable
        .httpsCallable('requestDeviceRegistration')
        .call<Map<String, dynamic>>({
      'organizationId': organizationId,
      'branchId': branchId,
      'platform': 'android',
      'publicKeyPem': keyPair.publicKeyPem,
      'signatureAlgorithm': 'ed25519',
      'capabilities': ['POS'],
    });
    final deviceId = registration.data['deviceId'] as String;
    final approvalRequestId = registration.data['approvalRequestId'] as String;

    await callCallableRaw(
      'respondToApprovalRequest',
      {'requestId': approvalRequestId, 'decision': 'approved'},
      idToken: approverIdToken,
    );

    final challenge = await callable
        .httpsCallable('requestDeviceChallenge')
        .call<Map<String, dynamic>>({
      'organizationId': organizationId,
      'branchId': branchId,
      'deviceId': deviceId,
      'purpose': 'issue',
    });
    final nonce = challenge.data['nonce'] as String;
    final challengeId = challenge.data['challengeId'] as String;
    final signature = await keyPair.sign(nonce);

    final session = await callable
        .httpsCallable('issueDeviceSession')
        .call<Map<String, dynamic>>({
      'organizationId': organizationId,
      'branchId': branchId,
      'deviceId': deviceId,
      'challengeId': challengeId,
      'signature': signature,
    });
    final deviceSessionId = session.data['sessionId'] as String;
    return (deviceId: deviceId, deviceSessionId: deviceSessionId);
  }
}

class EmulatorFixtureException implements Exception {
  const EmulatorFixtureException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'EmulatorFixtureException($code): $message';
}

/// RFC 8410 §4 fixed DER prefix for an Ed25519 SPKI — duplicated from
/// `device_key_store.dart`'s own private `_ed25519PublicKeyToSpkiPem`
/// (not exported) rather than imported; this is a small, RFC-fixed,
/// stable structural constant, not business logic.
const List<int> _ed25519SpkiDerPrefix = [
  0x30,
  0x2a,
  0x30,
  0x05,
  0x06,
  0x03,
  0x2b,
  0x65,
  0x70,
  0x03,
  0x21,
  0x00,
];

String _ed25519PublicKeyToSpkiPem(List<int> rawPublicKeyBytes) {
  final der = <int>[..._ed25519SpkiDerPrefix, ...rawPublicKeyBytes];
  final base64Body = base64.encode(der);
  final wrapped = StringBuffer();
  for (var i = 0; i < base64Body.length; i += 64) {
    wrapped.writeln(base64Body.substring(
        i, i + 64 > base64Body.length ? base64Body.length : i + 64));
  }
  return '-----BEGIN PUBLIC KEY-----\n$wrapped-----END PUBLIC KEY-----\n';
}

/// Real Ed25519 key generation/signing via the SAME `package:cryptography`
/// dependency `DeviceKeyStore` uses in production — mirrors
/// `SecureDeviceKeyStore` exactly, except ephemeral (in-memory for the
/// lifetime of one test, never written to secure storage — there is no
/// real device to persist a key for here).
Future<_Ed25519KeyPair> _generateEd25519KeyPair() async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final keyPairData = await keyPair.extract();
  final publicKey = await keyPair.extractPublicKey();
  return _Ed25519KeyPair._(
    _ed25519PublicKeyToSpkiPem(publicKey.bytes),
    keyPairData,
    algorithm,
  );
}

class _Ed25519KeyPair {
  _Ed25519KeyPair._(this.publicKeyPem, this._keyPairData, this._algorithm);

  final String publicKeyPem;
  final SimpleKeyPairData _keyPairData;
  final Ed25519 _algorithm;

  Future<String> sign(String nonce) async {
    final signature =
        await _algorithm.sign(utf8.encode(nonce), keyPair: _keyPairData);
    return base64.encode(signature.bytes);
  }
}
