import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:abakus_one_v2/core/router/app_routes.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/campaigns/data/campaign_gateway.dart';
import 'package:abakus_one_v2/features/campaigns/domain/models/campaign.dart';
import 'package:abakus_one_v2/features/campaigns/presentation/providers/campaigns_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/takeaway_checkout_screen.dart'
    show computeClientEstimatedMaxBoncuk;
import 'package:abakus_one_v2/features/loyalty/data/loyalty_gateway.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_account_snapshot.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_history_entry.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_reward.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/providers/loyalty_providers.dart';
import 'package:abakus_one_v2/features/reservation/data/reservation_gateway.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_area.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_availability_slot.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_branch_info.dart';
import 'package:abakus_one_v2/features/reservation/presentation/providers/preorder_cart_provider.dart';
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
  int? lastRequestedBoncukAmount;
  String? lastSelectedRewardId;
  String? lastSelectedCampaignId;

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
    int requestedBoncukAmount = 0,
    String? selectedRewardId,
    String? selectedCampaignId,
  }) async {
    submitCallCount++;
    lastRequestedBoncukAmount = requestedBoncukAmount;
    lastSelectedRewardId = selectedRewardId;
    lastSelectedCampaignId = selectedCampaignId;
    submitCalls.add({
      'restaurantId': restaurantId,
      'branchId': branchId,
      'areaId': areaId,
      'partySize': partySize,
      'requestedTime': requestedTime,
      'contactFirstName': contactFirstName,
      'contactLastName': contactLastName,
      'preorderItems': preorderItems,
      'requestedBoncukAmount': requestedBoncukAmount,
      'selectedRewardId': selectedRewardId,
      'selectedCampaignId': selectedCampaignId,
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

/// Boncuk Loyalty P6-B — mirrors `takeaway_checkout_screen_test.dart`'s/
/// `delivery_checkout_screen_test.dart`'s own private `_FakeLoyaltyGateway`
/// exactly (duplicated per this codebase's established per-file
/// test-double convention, not shared).
class _FakeLoyaltyGateway implements LoyaltyGateway {
  _FakeLoyaltyGateway({
    LoyaltyAccountSnapshot? snapshot,
    this.snapshotError,
    this.neverCompleteSnapshot = false,
    this.rewards = const [],
    this.rewardCatalogError,
  }) : snapshot = snapshot ?? LoyaltyAccountSnapshot.zero;

  LoyaltyAccountSnapshot snapshot;
  LoyaltyGatewayException? snapshotError;
  bool neverCompleteSnapshot;
  int snapshotCalls = 0;

  /// Boncuk Loyalty P7-D (2026-08-24) — the real, server-authoritative
  /// reward list this fake returns; mirrors
  /// `takeaway_checkout_screen_test.dart`'s own `_FakeLoyaltyGateway`.
  List<LoyaltyReward> rewards;
  LoyaltyGatewayException? rewardCatalogError;
  int rewardCatalogCalls = 0;

  @override
  Future<LoyaltyAccountSnapshot> getSnapshot() async {
    snapshotCalls += 1;
    if (neverCompleteSnapshot) {
      return Completer<LoyaltyAccountSnapshot>().future;
    }
    if (snapshotError != null) throw snapshotError!;
    return snapshot;
  }

  @override
  Future<LoyaltyHistoryPage> getHistory({int? pageSize, String? cursor}) async {
    return LoyaltyHistoryPage.empty;
  }

  @override
  Future<List<LoyaltyReward>> getRewardCatalog() async {
    rewardCatalogCalls += 1;
    if (rewardCatalogError != null) throw rewardCatalogError!;
    return rewards;
  }
}

/// A well-formed, non-default snapshot for Boncuk reservation-preorder
/// tests — mirrors `takeaway_checkout_screen_test.dart`'s own
/// `_boncukSnapshot` exactly (a non-default redemption rate/cap
/// deliberately, so a test can prove the UI reads
/// [LoyaltyAccountSnapshot]'s own fields rather than a Flutter constant).
LoyaltyAccountSnapshot _boncukSnapshot({
  int spendableBalance = 500,
  int boncukDebt = 0,
  int redemptionValueMinorUnitsPerBoncuk = 150,
  int maxRedemptionBasisPoints = 4000,
}) {
  return LoyaltyAccountSnapshot(
    spendableBalance: spendableBalance,
    boncukDebt: boncukDebt,
    earningRemainderMinorUnits: 0,
    minorUnitsUntilNextBoncuk: 5000,
    lifetimeEarned: spendableBalance,
    lifetimeRedeemed: 0,
    earningSpendMinorUnits: 5000,
    earningBoncukAmount: 5,
    redemptionValueMinorUnitsPerBoncuk: redemptionValueMinorUnitsPerBoncuk,
    maxRedemptionBasisPoints: maxRedemptionBasisPoints,
  );
}

/// Boncuk Loyalty P7-D (2026-08-24) — a well-formed [LoyaltyReward],
/// eligible for the preorder cart item `'p1'` seeded by
/// [_driveToReviewStepWithPreorder] by default. Mirrors
/// `delivery_checkout_screen_test.dart`'s own `_catalogReward` exactly.
LoyaltyReward _catalogReward({
  String rewardId = 'reward-1',
  String title = 'Test Ödülü',
  String description = 'Bir test ödülü.',
  List<String> eligibleProductIds = const ['p1'],
  List<String> eligibleChannels = const [
    'dineIn',
    'takeaway',
    'delivery',
    'reservationPreorder',
  ],
  int boncukCost = 100,
  int sortOrder = 0,
  int version = 1,
}) {
  return LoyaltyReward(
    rewardId: rewardId,
    title: title,
    description: description,
    rewardType: 'explicitProductSet',
    eligibleProductIds: eligibleProductIds,
    eligibleChannels: eligibleChannels,
    boncukCost: boncukCost,
    sortOrder: sortOrder,
    version: version,
  );
}

/// Server-Authoritative Campaign Engine P8-C.2 (2026-08-25) — mirrors
/// `delivery_checkout_screen_test.dart`'s own `_FakeCampaignGateway` exactly.
class _FakeCampaignGateway implements CampaignGateway {
  _FakeCampaignGateway({this.campaigns = const [], this.error});

  List<Campaign> campaigns;
  CampaignGatewayException? error;
  int calls = 0;

  @override
  Future<List<Campaign>> getActiveCampaigns() async {
    calls += 1;
    if (error != null) throw error!;
    return campaigns;
  }
}

/// A well-formed, reservationPreorder-eligible [Campaign] for checkout
/// tests — mirrors `delivery_checkout_screen_test.dart`'s own
/// `_testCampaign` exactly, default channel adapted to this screen's own.
Campaign _testCampaign({
  String campaignId = 'camp-1',
  String title = 'Test Kampanya',
  String description = 'Bir test kampanyası.',
  List<String> eligibleChannels = const ['reservationPreorder'],
  int? minimumBasketMinorUnits,
  List<String>? eligibleProductIds,
  int sortOrder = 0,
}) {
  return Campaign(
    campaignId: campaignId,
    title: title,
    description: description,
    campaignType: 'percentageDiscount',
    rule: const CampaignRule(
      mechanic: 'percentage',
      scopeKind: 'order',
      percentBasisPoints: 1000,
    ),
    eligibleChannels: eligibleChannels,
    eligibleProductIds: eligibleProductIds,
    eligibleCategoryIds: null,
    minimumBasketMinorUnits: minimumBasketMinorUnits,
    schedule: const CampaignSchedule(mode: 'oneTime'),
    sortOrder: sortOrder,
    version: 1,
  );
}

String? _lastConfirmationReservationId;

Future<ProviderContainer> _pumpFlow(
  WidgetTester tester, {
  required _FakeReservationGateway gateway,
  AuthNotifier Function()? authNotifierBuilder,
  // ignore: library_private_types_in_public_api
  _FakeLoyaltyGateway? loyaltyGateway,
  // ignore: library_private_types_in_public_api
  _FakeCampaignGateway? campaignGateway,
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
        if (loyaltyGateway != null)
          loyaltyGatewayProvider.overrideWithValue(loyaltyGateway),
        campaignGatewayProvider
            .overrideWithValue(campaignGateway ?? _FakeCampaignGateway()),
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

/// Boncuk Loyalty P6-B — identical to [_driveToReviewStep] through step 3,
/// but seeds [preorderCartProvider] directly (bypassing the real
/// menu/product-detail UI, which needs a full catalog this test doesn't
/// set up — mirrors `preorderCartTotalPriceProvider`'s own reliance on the
/// same provider) before reaching step 4, then taps 'Devam Et' (the
/// non-empty-cart label) instead of 'Şimdilik Geç'.
Future<void> _driveToReviewStepWithPreorder(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.tap(find.text('Devam Et'));
  await tester.pumpAndSettle();

  await tester.tap(find.text(_area.displayName));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Devam Et'));
  await tester.pumpAndSettle();

  final today = DateTime.now();
  await tester.tap(find.text('${today.day}').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Devam Et'));
  await tester.pumpAndSettle();

  await tester.tap(find.text(_timeChipLabel(_fakeSlotTime)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Devam Et'));
  await tester.pumpAndSettle();

  // Step 4 — preorder: seed the cart directly, then continue.
  container.read(preorderCartProvider.notifier).addToCart(
        id: 'p1',
        name: 'Falafel Bowl',
        desc: '',
        price: 120.0,
        quantity: 2,
      );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Devam Et'));
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

  // =========================================================================
  // Boncuk Loyalty P6-B (2026-08-24) — reservation preorder Boncuk checkout,
  // reusing `BoncukRedemptionCard`/`computeClientEstimatedMaxBoncuk`
  // UNCHANGED (already exhaustively proven correct by takeaway's own P4-E-B
  // A-R suite and delivery's own P5-B mirror) — this file's job is to prove
  // the WIRING into `ReservationFlowScreen` is correct, not re-prove the
  // shared widget/estimate-function's own internal behavior a third time.
  // =========================================================================

  testWidgets(
      'no preorder in cart -> the Boncuk card never appears on the review step',
      (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ];
    await _pumpFlow(
      tester,
      gateway: gateway,
      loyaltyGateway: _FakeLoyaltyGateway(snapshot: _boncukSnapshot()),
    );
    await _driveToReviewStep(tester);

    expect(find.byKey(const Key('boncukRedemptionCard')), findsNothing);
  });

  testWidgets(
      'a preorder in cart with balance > 0 -> the Boncuk card is available',
      (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ];
    final container = await _pumpFlow(
      tester,
      gateway: gateway,
      loyaltyGateway: _FakeLoyaltyGateway(snapshot: _boncukSnapshot()),
    );
    await _driveToReviewStepWithPreorder(tester, container);

    expect(find.byKey(const Key('boncukRedemptionCard')), findsOneWidget);
    expect(find.byKey(const Key('boncukToggle')), findsOneWidget);
  });

  testWidgets('toggle off -> requestedBoncukAmount sent is 0', (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ]
      ..submitResultToReturn = const SubmitReservationResult(
        reservationId: 'reservation-boncuk-1',
        status: 'pendingRestaurantApproval',
        requestedAvailabilityAtSubmission: 'available',
        preorderOrderId: 'order-1',
        duplicate: false,
      );
    final container = await _pumpFlow(
      tester,
      gateway: gateway,
      loyaltyGateway: _FakeLoyaltyGateway(snapshot: _boncukSnapshot()),
    );
    await _driveToReviewStepWithPreorder(tester, container);
    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Yılmaz');
    await tester.pumpAndSettle();
    // Toggle stays off — the default state.

    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.pumpAndSettle();

    expect(gateway.lastRequestedBoncukAmount, 0);
  });

  testWidgets(
      'toggle on -> minimum selected amount is 1, MAX uses the order cap',
      (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ]
      ..submitResultToReturn = const SubmitReservationResult(
        reservationId: 'reservation-boncuk-2',
        status: 'pendingRestaurantApproval',
        requestedAvailabilityAtSubmission: 'available',
        preorderOrderId: 'order-2',
        duplicate: false,
      );
    final container = await _pumpFlow(
      tester,
      gateway: gateway,
      loyaltyGateway: _FakeLoyaltyGateway(
        snapshot: _boncukSnapshot(
          spendableBalance: 500,
          redemptionValueMinorUnitsPerBoncuk: 150,
          maxRedemptionBasisPoints: 4000,
        ),
      ),
    );
    await _driveToReviewStepWithPreorder(tester, container);
    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Yılmaz');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();
    expect(find.text('1 Boncuk'), findsOneWidget);

    // Cart total is 240 TL (120 x 2, seeded by _driveToReviewStepWithPreorder)
    // -> 24000 minor units. maxRedemptionValueMinorUnits = 24000*4000/10000 =
    // 9600. maxUsableBoncukByOrderCap = 9600/150 = 64. min(500, 64) = 64.
    expect(computeClientEstimatedMaxBoncuk(_boncukSnapshot(), 240.0), 64);

    await tester.tap(find.byKey(const Key('boncukMaxButton')));
    await tester.pumpAndSettle();
    expect(find.text('64 Boncuk'), findsOneWidget);

    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.pumpAndSettle();
    expect(gateway.lastRequestedBoncukAmount, 64);
    expect(_lastConfirmationReservationId, 'reservation-boncuk-2');
  });

  testWidgets('zero spendable balance shows the quiet zero state, no toggle',
      (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ];
    final container = await _pumpFlow(
      tester,
      gateway: gateway,
      loyaltyGateway: _FakeLoyaltyGateway(
        snapshot: _boncukSnapshot(spendableBalance: 0),
      ),
    );
    await _driveToReviewStepWithPreorder(tester, container);

    expect(find.byKey(const Key('boncukZeroState')), findsOneWidget);
    expect(find.byKey(const Key('boncukToggle')), findsNothing);
  });

  testWidgets(
      'snapshot loading renders the inline premium skeleton on the review step',
      (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ];
    final container = await _pumpFlow(
      tester,
      gateway: gateway,
      loyaltyGateway: _FakeLoyaltyGateway(neverCompleteSnapshot: true),
    );
    // Deliberately no pumpAndSettle for the drive helper's own steps beyond
    // the last one — the snapshot future never completes, so we only need
    // one settled frame once the review step itself is reachable.
    await _driveToReviewStepWithPreorder(tester, container);

    expect(find.byKey(const Key('boncukCardSkeleton')), findsOneWidget);
  });

  testWidgets(
      'snapshot load failure shows scoped retry, ordinary reservation '
      'submission remains fully usable without Boncuk', (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ]
      ..submitResultToReturn = const SubmitReservationResult(
        reservationId: 'reservation-boncuk-k',
        status: 'pendingRestaurantApproval',
        requestedAvailabilityAtSubmission: 'available',
        preorderOrderId: 'order-k',
        duplicate: false,
      );
    final container = await _pumpFlow(
      tester,
      gateway: gateway,
      loyaltyGateway: _FakeLoyaltyGateway(
        snapshotError: const LoyaltyGatewayException(
          'internal',
          'Boncuk bakiyenize şu anda ulaşılamıyor.',
        ),
      ),
    );
    await _driveToReviewStepWithPreorder(tester, container);
    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Yılmaz');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('boncukCardError')), findsOneWidget);

    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.pumpAndSettle();

    expect(_lastConfirmationReservationId, 'reservation-boncuk-k');
    expect(gateway.lastRequestedBoncukAmount, 0);
  });

  testWidgets(
      'a cart change that lowers the estimated max below the current selection '
      'NEVER silently clamps to a smaller nonzero amount — submission is '
      'disabled and an explicit recovery notice is shown', (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ];
    final container = await _pumpFlow(
      tester,
      gateway: gateway,
      loyaltyGateway: _FakeLoyaltyGateway(
        snapshot: _boncukSnapshot(
          spendableBalance: 500,
          redemptionValueMinorUnitsPerBoncuk: 100,
          maxRedemptionBasisPoints: 5000,
        ),
      ),
    );
    await _driveToReviewStepWithPreorder(tester, container);
    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Yılmaz');
    await tester.pumpAndSettle();

    // Cart total 240 TL -> max = min(500, floor(24000*5000/10000)/100) = 120.
    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('boncukMaxButton')));
    await tester.pumpAndSettle();
    expect(find.text('120 Boncuk'), findsOneWidget);

    // Halve the cart total (quantity 2 -> 1), lowering the order cap to 60.
    container
        .read(preorderCartProvider.notifier)
        .updateQuantity('p1', '', '', 1);
    await tester.pumpAndSettle();

    // Selection must remain exactly 120 — never silently reduced.
    expect(find.text('120 Boncuk'), findsOneWidget);
    expect(
        find.byKey(const Key('boncukInvalidSelectionNotice')), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Rezervasyon Talebini Gönder'));
    expect(button.onPressed, isNull);
  });

  testWidgets(
      'a Boncuk-specific server rejection never auto-resubmits without '
      'Boncuk — the customer must explicitly tap submit again', (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ]
      ..submitError = const ReservationException(
        'invalid-argument',
        'requestedBoncukAmount exceeds the maximum usable Boncuk for this order.',
        boncukErrorReason: 'boncuk/exceeds-max-usable',
      );
    final container = await _pumpFlow(
      tester,
      gateway: gateway,
      loyaltyGateway: _FakeLoyaltyGateway(snapshot: _boncukSnapshot()),
    );
    await _driveToReviewStepWithPreorder(tester, container);
    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Yılmaz');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.pumpAndSettle();

    expect(gateway.submitCallCount, 1);
    expect(
      find.textContaining('Bilgileri güncelledik; tekrar seçim yapın'),
      findsOneWidget,
    );
    final toggle = tester.widget<Switch>(find.byKey(const Key('boncukToggle')));
    expect(toggle.value, isFalse);

    gateway.submitError = null;
    gateway.submitResultToReturn = const SubmitReservationResult(
      reservationId: 'reservation-boncuk-retry',
      status: 'pendingRestaurantApproval',
      requestedAvailabilityAtSubmission: 'available',
      preorderOrderId: 'order-retry',
      duplicate: false,
    );
    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.pumpAndSettle();
    expect(gateway.submitCallCount, 2);
    expect(gateway.lastRequestedBoncukAmount, 0);
    expect(_lastConfirmationReservationId, 'reservation-boncuk-retry');
  });

  testWidgets(
      'loyalty snapshot is invalidated after a successful Boncuk redemption '
      'so the customer\'s displayed balance refreshes', (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ]
      ..submitResultToReturn = const SubmitReservationResult(
        reservationId: 'reservation-boncuk-3',
        status: 'pendingRestaurantApproval',
        requestedAvailabilityAtSubmission: 'available',
        preorderOrderId: 'order-3',
        duplicate: false,
      );
    final loyaltyGateway = _FakeLoyaltyGateway(snapshot: _boncukSnapshot());
    final container = await _pumpFlow(
      tester,
      gateway: gateway,
      loyaltyGateway: loyaltyGateway,
    );
    await _driveToReviewStepWithPreorder(tester, container);
    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Yılmaz');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();
    final callsBeforeSubmit = loyaltyGateway.snapshotCalls;

    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.pumpAndSettle();

    expect(
      loyaltyGateway.snapshotCalls,
      greaterThan(callsBeforeSubmit),
      reason:
          'ref.invalidate(loyaltySnapshotProvider) must trigger a fresh fetch',
    );
  });

  // =========================================================================
  // Boncuk Loyalty Program P7-D (2026-08-24) — the Reservation Preorder
  // catalog-reward checkout wiring: [CatalogRewardCard], mutual exclusivity
  // with cash Boncuk redemption. The server-confirmed success summary itself
  // is proven in `reservation_confirmation_screen_test.dart` (a separate
  // screen this flow only navigates to) — this file's job, per its own
  // established Boncuk-section convention above, is the WIRING only.
  // =========================================================================

  testWidgets(
      'P7-D reward-catalog load failure never blocks ordinary reservation '
      'submission — the catalog reward card is simply absent', (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ]
      ..submitResultToReturn = const SubmitReservationResult(
        reservationId: 'reservation-reward-catalog-error',
        status: 'pendingRestaurantApproval',
        requestedAvailabilityAtSubmission: 'available',
        preorderOrderId: 'order-reward-catalog-error',
        duplicate: false,
      );
    final container = await _pumpFlow(
      tester,
      gateway: gateway,
      loyaltyGateway: _FakeLoyaltyGateway(
        rewardCatalogError:
            const LoyaltyGatewayException('internal', 'Ödüller yüklenemedi.'),
      ),
    );
    await _driveToReviewStepWithPreorder(tester, container);

    expect(find.byKey(const Key('catalogRewardCardError')), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Yılmaz');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.pumpAndSettle();

    expect(gateway.lastSelectedRewardId, isNull);
    expect(_lastConfirmationReservationId, 'reservation-reward-catalog-error');
  });

  testWidgets(
      'P7-D A: no preorder in cart -> the catalog reward card never appears',
      (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ];
    await _pumpFlow(
      tester,
      gateway: gateway,
      loyaltyGateway: _FakeLoyaltyGateway(
        rewards: [_catalogReward(rewardId: 'reward-1')],
      ),
    );
    await _driveToReviewStep(tester);

    expect(find.byKey(const Key('catalogRewardCard')), findsNothing);
  });

  testWidgets(
      'P7-D B: only rewards eligible for the preorder cart are shown; '
      'selecting one sends exactly its rewardId and removes the Boncuk card',
      (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ]
      ..submitResultToReturn = const SubmitReservationResult(
        reservationId: 'reservation-reward-1',
        status: 'pendingRestaurantApproval',
        requestedAvailabilityAtSubmission: 'available',
        preorderOrderId: 'order-reward-1',
        duplicate: false,
      );
    final container = await _pumpFlow(
      tester,
      gateway: gateway,
      loyaltyGateway: _FakeLoyaltyGateway(
        snapshot: _boncukSnapshot(),
        rewards: [
          _catalogReward(rewardId: 'eligible', eligibleProductIds: ['p1']),
          _catalogReward(
              rewardId: 'ineligible', eligibleProductIds: ['other-product']),
        ],
      ),
    );
    await _driveToReviewStepWithPreorder(tester, container);
    expect(find.byKey(const Key('boncukRedemptionCard')), findsOneWidget);
    expect(find.byKey(const Key('catalogRewardTile-eligible')), findsOneWidget);
    expect(find.byKey(const Key('catalogRewardTile-ineligible')), findsNothing);

    await tester.tap(find.byKey(const Key('catalogRewardTile-eligible')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('boncukRedemptionCard')), findsNothing);

    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Yılmaz');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.pumpAndSettle();

    expect(gateway.lastSelectedRewardId, 'eligible');
    expect(gateway.lastRequestedBoncukAmount, 0);
  });

  testWidgets(
      'P7-D C: selecting a reward while Boncuk cash redemption is already on '
      'turns Boncuk off (mutual exclusivity, the reward selection wins)',
      (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ];
    final container = await _pumpFlow(
      tester,
      gateway: gateway,
      loyaltyGateway: _FakeLoyaltyGateway(
        snapshot: _boncukSnapshot(),
        rewards: [_catalogReward(rewardId: 'reward-1')],
      ),
    );
    await _driveToReviewStepWithPreorder(tester, container);

    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();
    expect(find.text('1 Boncuk'), findsOneWidget);
    expect(find.byKey(const Key('catalogRewardCard')), findsNothing);
  });

  testWidgets(
      'P7-D D: tapping an already-selected reward deselects it, and the '
      'Boncuk cash-redemption card reappears', (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ]
      ..submitResultToReturn = const SubmitReservationResult(
        reservationId: 'reservation-reward-2',
        status: 'pendingRestaurantApproval',
        requestedAvailabilityAtSubmission: 'available',
        preorderOrderId: 'order-reward-2',
        duplicate: false,
      );
    final container = await _pumpFlow(
      tester,
      gateway: gateway,
      loyaltyGateway: _FakeLoyaltyGateway(
        snapshot: _boncukSnapshot(),
        rewards: [_catalogReward(rewardId: 'reward-1')],
      ),
    );
    await _driveToReviewStepWithPreorder(tester, container);

    await tester.tap(find.byKey(const Key('catalogRewardTile-reward-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('boncukRedemptionCard')), findsNothing);

    await tester.tap(find.byKey(const Key('catalogRewardTile-reward-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('boncukRedemptionCard')), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Yılmaz');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.pumpAndSettle();
    expect(gateway.lastSelectedRewardId, isNull);
  });

  testWidgets(
      'P7-D E: a catalogReward-specific server rejection resets the '
      'selection, ordinary submission (no reward) remains possible',
      (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ]
      ..submitResultToReturn = const SubmitReservationResult(
        reservationId: 'reservation-reward-3',
        status: 'pendingRestaurantApproval',
        requestedAvailabilityAtSubmission: 'available',
        preorderOrderId: 'order-reward-3',
        duplicate: false,
      );
    final container = await _pumpFlow(
      tester,
      gateway: gateway,
      loyaltyGateway: _FakeLoyaltyGateway(
        rewards: [_catalogReward(rewardId: 'reward-1')],
      ),
    );
    await _driveToReviewStepWithPreorder(tester, container);
    await tester.tap(find.byKey(const Key('catalogRewardTile-reward-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Yılmaz');
    await tester.pumpAndSettle();

    gateway.submitError = const ReservationException(
      'invalid-argument',
      'Reward no longer valid.',
      boncukErrorReason: 'catalogReward/insufficient-balance',
    );
    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.pumpAndSettle();

    expect(gateway.submitCallCount, 1);
    expect(_lastConfirmationReservationId, isNull);
    // The reward's card is back — selection was reset, not merely hidden.
    expect(find.byKey(const Key('catalogRewardTile-reward-1')), findsOneWidget);

    gateway.submitError = null;
    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.pumpAndSettle();
    expect(gateway.submitCallCount, 2);
    expect(gateway.lastSelectedRewardId, isNull);
    expect(_lastConfirmationReservationId, 'reservation-reward-3');
  });

  // =========================================================================
  // Server-Authoritative Campaign Engine P8-C.2 (2026-08-25) — the
  // reservation preorder campaign checkout wiring: [CampaignSelectionCard],
  // mutual exclusivity with cash Boncuk redemption AND a catalog reward.
  // The server-confirmed success summary itself is proven in
  // `reservation_confirmation_screen_test.dart`; the historical snapshot
  // display is proven in `reservation_detail_screen_test.dart` — this
  // file's job, per its own established P6-B/P7-D-section convention
  // above, is the WIRING only.
  // =========================================================================

  testWidgets(
      'P8-C.2 A: no preorder in cart -> the campaign card never appears',
      (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ];
    await _pumpFlow(
      tester,
      gateway: gateway,
      campaignGateway:
          _FakeCampaignGateway(campaigns: [_testCampaign(campaignId: 'c1')]),
    );
    await _driveToReviewStep(tester);

    expect(find.byKey(const Key('campaignSelectionCard')), findsNothing);
  });

  testWidgets(
      'P8-C.2 B: only campaigns eligible for reservationPreorder are shown '
      '(client-side best-effort filter); selecting one sends exactly its '
      'campaignId and removes the Boncuk/catalog-reward cards',
      (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ]
      ..submitResultToReturn = const SubmitReservationResult(
        reservationId: 'reservation-campaign-1',
        status: 'pendingRestaurantApproval',
        requestedAvailabilityAtSubmission: 'available',
        preorderOrderId: 'order-campaign-1',
        duplicate: false,
      );
    final container = await _pumpFlow(
      tester,
      gateway: gateway,
      loyaltyGateway: _FakeLoyaltyGateway(snapshot: _boncukSnapshot()),
      campaignGateway: _FakeCampaignGateway(campaigns: [
        _testCampaign(campaignId: 'eligible'),
        _testCampaign(
          campaignId: 'delivery-only',
          eligibleChannels: const ['delivery'],
        ),
      ]),
    );
    await _driveToReviewStepWithPreorder(tester, container);

    expect(find.byKey(const Key('boncukRedemptionCard')), findsOneWidget);
    expect(find.byKey(const Key('campaignTile-eligible')), findsOneWidget);
    expect(find.byKey(const Key('campaignTile-delivery-only')), findsNothing);

    await tester.tap(find.byKey(const Key('campaignTile-eligible')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('boncukRedemptionCard')), findsNothing);
    expect(find.byKey(const Key('catalogRewardCard')), findsNothing);

    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Yılmaz');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.pumpAndSettle();

    expect(gateway.lastSelectedCampaignId, 'eligible');
    expect(gateway.lastRequestedBoncukAmount, 0);
    expect(gateway.lastSelectedRewardId, isNull);
  });

  testWidgets(
      'P8-C.2 C: turning cash Boncuk redemption on while a campaign is '
      'selected turns the campaign selection off (mutual exclusivity, '
      'Boncuk wins)', (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ];
    final container = await _pumpFlow(
      tester,
      gateway: gateway,
      loyaltyGateway: _FakeLoyaltyGateway(snapshot: _boncukSnapshot()),
      campaignGateway: _FakeCampaignGateway(
        campaigns: [_testCampaign(campaignId: 'c1')],
      ),
    );
    await _driveToReviewStepWithPreorder(tester, container);

    await tester.tap(find.byKey(const Key('campaignTile-c1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('boncukRedemptionCard')), findsNothing);

    // Deselect the campaign to bring the Boncuk card back, then toggle it —
    // mirrors the reservation-scoped equivalent of
    // `DeliveryCheckoutScreen`'s own C test, adapted since this card is
    // hidden (not merely disabled) while a campaign is active.
    await tester.tap(find.byKey(const Key('campaignTile-c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();
    expect(find.text('1 Boncuk'), findsOneWidget);
    expect(find.byKey(const Key('campaignSelectionCard')), findsNothing,
        reason: 'otherBenefitActive hides the campaign card entirely while '
            'Boncuk cash redemption is on');
  });

  testWidgets(
      'P8-C.2 D: tapping an already-selected campaign deselects it, and the '
      'Boncuk/catalog-reward cards reappear', (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ]
      ..submitResultToReturn = const SubmitReservationResult(
        reservationId: 'reservation-campaign-2',
        status: 'pendingRestaurantApproval',
        requestedAvailabilityAtSubmission: 'available',
        preorderOrderId: 'order-campaign-2',
        duplicate: false,
      );
    final container = await _pumpFlow(
      tester,
      gateway: gateway,
      loyaltyGateway: _FakeLoyaltyGateway(snapshot: _boncukSnapshot()),
      campaignGateway: _FakeCampaignGateway(
        campaigns: [_testCampaign(campaignId: 'c1')],
      ),
    );
    await _driveToReviewStepWithPreorder(tester, container);

    await tester.tap(find.byKey(const Key('campaignTile-c1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('boncukRedemptionCard')), findsNothing);

    await tester.tap(find.byKey(const Key('campaignTile-c1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('boncukRedemptionCard')), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Yılmaz');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.pumpAndSettle();
    expect(gateway.lastSelectedCampaignId, isNull);
  });

  testWidgets(
      'P8-C.2 E: a campaign-specific server rejection resets the '
      'selection, ordinary submission (no campaign) remains possible',
      (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ]
      ..submitResultToReturn = const SubmitReservationResult(
        reservationId: 'reservation-campaign-3',
        status: 'pendingRestaurantApproval',
        requestedAvailabilityAtSubmission: 'available',
        preorderOrderId: 'order-campaign-3',
        duplicate: false,
      );
    final container = await _pumpFlow(
      tester,
      gateway: gateway,
      campaignGateway: _FakeCampaignGateway(
        campaigns: [_testCampaign(campaignId: 'c1')],
      ),
    );
    await _driveToReviewStepWithPreorder(tester, container);
    await tester.tap(find.byKey(const Key('campaignTile-c1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Yılmaz');
    await tester.pumpAndSettle();

    gateway.submitError = const ReservationException(
      'failed-precondition',
      'The selected campaign has reached its usage limit.',
      boncukErrorReason: 'campaign/usage-limit-reached',
    );
    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.pumpAndSettle();

    expect(gateway.submitCallCount, 1);
    expect(_lastConfirmationReservationId, isNull);
    expect(find.text('Bu kampanyanın kullanım hakkı doldu.'), findsOneWidget);
    // The campaign's tile is back — selection was reset, not merely hidden.
    expect(find.byKey(const Key('campaignTile-c1')), findsOneWidget);

    gateway.submitError = null;
    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.pumpAndSettle();
    expect(gateway.submitCallCount, 2);
    expect(gateway.lastSelectedCampaignId, isNull);
    expect(_lastConfirmationReservationId, 'reservation-campaign-3');
  });

  testWidgets(
      'P8-C.2 F: a campaign load failure never blocks ordinary reservation '
      'submission — the campaign card is simply absent', (tester) async {
    final gateway = _FakeReservationGateway()
      ..availabilitySlotsToReturn = [
        ReservationAvailabilitySlot(time: _fakeSlotTime, available: true),
      ]
      ..submitResultToReturn = const SubmitReservationResult(
        reservationId: 'reservation-campaign-error',
        status: 'pendingRestaurantApproval',
        requestedAvailabilityAtSubmission: 'available',
        preorderOrderId: 'order-campaign-error',
        duplicate: false,
      );
    final container = await _pumpFlow(
      tester,
      gateway: gateway,
      campaignGateway: _FakeCampaignGateway(
        error: const CampaignGatewayException(
            'internal', 'Kampanyalar yüklenemedi.'),
      ),
    );
    await _driveToReviewStepWithPreorder(tester, container);

    expect(find.byKey(const Key('campaignSelectionCardError')),
        findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Yılmaz');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rezervasyon Talebini Gönder'));
    await tester.pumpAndSettle();

    expect(gateway.lastSelectedCampaignId, isNull);
    expect(_lastConfirmationReservationId, 'reservation-campaign-error');
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
    int requestedBoncukAmount = 0,
    String? selectedRewardId,
    String? selectedCampaignId,
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
