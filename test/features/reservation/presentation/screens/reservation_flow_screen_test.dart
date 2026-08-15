import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:abakus_one_v2/core/router/app_routes.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/reservation/data/reservation_gateway.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_area.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_availability_slot.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_branch_info.dart';
import 'package:abakus_one_v2/features/reservation/presentation/providers/reservation_dependencies_provider.dart';
import 'package:abakus_one_v2/features/reservation/presentation/providers/reservation_draft_provider.dart';
import 'package:abakus_one_v2/features/reservation/presentation/screens/reservation_flow_screen.dart';

const _area = ReservationArea(id: 'area-1', displayName: 'Bahçe');

/// A fixed instant (never `DateTime.now()`-relative) so the tap-target
/// label computed in `_driveToReviewStep` can never drift from the label
/// each test configured the fake gateway's sole slot with.
final DateTime _fakeSlotTime = DateTime.utc(2026, 1, 1, 19, 30);

String _timeChipLabel(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

const _branchInfo = ReservationBranchInfo(
  policy: ReservationBranchPolicy(
    maxPartySize: 8,
    slotIntervalMinutes: 30,
    reservationDurationMinutes: 90,
    bookingHorizonDays: 60,
    timezone: 'Europe/Istanbul',
    minimumAdvanceMinutes: 30,
  ),
  areas: [_area],
);

/// Records every call, lets each test independently configure what each
/// method returns/throws, and — for `submitReservation` — can be gated by
/// a [Completer] so a test can hold the first call open long enough to
/// prove a second tap is rejected client-side (Faz R.2's double-submit
/// prevention).
class _FakeReservationGateway implements ReservationGateway {
  ReservationBranchInfo? branchInfoToReturn = _branchInfo;
  ReservationException? branchInfoError;
  int branchInfoCallCount = 0;

  List<ReservationAvailabilitySlot> availabilitySlotsToReturn = const [];

  SubmitReservationResult? submitResultToReturn;
  ReservationException? submitError;
  Completer<void>? submitGate;
  int submitCallCount = 0;
  final List<Map<String, dynamic>> submitCalls = [];

  @override
  Future<ReservationBranchInfo> getReservationBranchInfo({
    required String restaurantId,
    required String branchId,
  }) async {
    branchInfoCallCount++;
    if (branchInfoError != null) throw branchInfoError!;
    return branchInfoToReturn!;
  }

  @override
  Future<List<ReservationAvailabilitySlot>> getReservationAvailability({
    required String restaurantId,
    required String branchId,
    required String areaId,
    required String date,
    required int partySize,
  }) async {
    return availabilitySlotsToReturn;
  }

  @override
  Future<SubmitReservationResult> submitReservation({
    required String submissionKey,
    required String restaurantId,
    required String branchId,
    required String areaId,
    required int partySize,
    required DateTime requestedTime,
    required String contactFirstName,
    required String contactLastName,
    List<ReservationPreorderItem>? preorderItems,
  }) async {
    submitCallCount++;
    submitCalls.add({
      'restaurantId': restaurantId,
      'branchId': branchId,
      'areaId': areaId,
      'partySize': partySize,
      'requestedTime': requestedTime,
      'contactFirstName': contactFirstName,
      'contactLastName': contactLastName,
      'preorderItems': preorderItems,
    });
    if (submitGate != null) await submitGate!.future;
    if (submitError != null) throw submitError!;
    return submitResultToReturn!;
  }

  @override
  Future<void> respondToProposedChange({
    required String reservationId,
    required String proposalId,
    required bool accept,
  }) {
    throw UnimplementedError('not used by ReservationFlowScreen');
  }

  @override
  Future<void> cancelReservation({
    required String reservationId,
    String? reasonCode,
  }) {
    throw UnimplementedError('not used by ReservationFlowScreen');
  }
}

class _FakeRealCustomerAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return AuthState(
      isAuthenticated: true,
      isGuest: false,
      session: AuthSession(
        uid: 'uid-1',
        phoneNumber: '+905551112233',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      ),
    );
  }
}

class _FakeGuestAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState(isAuthenticated: false, isGuest: true);
}

String? _lastConfirmationReservationId;

Future<ProviderContainer> _pumpFlow(
  WidgetTester tester, {
  required _FakeReservationGateway gateway,
  AuthNotifier Function()? authNotifierBuilder,
}) async {
  _lastConfirmationReservationId = null;
  final router = GoRouter(
    initialLocation: AppRoutes.reservationPrefix,
    routes: [
      GoRoute(
        path: AppRoutes.reservationPrefix,
        builder: (context, state) => const ReservationFlowScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.reservationConfirmationPrefix}/:reservationId',
        builder: (context, state) {
          _lastConfirmationReservationId =
              state.pathParameters['reservationId'];
          return Scaffold(
            body: Text('Confirmation:${state.pathParameters['reservationId']}'),
          );
        },
      ),
    ],
  );

  // The Signature Calendar's day grid doesn't fit the default 800x600 test
  // surface without scrolling, and unlike the calendar's own isolated
  // widget test, this screen's date step can't just be wrapped in an extra
  // scroll view — it's already the real production tree. A taller surface
  // instead, so every day cell is actually reachable by `tester.tap`.
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;

  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reservationGatewayProvider.overrideWithValue(gateway),
        authProvider.overrideWith(
            authNotifierBuilder ?? _FakeRealCustomerAuthNotifier.new),
      ],
      child: Builder(builder: (context) {
        container = ProviderScope.containerOf(context, listen: false);
        return MaterialApp.router(routerConfig: router);
      }),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Drives the flow from step 0 (party size) through to step 5 (review),
/// picking today's date (always inside the wide-open policy horizon used
/// here) and the sole fake availability slot, and skips the optional
/// preorder step. Leaves the review step's name fields untouched.
Future<void> _driveToReviewStep(WidgetTester tester) async {
  // Step 0 — party size: default value (1) is already valid.
  await tester.tap(find.text('Devam Et'));
  await tester.pumpAndSettle();

  // Step 1 — area.
  await tester.tap(find.text(_area.displayName));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Devam Et'));
  await tester.pumpAndSettle();

  // Step 2 — date: tap today's day cell.
  final today = DateTime.now();
  await tester.tap(find.text('${today.day}').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Devam Et'));
  await tester.pumpAndSettle();

  // Step 3 — time: tap the one fake slot's chip.
  await tester.tap(find.text(_timeChipLabel(_fakeSlotTime)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Devam Et'));
  await tester.pumpAndSettle();

  // Step 4 — preorder: skip (cart empty).
  await tester.tap(find.text('Şimdilik Geç'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'an unauthenticated/guest visitor sees the login-required gate, '
      'and branch info is never even requested', (tester) async {
    final gateway = _FakeReservationGateway();
    await _pumpFlow(tester,
        gateway: gateway, authNotifierBuilder: _FakeGuestAuthNotifier.new);

    expect(find.text('Giriş Yap'), findsOneWidget);
    expect(
      find.text(
          'Rezervasyon oluşturmak için telefon numaranızla giriş yapmanız gerekiyor.'),
      findsOneWidget,
    );
    expect(gateway.branchInfoCallCount, 0);
  });

  testWidgets('a real customer sees the branch-info loading state first',
      (tester) async {
    final gateway = _FakeReservationGateway();
    final gate = Completer<ReservationBranchInfo>();
    gateway.branchInfoToReturn = null;

    final router = GoRouter(
      initialLocation: AppRoutes.reservationPrefix,
      routes: [
        GoRoute(
          path: AppRoutes.reservationPrefix,
          builder: (context, state) => const ReservationFlowScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reservationGatewayProvider.overrideWithValue(
            _DelayedBranchInfoGateway(gate.future),
          ),
          authProvider.overrideWith(_FakeRealCustomerAuthNotifier.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    expect(find.text('Rezervasyon bilgileri yükleniyor...'), findsOneWidget);

    gate.complete(_branchInfo);
    await tester.pumpAndSettle();
    expect(find.text('Kaç Kişilik?'), findsOneWidget);
  });

  testWidgets(
      'a branch-info failure shows a customer-safe mapped error with retry',
      (tester) async {
    final gateway = _FakeReservationGateway()
      ..branchInfoError =
          const ReservationException('not-found', 'branch missing');
    await _pumpFlow(tester, gateway: gateway);

    expect(
      find.text('Seçtiğiniz şube veya alan bulunamadı. Lütfen tekrar deneyin.'),
      findsOneWidget,
    );
    expect(find.text('Tekrar Dene'), findsOneWidget);

    gateway.branchInfoError = null;
    await tester.tap(find.text('Tekrar Dene'));
    await tester.pumpAndSettle();

    expect(find.text('Kaç Kişilik?'), findsOneWidget);
    expect(gateway.branchInfoCallCount, 2);
  });

  testWidgets('a real customer starts on step 1 — party size', (tester) async {
    final gateway = _FakeReservationGateway();
    await _pumpFlow(tester, gateway: gateway);

    expect(find.text('Kaç Kişilik?'), findsOneWidget);
  });

  testWidgets('stepping forward through area/date/time updates the summary bar',
      (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(
          time: _fakeSlotTime,
          available: true,
        ),
      ];
    await _pumpFlow(tester, gateway: gateway);

    await tester.tap(find.text('Devam Et'));
    await tester.pumpAndSettle();
    expect(find.text('Hangi Alan?'), findsOneWidget);

    await tester.tap(find.text(_area.displayName));
    await tester.pumpAndSettle();
    expect(find.text(_area.displayName), findsWidgets);

    await tester.tap(find.text('Devam Et'));
    await tester.pumpAndSettle();
    expect(find.text('Hangi Tarih?'), findsOneWidget);
  });

  testWidgets(
      'submitting the review step sends the exact draft/preorder payload to '
      'the gateway and navigates to the confirmation route on success',
      (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(
          time: _fakeSlotTime,
          available: true,
        ),
      ]
      ..submitResultToReturn = const SubmitReservationResult(
        reservationId: 'reservation-abc',
        status: 'pendingRestaurantApproval',
        requestedAvailabilityAtSubmission: 'available',
        preorderOrderId: null,
        duplicate: false,
      );

    final container = await _pumpFlow(tester, gateway: gateway);
    await _driveToReviewStep(tester);

    expect(find.text('Özet'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Yılmaz');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.pumpAndSettle();

    expect(gateway.submitCallCount, 1);
    final call = gateway.submitCalls.single;
    expect(call['restaurantId'], reservationRestaurantId);
    expect(call['branchId'], reservationBranchId);
    expect(call['areaId'], _area.id);
    expect(call['partySize'], 1);
    expect(call['contactFirstName'], 'Ada');
    expect(call['contactLastName'], 'Yılmaz');
    expect(call['preorderItems'], isNull);

    expect(_lastConfirmationReservationId, 'reservation-abc');

    // The draft/preorder cart are reset after a successful submit — proven
    // via the same container the screen itself reads from.
    expect(container.read(reservationDraftProvider).partySize, isNull);
  });

  testWidgets(
      'tapping submit twice in quick succession — before the first call '
      'resolves — only ever reaches the gateway once', (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(
          time: _fakeSlotTime,
          available: true,
        ),
      ]
      ..submitGate = Completer<void>()
      ..submitResultToReturn = const SubmitReservationResult(
        reservationId: 'reservation-xyz',
        status: 'pendingRestaurantApproval',
        requestedAvailabilityAtSubmission: 'available',
        preorderOrderId: null,
        duplicate: false,
      );

    await _pumpFlow(tester, gateway: gateway);
    await _driveToReviewStep(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Yılmaz');
    await tester.pumpAndSettle();

    // Two taps back-to-back, no pump in between — the second tap still
    // resolves to the same not-yet-rebuilt button, whose callback's own
    // `if (_isSubmitting) return;` guard (set synchronously by the first
    // tap, before either awaits) is what must reject it.
    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.tap(find.text('Rezervasyon Talebini Gönder'));

    gateway.submitGate!.complete();
    await tester.pumpAndSettle();

    expect(gateway.submitCallCount, 1);
  });

  testWidgets(
      'a submit failure shows the mapped Turkish error and lets the customer '
      'retry — the draft is not reset, so the flow is not lost',
      (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(
          time: _fakeSlotTime,
          available: true,
        ),
      ]
      ..submitError = const ReservationException(
          'failed-precondition', 'This slot is full');

    await _pumpFlow(tester, gateway: gateway);
    await _driveToReviewStep(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Yılmaz');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.pumpAndSettle();

    expect(
      find.text(
          'Bu saat için az önce bir değişiklik oldu. Lütfen tekrar deneyin.'),
      findsOneWidget,
    );
    // Still on the review step — submit is re-enabled, not stuck disabled.
    expect(find.text('Rezervasyon Talebini Gönder'), findsOneWidget);
    expect(gateway.submitCallCount, 1);

    gateway.submitError = null;
    gateway.submitResultToReturn = const SubmitReservationResult(
      reservationId: 'reservation-retry',
      status: 'pendingRestaurantApproval',
      requestedAvailabilityAtSubmission: 'available',
      preorderOrderId: null,
      duplicate: false,
    );
    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.pumpAndSettle();

    expect(_lastConfirmationReservationId, 'reservation-retry');
    expect(gateway.submitCallCount, 2);
  });
}

class _DelayedBranchInfoGateway implements ReservationGateway {
  _DelayedBranchInfoGateway(this._future);

  final Future<ReservationBranchInfo> _future;

  @override
  Future<ReservationBranchInfo> getReservationBranchInfo({
    required String restaurantId,
    required String branchId,
  }) {
    return _future;
  }

  @override
  Future<List<ReservationAvailabilitySlot>> getReservationAvailability({
    required String restaurantId,
    required String branchId,
    required String areaId,
    required String date,
    required int partySize,
  }) async =>
      const [];

  @override
  Future<SubmitReservationResult> submitReservation({
    required String submissionKey,
    required String restaurantId,
    required String branchId,
    required String areaId,
    required int partySize,
    required DateTime requestedTime,
    required String contactFirstName,
    required String contactLastName,
    List<ReservationPreorderItem>? preorderItems,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> respondToProposedChange({
    required String reservationId,
    required String proposalId,
    required bool accept,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> cancelReservation({
    required String reservationId,
    String? reasonCode,
  }) {
    throw UnimplementedError();
  }
}
