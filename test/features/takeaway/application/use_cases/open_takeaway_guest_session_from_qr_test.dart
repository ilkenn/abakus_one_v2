import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/qr/data/technical_identity_provider.dart';
import 'package:abakus_one_v2/features/takeaway/application/use_cases/open_takeaway_guest_session_from_qr.dart';
import 'package:abakus_one_v2/features/takeaway/data/takeaway_guest_session_gateway.dart';

class _FakeTechnicalIdentityProvider implements TechnicalIdentityProvider {
  _FakeTechnicalIdentityProvider(this.uid);

  final String uid;
  int callCount = 0;

  @override
  Future<String> ensureSignedIn() async {
    callCount++;
    return uid;
  }

  @override
  String? get currentUid => uid;
}

class _FakeTakeawayGuestSessionGateway implements TakeawayGuestSessionGateway {
  _FakeTakeawayGuestSessionGateway({this.openResult, this.openError});

  final OpenedTakeawayGuestSession? openResult;
  final Object? openError;

  @override
  Future<TakeawayQrPreview> resolveToken(String token) async {
    throw UnimplementedError(
      'Not used by OpenTakeawayGuestSessionFromQr — the preview call is '
      'made separately by the screen before this use case ever runs.',
    );
  }

  @override
  Future<OpenedTakeawayGuestSession> openSession(String token) async {
    if (openError != null) throw openError!;
    return openResult!;
  }
}

void main() {
  final now = DateTime(2026, 8, 11, 12);
  final opened = OpenedTakeawayGuestSession(
    sessionId: 'tags-1',
    organizationId: 'org-1',
    restaurantId: 'restaurant-1',
    branchId: 'branch-1',
    branchDisplayName: 'Abaküs Ortaköy',
    expiresAt: now.add(const Duration(minutes: 30)),
    reused: false,
  );

  test(
      'establishes technical identity before opening the session, and '
      'populates TakeawayGuestContext from the callable response', () async {
    final identity = _FakeTechnicalIdentityProvider('anon-uid-1');
    final gateway = _FakeTakeawayGuestSessionGateway(openResult: opened);
    final useCase = OpenTakeawayGuestSessionFromQr(
      gateway: gateway,
      identityProvider: identity,
    );

    final context = await useCase.call('some-token');

    expect(identity.callCount, 1);
    expect(context.sessionId, 'tags-1');
    expect(context.organizationId, 'org-1');
    expect(context.restaurantId, 'restaurant-1');
    expect(context.branchId, 'branch-1');
    expect(context.branchDisplayName, 'Abaküs Ortaköy');
    expect(context.guestAuthUid, 'anon-uid-1');
  });

  test(
      'reuses an already-signed-in identity (a real customer or a prior '
      'anonymous uid) — never signs in a second time on top of it', () async {
    final identity =
        _FakeTechnicalIdentityProvider('existing-real-customer-uid');
    final gateway = _FakeTakeawayGuestSessionGateway(openResult: opened);
    final useCase = OpenTakeawayGuestSessionFromQr(
      gateway: gateway,
      identityProvider: identity,
    );

    final context = await useCase.call('some-token');

    // The orchestration always delegates the "reuse vs. create" decision
    // to TechnicalIdentityProvider itself and calls it exactly once — this
    // proves the use case never second-guesses or duplicates that
    // decision, and never overwrites an existing (possibly real) session.
    expect(identity.callCount, 1);
    expect(context.guestAuthUid, 'existing-real-customer-uid');
  });

  test(
      'propagates a gateway failure (invalid/expired/notFound token) '
      'without producing a context', () async {
    final identity = _FakeTechnicalIdentityProvider('anon-uid-2');
    final gateway = _FakeTakeawayGuestSessionGateway(
      openError: const TakeawayGuestSessionException(
        'failed-precondition',
        'QR code is expired.',
      ),
    );
    final useCase = OpenTakeawayGuestSessionFromQr(
      gateway: gateway,
      identityProvider: identity,
    );

    await expectLater(
      useCase.call('some-token'),
      throwsA(isA<TakeawayGuestSessionException>()),
    );
  });
}
