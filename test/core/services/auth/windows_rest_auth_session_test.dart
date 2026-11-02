import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/services/auth/identity_toolkit_rest_auth_client.dart';
import 'package:abakus_one_v2/core/services/auth/windows_rest_auth_session.dart';

class _FakeIdentityToolkitRestAuthClient
    implements IdentityToolkitRestAuthClient {
  _FakeIdentityToolkitRestAuthClient({this.refreshResult, this.refreshError});

  RestAuthTokens? refreshResult;
  IdentityToolkitAuthException? refreshError;
  int refreshCallCount = 0;

  @override
  Future<RestAuthTokens> signInWithPassword({
    required String email,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<RestAuthTokens> createAccount({
    required String email,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<RestAuthTokens> refresh(String refreshToken) async {
    refreshCallCount += 1;
    if (refreshError != null) throw refreshError!;
    return refreshResult!;
  }
}

RestAuthTokens _tokens({required DateTime expiresAt, String idToken = 'id-1'}) {
  return RestAuthTokens(
    idToken: idToken,
    refreshToken: 'refresh-1',
    localId: 'uid-1',
    expiresAt: expiresAt,
  );
}

void main() {
  // `WindowsRestAuthSession` is a static, process-wide holder — reset it
  // around every test so none leak state into another.
  setUp(() => WindowsRestAuthSession.clear());
  tearDown(() => WindowsRestAuthSession.clear());

  test('isActive/uid are false/null with no session set', () {
    expect(WindowsRestAuthSession.isActive, isFalse);
    expect(WindowsRestAuthSession.uid, isNull);
  });

  test('set makes a session active and exposes its uid', () {
    WindowsRestAuthSession.set(
      _tokens(expiresAt: DateTime.now().add(const Duration(hours: 1))),
    );
    expect(WindowsRestAuthSession.isActive, isTrue);
    expect(WindowsRestAuthSession.uid, 'uid-1');
  });

  test('clear ends the session', () {
    WindowsRestAuthSession.set(
      _tokens(expiresAt: DateTime.now().add(const Duration(hours: 1))),
    );
    WindowsRestAuthSession.clear();
    expect(WindowsRestAuthSession.isActive, isFalse);
  });

  group('currentIdToken', () {
    test('returns null with no session active, never calls the client',
        () async {
      final client = _FakeIdentityToolkitRestAuthClient();
      final token = await WindowsRestAuthSession.currentIdToken(client: client);
      expect(token, isNull);
      expect(client.refreshCallCount, 0);
    });

    test('returns the cached token unchanged when well within its expiry',
        () async {
      WindowsRestAuthSession.set(
        _tokens(expiresAt: DateTime.now().add(const Duration(hours: 1))),
      );
      final client = _FakeIdentityToolkitRestAuthClient();

      final token = await WindowsRestAuthSession.currentIdToken(client: client);

      expect(token, 'id-1');
      expect(client.refreshCallCount, 0);
    });

    test(
        'refreshes proactively once within the expiry buffer, even though '
        'not technically expired yet', () async {
      WindowsRestAuthSession.set(
        _tokens(expiresAt: DateTime.now().add(const Duration(seconds: 30))),
      );
      final client = _FakeIdentityToolkitRestAuthClient(
        refreshResult: _tokens(
          idToken: 'id-2',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      final token = await WindowsRestAuthSession.currentIdToken(client: client);

      expect(token, 'id-2');
      expect(client.refreshCallCount, 1);
    });

    test('a failed refresh clears the session and returns null', () async {
      WindowsRestAuthSession.set(
        _tokens(expiresAt: DateTime.now().subtract(const Duration(seconds: 1))),
      );
      final client = _FakeIdentityToolkitRestAuthClient(
        refreshError: const IdentityToolkitAuthException('unknown', 'nope'),
      );

      final token = await WindowsRestAuthSession.currentIdToken(client: client);

      expect(token, isNull);
      expect(WindowsRestAuthSession.isActive, isFalse);
    });
  });

  group('forceRefresh', () {
    test('returns null with no session active, never calls the client',
        () async {
      final client = _FakeIdentityToolkitRestAuthClient();
      final token = await WindowsRestAuthSession.forceRefresh(client: client);
      expect(token, isNull);
      expect(client.refreshCallCount, 0);
    });

    test(
        'always refreshes, even when the cached token is nowhere near '
        'expiry — detects a revoked role the way getIdTokenResult(true) '
        'would natively', () async {
      WindowsRestAuthSession.set(
        _tokens(expiresAt: DateTime.now().add(const Duration(hours: 1))),
      );
      final client = _FakeIdentityToolkitRestAuthClient(
        refreshResult: _tokens(
          idToken: 'id-fresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      final token = await WindowsRestAuthSession.forceRefresh(client: client);

      expect(token, 'id-fresh');
      expect(client.refreshCallCount, 1);
    });

    test('a failed force refresh clears the session and returns null',
        () async {
      WindowsRestAuthSession.set(
        _tokens(expiresAt: DateTime.now().add(const Duration(hours: 1))),
      );
      final client = _FakeIdentityToolkitRestAuthClient(
        refreshError: const IdentityToolkitAuthException('unknown', 'nope'),
      );

      final token = await WindowsRestAuthSession.forceRefresh(client: client);

      expect(token, isNull);
      expect(WindowsRestAuthSession.isActive, isFalse);
    });
  });
}
