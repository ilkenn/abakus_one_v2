import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/application/use_cases/trusted_device_session_controller.dart';

import 'package:abakus_one_v2/features/admin/data/device_key_store.dart';
import 'package:abakus_one_v2/features/admin/data/device_session_cache.dart';
import 'package:abakus_one_v2/features/admin/data/trusted_device_repository.dart';
import 'package:abakus_one_v2/features/admin/data/trusted_device_session_gateway.dart';
import 'package:abakus_one_v2/features/admin/domain/trusted_device/trusted_device.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/trusted_device_session_providers.dart';
import 'package:abakus_one_v2/features/orders/data/canonical_order_repository.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/orders_provider.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_projection_repository.dart';
import 'package:abakus_one_v2/features/pos/data/pos_action_gateway.dart';
import 'package:abakus_one_v2/features/pos/data/pos_operational_view_gateway.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kds_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/pos_workspace_providers.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/pos_branch_overview_screen.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/pos_table_workspace_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/trusted_device_status_screen.dart';

import '../../../admin/test_support/fake_secure_storage_platform.dart';

/// 2026-11-10 — a server that no longer knows [rejectedSessionId] (the
/// emulator data reset case) and serves tables for any other session.
class _SessionRejectingGateway extends _FakePosOperationalViewGateway {
  _SessionRejectingGateway(this.rejectedSessionId);
  final String rejectedSessionId;
  final sessionIdsSeen = <String>[];

  @override
  Future<PosBranchOverviewPage> getBranchOverview({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String deviceSessionId,
    String? cursor,
    String? ifNoneMatchVersion,
  }) async {
    sessionIdsSeen.add(deviceSessionId);
    if (deviceSessionId == rejectedSessionId) {
      // The Windows REST bridge's spelling of PERMISSION_DENIED.
      throw const PosOperationalViewException(
        'permission_denied',
        'No such device session.',
      );
    }
    return super.getBranchOverview(
      organizationId: organizationId,
      branchId: branchId,
      deviceId: deviceId,
      deviceSessionId: deviceSessionId,
      cursor: cursor,
      ifNoneMatchVersion: ifNoneMatchVersion,
    );
  }
}

class _IssuingSessionGateway extends _NoopSessionGateway {
  int issueCount = 0;

  @override
  Future<RequestDeviceChallengeResult> requestChallenge({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String purpose,
  }) async =>
      RequestDeviceChallengeResult(
        challengeId: 'c1',
        nonce: 'nonce-1',
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      );

  @override
  Future<IssueDeviceSessionResult> issueSession({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String challengeId,
    required String signature,
  }) async {
    issueCount += 1;
    return IssueDeviceSessionResult(
      sessionId: 'session-new',
      expiresAt: DateTime.now().add(const Duration(hours: 12)),
      deviceId: deviceId,
    );
  }
}

class _FakePosOperationalViewGateway implements PosOperationalViewGateway {
  List<PosBranchTableSummary> tables = const [];
  int callCount = 0;

  /// 2026-11-06 — "Ödeme Al" quick action. `null` (the default) keeps
  /// [getTableView] throwing, matching every pre-existing test in this
  /// file that never exercises it; the new PAX/payment tests below set
  /// this explicitly.
  PosTableOperationalView? tableView;
  int getTableViewCallCount = 0;

  @override
  Future<PosBranchOverviewPage> getBranchOverview({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String deviceSessionId,
    String? cursor,
    String? ifNoneMatchVersion,
  }) async {
    callCount += 1;
    return PosBranchOverviewPage(
      tables: tables,
      nextCursor: null,
      version: 'v1',
      unchanged: false,
    );
  }

  @override
  Future<PosTableOperationalView> getTableView({
    required String organizationId,
    required String branchId,
    required String tableId,
    required String deviceId,
    required String deviceSessionId,
  }) async {
    getTableViewCallCount += 1;
    final view = tableView;
    if (view == null) throw UnimplementedError();
    return view;
  }

  @override
  Future<List<PosTopSellingProduct>> getTopSellingProducts({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String deviceSessionId,
  }) async =>
      throw UnimplementedError();
}

class _FakePosActionGateway implements PosActionGateway {
  String? lastResolvedRequestId;
  int resolveCallCount = 0;

  @override
  Future<void> resolveServiceRequest({
    required PosDeviceContext ctx,
    required String requestId,
  }) async {
    resolveCallCount += 1;
    lastResolvedRequestId = requestId;
  }

  @override
  Future<void> respondToOrderLines({
    required String orderId,
    required List<({int lineIndex, bool accept})> decisions,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> proposeLineReplacement({
    required PosDeviceContext ctx,
    required String orderId,
    required int lineIndex,
    required String proposedProductId,
    required int proposedQuantity,
    required String reasonCode,
    required String reasonMessage,
  }) async =>
      throw UnimplementedError();

  @override
  Future<String> submitStaffEntryOrder({
    required PosDeviceContext ctx,
    required String tableId,
    required Map<String, dynamic> subAccountSelection,
    required List<Map<String, dynamic>> items,
  }) async =>
      throw UnimplementedError();

  @override
  Future<String> openCheck({
    required PosDeviceContext ctx,
    required String tableSessionId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> finalizeCheckReadyForPayment({
    required PosDeviceContext ctx,
    required String checkId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> reopenCheck({
    required PosDeviceContext ctx,
    required String checkId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<String> splitByProduct({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
    required String sourceOrderId,
    required int sourceLineIndex,
  }) async =>
      throw UnimplementedError();

  @override
  Future<String> splitByQuantity({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
    required String sourceOrderId,
    required int sourceLineIndex,
    required int quantity,
  }) async =>
      throw UnimplementedError();

  @override
  Future<String> splitByCustomer({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<String>> splitEqualByHeadcount({
    required PosDeviceContext ctx,
    required String checkId,
    required List<String> subAccountIds,
  }) async =>
      throw UnimplementedError();

  @override
  Future<String> splitFreeAmount({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
    required int amountMinorUnits,
    required String sourceOrderId,
    required int sourceLineIndex,
  }) async =>
      throw UnimplementedError();

  final transfers = <(String, String)>[];
  final merges = <(String, String)>[];
  PosActionException? moveError;

  @override
  Future<void> transferTable({
    required PosDeviceContext ctx,
    required String sourceTableId,
    required String targetTableId,
  }) async {
    final error = moveError;
    if (error != null) throw error;
    transfers.add((sourceTableId, targetTableId));
  }

  @override
  Future<void> mergeTables({
    required PosDeviceContext ctx,
    required String sourceTableId,
    required String targetTableId,
  }) async {
    merges.add((sourceTableId, targetTableId));
  }

  @override
  Future<AcceptedLineCancellationResult> requestAcceptedLineCancellation({
    required PosDeviceContext ctx,
    required String orderId,
    required int lineIndex,
    required String reasonCode,
    required String reasonMessage,
  }) async =>
      throw UnimplementedError();

  @override
  Future<String> requestCheckFinancialAdjustment({
    required PosDeviceContext ctx,
    required String checkId,
    required String scope,
    String? allocationId,
    String? subAccountId,
    required String adjustmentType,
    int? percentageBasisPoints,
    int? fixedAmountMinorUnits,
    required String reasonCode,
    required String reasonMessage,
  }) async =>
      throw UnimplementedError();
}

/// A trivially-fake [DeviceKeyStore] that reports platform support and does
/// nothing else meaningful — this test only needs
/// [posDeviceContextProvider] to resolve to a non-null value, which happens
/// entirely through provider overrides below (never through an actual
/// registration flow).
class _NoopKeyStore implements DeviceKeyStore {
  @override
  bool get isPlatformSupported => true;
  @override
  Future<String> loadOrCreatePublicKeyPem(String namespace) async => '';
  @override
  Future<String> signChallenge(String namespace, String nonce) async => '';
  @override
  Future<void> deleteKey(String namespace) async {}
  @override
  Future<bool> hasKey(String namespace) async => false;
}

class _NoopTrustedDeviceRepository implements TrustedDeviceRepository {
  @override
  Stream<List<TrustedDevice>> watchDevicesForBranch({
    required String organizationId,
    required String branchId,
  }) =>
      const Stream.empty();
}

class _NoopSessionGateway implements TrustedDeviceSessionGateway {
  @override
  Future<RequestDeviceRegistrationResult> requestRegistration({
    required String organizationId,
    required String branchId,
    required String platform,
    required String publicKeyPem,
    required List<String> capabilities,
  }) async =>
      throw UnimplementedError();

  @override
  Future<RequestDeviceChallengeResult> requestChallenge({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String purpose,
  }) async =>
      throw UnimplementedError();

  @override
  Future<IssueDeviceSessionResult> issueSession({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String challengeId,
    required String signature,
  }) async =>
      throw UnimplementedError();
}

void main() {
  testWidgets(
      'with no trusted-device session, renders the TrustedDeviceStatusScreen '
      'gate — never table data', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceKeyStoreProvider.overrideWithValue(_NoopKeyStore()),
          deviceSessionCacheProvider.overrideWithValue(DeviceSessionCache()),
          trustedDeviceSessionGatewayProvider
              .overrideWithValue(_NoopSessionGateway()),
          trustedDeviceRepositoryProvider
              .overrideWithValue(_NoopTrustedDeviceRepository()),
          selectedPosBranchIdProvider.overrideWith((ref) => null),
        ],
        child: const MaterialApp(home: PosBranchOverviewScreen()),
      ),
    );
    await tester.pump();

    // No branch selected yet -> posDeviceContextProvider resolves null ->
    // the trusted-device gate renders, which itself shows the
    // branch-selection-required fallback (no crash, never table data).
    expect(find.byType(TrustedDeviceStatusScreen), findsOneWidget);
    expect(find.textContaining('şube seçilmelidir'), findsOneWidget);
  });

  testWidgets('a real device session with tables renders the table grid',
      (tester) async {
    final gateway = _FakePosOperationalViewGateway()
      ..tables = [
        const PosBranchTableSummary(
          tableId: 'table-1',
          displayName: 'Masa 1',
          status: 'available',
          activeTableSessionId: null,
          pendingQrLineCount: 0,
        ),
        const PosBranchTableSummary(
          tableId: 'table-2',
          displayName: 'Masa 2',
          status: 'occupied',
          activeTableSessionId: 'tsess-1',
          pendingQrLineCount: 2,
          // 2026-11-11 — "Dolu" (red) now requires a live order portion.
          activePortionCount: 2,
        ),
        const PosBranchTableSummary(
          tableId: 'table-3',
          displayName: 'Masa 3',
          status: 'billRequested',
          activeTableSessionId: 'tsess-2',
          pendingQrLineCount: 0,
        ),
      ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          posOperationalViewGatewayProvider.overrideWithValue(gateway),
          posDeviceContextProvider.overrideWithValue(
            const PosDeviceContext(
              organizationId: 'org-1',
              branchId: 'branch-1',
              deviceId: 'device-1',
              deviceSessionId: 'session-1',
            ),
          ),
        ],
        child: const MaterialApp(home: PosBranchOverviewScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Masa 1'), findsOneWidget);
    expect(find.text('Masa 2'), findsOneWidget);
    expect(find.text('Masa 3'), findsOneWidget);
    expect(find.text('Boş'), findsOneWidget);
    expect(find.text('Dolu'), findsOneWidget);
    expect(find.text('Hesap İstendi'), findsOneWidget);
    expect(find.textContaining('2 bekleyen'), findsOneWidget);
  });

  testWidgets(
      'Adım 5 (2026-11-07): kitchenReadyOrderCount > 0 gosterir "Mutfakta '
      'Hazır" rozetini, 0 iken hic gostermez', (tester) async {
    final gateway = _FakePosOperationalViewGateway()
      ..tables = [
        const PosBranchTableSummary(
          tableId: 'table-1',
          displayName: 'Masa 1',
          status: 'occupied',
          activeTableSessionId: 'tsess-1',
          pendingQrLineCount: 0,
          kitchenReadyOrderCount: 1,
        ),
        const PosBranchTableSummary(
          tableId: 'table-2',
          displayName: 'Masa 2',
          status: 'occupied',
          activeTableSessionId: 'tsess-2',
          pendingQrLineCount: 0,
          kitchenReadyOrderCount: 0,
        ),
      ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          posOperationalViewGatewayProvider.overrideWithValue(gateway),
          posDeviceContextProvider.overrideWithValue(
            const PosDeviceContext(
              organizationId: 'org-1',
              branchId: 'branch-1',
              deviceId: 'device-1',
              deviceSessionId: 'session-1',
            ),
          ),
        ],
        child: const MaterialApp(home: PosBranchOverviewScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Mutfakta Hazır'), findsOneWidget,
        reason: 'Masa 1 kitchenReadyOrderCount > 0, rozet gorunmeli');
  });

  testWidgets(
      'a pending service request badge is shown and one tap resolves it, refreshing the grid',
      (tester) async {
    final gateway = _FakePosOperationalViewGateway()
      ..tables = [
        const PosBranchTableSummary(
          tableId: 'table-1',
          displayName: 'Masa 1',
          status: 'occupied',
          activeTableSessionId: 'tsess-1',
          pendingQrLineCount: 0,
          pendingServiceRequests: [
            PosPendingServiceRequest(requestId: 'req-1', type: 'callWaiter'),
          ],
        ),
      ];
    final actionGateway = _FakePosActionGateway();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          posOperationalViewGatewayProvider.overrideWithValue(gateway),
          posActionGatewayProvider.overrideWithValue(actionGateway),
          posDeviceContextProvider.overrideWithValue(
            const PosDeviceContext(
              organizationId: 'org-1',
              branchId: 'branch-1',
              deviceId: 'device-1',
              deviceSessionId: 'session-1',
            ),
          ),
        ],
        child: const MaterialApp(home: PosBranchOverviewScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.room_service_outlined), findsOneWidget);
    final callCountBeforeTap = gateway.callCount;

    await tester.tap(find.byIcon(Icons.room_service_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(actionGateway.resolveCallCount, 1);
    expect(actionGateway.lastResolvedRequestId, 'req-1');
    expect(gateway.callCount, greaterThan(callCountBeforeTap),
        reason: 'resolving must trigger a grid refresh');
  });

  group('Self-Order QR Faz 5 — POS zili (SystemSound)', () {
    late List<MethodCall> platformCalls;

    setUp(() {
      platformCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        platformCalls.add(call);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets(
        'bekleyen toplam sayi bir sonraki pollda artarsa SystemSound.alert '
        'calinir (yeni bir siparis/cagri geldi)', (tester) async {
      final gateway = _FakePosOperationalViewGateway()
        ..tables = [
          const PosBranchTableSummary(
            tableId: 'table-1',
            displayName: 'Masa 1',
            status: 'occupied',
            activeTableSessionId: 'tsess-1',
            pendingQrLineCount: 0,
          ),
        ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posOperationalViewGatewayProvider.overrideWithValue(gateway),
            posDeviceContextProvider.overrideWithValue(
              const PosDeviceContext(
                organizationId: 'org-1',
                branchId: 'branch-1',
                deviceId: 'device-1',
                deviceSessionId: 'session-1',
              ),
            ),
          ],
          child: const MaterialApp(home: PosBranchOverviewScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The initial load itself must never ding — nothing to compare the
      // first snapshot against.
      expect(
        platformCalls.where((c) => c.method == 'SystemSound.play'),
        isEmpty,
      );

      // A new QR order line arrives at the table before the next poll.
      gateway.tables = [
        const PosBranchTableSummary(
          tableId: 'table-1',
          displayName: 'Masa 1',
          status: 'occupied',
          activeTableSessionId: 'tsess-1',
          pendingQrLineCount: 1,
        ),
      ];
      await tester.pump(const Duration(seconds: 9));

      expect(
        platformCalls.where((c) => c.method == 'SystemSound.play'),
        isNotEmpty,
      );
    });

    testWidgets(
        'bekleyen toplam sayi azalirsa (staff baska cihazdan cozdu) '
        'SystemSound.alert CALINMAZ', (tester) async {
      final gateway = _FakePosOperationalViewGateway()
        ..tables = [
          const PosBranchTableSummary(
            tableId: 'table-1',
            displayName: 'Masa 1',
            status: 'occupied',
            activeTableSessionId: 'tsess-1',
            pendingQrLineCount: 2,
          ),
        ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posOperationalViewGatewayProvider.overrideWithValue(gateway),
            posDeviceContextProvider.overrideWithValue(
              const PosDeviceContext(
                organizationId: 'org-1',
                branchId: 'branch-1',
                deviceId: 'device-1',
                deviceSessionId: 'session-1',
              ),
            ),
          ],
          child: const MaterialApp(home: PosBranchOverviewScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      gateway.tables = [
        const PosBranchTableSummary(
          tableId: 'table-1',
          displayName: 'Masa 1',
          status: 'occupied',
          activeTableSessionId: 'tsess-1',
          pendingQrLineCount: 1,
        ),
      ];
      await tester.pump(const Duration(seconds: 9));

      expect(
        platformCalls.where((c) => c.method == 'SystemSound.play'),
        isEmpty,
      );
    });
  });

  group('Masalar 5-sekme bölge filtresi (2026-11-06)', () {
    Future<void> pump(
      WidgetTester tester,
      _FakePosOperationalViewGateway gateway, {
      List<Override> extraOverrides = const [],
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posOperationalViewGatewayProvider.overrideWithValue(gateway),
            posDeviceContextProvider.overrideWithValue(
              const PosDeviceContext(
                organizationId: 'org-1',
                branchId: 'branch-1',
                deviceId: 'device-1',
                deviceSessionId: 'session-1',
              ),
            ),
            ...extraOverrides,
          ],
          child: const MaterialApp(home: PosBranchOverviewScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets(
        '"Tümü" varsayılan sekmedir ve her bölgeden masayı birlikte gösterir',
        (tester) async {
      final gateway = _FakePosOperationalViewGateway()
        ..tables = [
          const PosBranchTableSummary(
            tableId: 'table-1',
            displayName: 'Masa 1',
            status: 'available',
            activeTableSessionId: null,
            pendingQrLineCount: 0,
            areaName: 'Bahçe',
          ),
          const PosBranchTableSummary(
            tableId: 'table-2',
            displayName: 'Masa 2',
            status: 'available',
            activeTableSessionId: null,
            pendingQrLineCount: 0,
            areaName: 'Salon',
          ),
        ];
      await pump(tester, gateway);

      expect(find.text('Masa 1'), findsOneWidget);
      expect(find.text('Masa 2'), findsOneWidget);
    });

    testWidgets(
        '2026-11-11: "Teras" sekmesi yok — Tümü / Bahçe / Salon / Paket',
        (tester) async {
      final gateway = _FakePosOperationalViewGateway()
        ..tables = [
          const PosBranchTableSummary(
            tableId: 'table-1',
            displayName: 'Masa 1',
            status: 'available',
            activeTableSessionId: null,
            pendingQrLineCount: 0,
            areaName: 'Bahçe',
          ),
        ];
      await pump(tester, gateway);

      final chips = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .map((chip) => (chip.label as Text).data)
          .toList();
      expect(chips, ['Tümü', 'Bahçe', 'Salon', 'Paket / Gel-Al']);
    });

    testWidgets('bir bölge sekmesi sadece o bölgedeki masaları gösterir',
        (tester) async {
      final gateway = _FakePosOperationalViewGateway()
        ..tables = [
          const PosBranchTableSummary(
            tableId: 'table-1',
            displayName: 'Masa 1',
            status: 'available',
            activeTableSessionId: null,
            pendingQrLineCount: 0,
            areaName: 'Bahçe',
          ),
          const PosBranchTableSummary(
            tableId: 'table-2',
            displayName: 'Masa 2',
            status: 'available',
            activeTableSessionId: null,
            pendingQrLineCount: 0,
            areaName: 'Salon',
          ),
        ];
      await pump(tester, gateway);

      await tester.tap(find.text('Salon'));
      await tester.pump();

      expect(find.text('Masa 1'), findsNothing);
      expect(find.text('Masa 2'), findsOneWidget);
    });

    testWidgets(
        'Adım 5 (2026-11-07): "Paket / Gel-Al" sekmesi artik gercek Paket '
        'Siparisleri ekranini acar, masa listesini degil', (tester) async {
      final gateway = _FakePosOperationalViewGateway()
        ..tables = [
          const PosBranchTableSummary(
            tableId: 'table-1',
            displayName: 'Masa 1',
            status: 'available',
            activeTableSessionId: null,
            pendingQrLineCount: 0,
            areaName: 'Bahçe',
          ),
        ];
      await pump(
        tester,
        gateway,
        extraOverrides: [
          canonicalOrderRepositoryProvider
              .overrideWithValue(InMemoryCanonicalOrderRepository()),
        ],
      );

      await tester.tap(find.text('Paket / Gel-Al'));
      await tester.pump();

      expect(find.text('Masa 1'), findsNothing);
      expect(find.text('Paket / Gel-Al Siparişleri'), findsOneWidget);
      expect(find.text('Yeni Paket Sipariş'), findsOneWidget);
    });
  });

  group('"Ödeme Al" hızlı aksiyonu (2026-11-06)', () {
    const occupiedTable = PosBranchTableSummary(
      tableId: 'table-1',
      displayName: 'Masa 1',
      status: 'occupied',
      activeTableSessionId: 'tsess-1',
      pendingQrLineCount: 0,
    );

    testWidgets(
        'acik hesabi olan bir masada butona basmak PosCheckoutScreen\'i '
        'cözümlenen checkId ile açar', (tester) async {
      final gateway = _FakePosOperationalViewGateway()
        ..tables = [occupiedTable]
        ..tableView = const PosTableOperationalView(
          tableId: 'table-1',
          status: 'occupied',
          tableSessionId: 'tsess-1',
          subAccounts: [],
          checks: [
            {'id': 'check-1', 'status': 'open'},
          ],
          orders: [],
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posOperationalViewGatewayProvider.overrideWithValue(gateway),
            posDeviceContextProvider.overrideWithValue(
              const PosDeviceContext(
                organizationId: 'org-1',
                branchId: 'branch-1',
                deviceId: 'device-1',
                deviceSessionId: 'session-1',
              ),
            ),
          ],
          child: const MaterialApp(home: PosBranchOverviewScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byIcon(Icons.payments_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(gateway.getTableViewCallCount, 1);
      expect(find.text('Ödeme'), findsOneWidget,
          reason: 'the compact checkout modal must now be open');
    });

    testWidgets(
        'acik hesabi olmayan bir masada butona basmak bir uyari gosterir, '
        'PosCheckoutScreen asla acilmaz', (tester) async {
      final gateway = _FakePosOperationalViewGateway()
        ..tables = [occupiedTable]
        ..tableView = const PosTableOperationalView(
          tableId: 'table-1',
          status: 'occupied',
          tableSessionId: 'tsess-1',
          subAccounts: [],
          checks: [
            {'id': 'check-1', 'status': 'paid'},
          ],
          orders: [],
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posOperationalViewGatewayProvider.overrideWithValue(gateway),
            posDeviceContextProvider.overrideWithValue(
              const PosDeviceContext(
                organizationId: 'org-1',
                branchId: 'branch-1',
                deviceId: 'device-1',
                deviceSessionId: 'session-1',
              ),
            ),
          ],
          child: const MaterialApp(home: PosBranchOverviewScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byIcon(Icons.payments_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Ödeme'), findsNothing);
      expect(find.text('Bu masada açık bir hesap yok.'), findsOneWidget);
    });
  });

  // 2026-11-10 — "Şube masaları yüklenirken bir sorun oluştu" after an
  // emulator data reset: the cached session (still valid locally) was gone
  // server-side and "Tekrar Dene" resent the same id forever.
  testWidgets(
      'a server-rejected device session is replaced with a fresh one and the '
      'tables load, instead of a permanent error', (tester) async {
    FlutterSecureStoragePlatform.instance = FakeSecureStoragePlatform();
    const namespace = 'test_org-1_branch-1';
    final cache = DeviceSessionCache(storage: const FlutterSecureStorage());
    await cache.writeDeviceId(namespace, 'device-1');
    await cache.writeSession(
      namespace,
      sessionId: 'session-stale',
      expiresAt: DateTime.now().add(const Duration(hours: 6)),
    );

    final sessionGateway = _IssuingSessionGateway();
    final gateway = _SessionRejectingGateway('session-stale')
      ..tables = [
        const PosBranchTableSummary(
          tableId: 'table-1',
          displayName: 'Salon 1',
          status: 'available',
          activeTableSessionId: null,
          pendingQrLineCount: 0,
        ),
      ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          posOperationalViewGatewayProvider.overrideWithValue(gateway),
          currentTrustedDeviceSessionControllerProvider.overrideWithValue(
            (organizationId: 'org-1', branchId: 'branch-1'),
          ),
          trustedDeviceSessionControllerProvider.overrideWith(
            (ref, args) => TrustedDeviceSessionController(
              keyStore: _NoopKeyStore(),
              sessionCache: cache,
              sessionGateway: sessionGateway,
              deviceRepository: _NoopTrustedDeviceRepository(),
              organizationId: args.organizationId,
              branchId: args.branchId,
              environment: 'test',
              devicePlatformWireValue: 'windows',
            ),
          ),
          selectedPosBranchIdProvider.overrideWith((ref) => 'branch-1'),
        ],
        child: const MaterialApp(home: PosBranchOverviewScreen()),
      ),
    );
    // The cached session is read asynchronously, so the screen's very first
    // load finds no device context yet; the next 8 s poll is the first real
    // call — it is rejected, recovered and retried in that same tick.
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(gateway.sessionIdsSeen, ['session-stale', 'session-new']);
    expect(sessionGateway.issueCount, 1);
    expect(find.text('Salon 1'), findsOneWidget);
    expect(
        find.text('Şube masaları yüklenirken bir sorun oluştu.'), findsNothing);
    final cached = await cache.readSession(namespace);
    expect(cached?.sessionId, 'session-new');
  });

  // 2026-11-11 — bird's-eye cards: wire fields drive chairs and colors.
  testWidgets(
      'wire activePortionCount/capacity fill the chairs (capped at 4) and '
      'set the card state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _FakePosOperationalViewGateway()
      ..tables = [
        PosBranchTableSummary.fromWire({
          'tableId': 'salon-1',
          'displayName': 'Salon 1',
          'status': 'occupied',
          'activeTableSessionId': 'tsess-1',
          'pendingQrLineCount': 0,
          'activePortionCount': 3,
          'capacity': 4,
        }),
        PosBranchTableSummary.fromWire({
          'tableId': 'bahce-1',
          'displayName': 'Bahçe 1',
          'status': 'billRequested',
          'activeTableSessionId': 'tsess-2',
          'pendingQrLineCount': 0,
          'activePortionCount': 9,
        }),
        PosBranchTableSummary.fromWire({
          'tableId': 'salon-2',
          'displayName': 'Salon 2',
          'status': 'occupied',
          'activeTableSessionId': 'tsess-3',
          'pendingQrLineCount': 0,
        }),
      ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          posOperationalViewGatewayProvider.overrideWithValue(gateway),
          posDeviceContextProvider.overrideWithValue(
            const PosDeviceContext(
              organizationId: 'org-1',
              branchId: 'branch-1',
              deviceId: 'device-1',
              deviceSessionId: 'session-1',
            ),
          ),
        ],
        child: const MaterialApp(home: PosBranchOverviewScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 3 + min(9, 4) + 0 person figures.
    expect(find.byIcon(Icons.person), findsNWidgets(7));
    expect(find.text('Dolu'), findsOneWidget);
    expect(find.text('Hesap İstendi'), findsOneWidget);
    // Active session but no live order: green "Boş", all chairs empty.
    expect(find.text('Boş'), findsOneWidget);
  });

  // 2026-11-11 — "Taşı" in the table workspace returns here; the target
  // table is picked on the bird's-eye grid.
  group('masa taşıma modu (2026-11-11)', () {
    const salon1 = PosBranchTableSummary(
      tableId: 'table-1',
      displayName: 'Salon 1',
      status: 'occupied',
      activeTableSessionId: 'tsess-1',
      pendingQrLineCount: 0,
      activePortionCount: 2,
      areaName: 'Salon',
    );
    const salon2 = PosBranchTableSummary(
      tableId: 'table-2',
      displayName: 'Salon 2',
      status: 'available',
      activeTableSessionId: null,
      pendingQrLineCount: 0,
      areaName: 'Salon',
    );
    const bahce1 = PosBranchTableSummary(
      tableId: 'table-3',
      displayName: 'Bahçe 1',
      status: 'occupied',
      activeTableSessionId: 'tsess-3',
      pendingQrLineCount: 0,
      activePortionCount: 1,
      areaName: 'Bahçe',
    );
    const salon1View = PosTableOperationalView(
      tableId: 'table-1',
      status: 'occupied',
      tableSessionId: 'tsess-1',
      subAccounts: [
        {'id': 'sub-1', 'displayName': 'Ayşe'},
      ],
      checks: [],
      orders: [
        PosTableOrderSummary(
          orderId: 'order-1',
          subAccountId: 'sub-1',
          mode: 'guestSession',
          linesDispositionSummary: 'resolved',
          lines: [
            PosOrderLineSummary(
              productName: 'Klasik Bowl',
              quantity: 1,
              unitPriceMinorUnits: 10000,
              status: 'accepted',
              subAccountId: 'sub-1',
            ),
          ],
        ),
      ],
    );

    /// Opens Salon 1, taps "Taşı" (nothing selected) and lands back on the
    /// grid in move mode — the real round trip through the workspace.
    Future<_FakePosActionGateway> startMove(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final viewGateway = _FakePosOperationalViewGateway()
        ..tables = [salon1, salon2, bahce1]
        ..tableView = salon1View;
      final actionGateway = _FakePosActionGateway();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posOperationalViewGatewayProvider.overrideWithValue(viewGateway),
            posActionGatewayProvider.overrideWithValue(actionGateway),
            posDeviceContextProvider.overrideWithValue(
              const PosDeviceContext(
                organizationId: 'org-1',
                branchId: 'branch-1',
                deviceId: 'device-1',
                deviceSessionId: 'session-1',
              ),
            ),
            kitchenProjectionRepositoryProvider
                .overrideWithValue(InMemoryKitchenProjectionRepository()),
          ],
          child: const MaterialApp(home: PosBranchOverviewScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Salon 1'));
      await tester.pumpAndSettle();
      expect(find.byType(PosTableWorkspaceScreen), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Taşı'));
      await tester.pumpAndSettle();
      expect(find.byType(PosTableWorkspaceScreen), findsNothing);
      return actionGateway;
    }

    testWidgets(
        'Taşı returns to the grid with a banner naming the table being moved',
        (tester) async {
      await startMove(tester);

      expect(find.byKey(const Key('tableMoveBanner')), findsOneWidget);
      expect(
          find.text('Salon 1 taşınıyor — hedef masayı seçin.'), findsOneWidget);
    });

    testWidgets('a free target receives the whole adisyon (transferTable)',
        (tester) async {
      final actions = await startMove(tester);

      await tester.tap(find.text('Salon 2'));
      await tester.pumpAndSettle();

      expect(actions.transfers, [('table-1', 'table-2')]);
      expect(actions.merges, isEmpty);
      expect(find.byKey(const Key('tableMoveBanner')), findsNothing);
      expect(find.text('Salon 1, Salon 2 masasına taşındı.'), findsOneWidget);
    });

    testWidgets(
        'an occupied target asks "Birleştirilsin mi?" and merges only after '
        'confirmation', (tester) async {
      final actions = await startMove(tester);

      await tester.tap(find.text('Bahçe 1'));
      await tester.pumpAndSettle();
      expect(find.text('Birleştirilsin mi?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Vazgeç').last);
      await tester.pumpAndSettle();
      expect(actions.merges, isEmpty);
      expect(find.byKey(const Key('tableMoveBanner')), findsOneWidget,
          reason: 'declining the merge keeps the move going');

      await tester.tap(find.text('Bahçe 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Birleştir'));
      await tester.pumpAndSettle();

      expect(actions.merges, [('table-1', 'table-3')]);
      expect(actions.transfers, isEmpty);
      expect(find.text('Salon 1, Bahçe 1 ile birleştirildi.'), findsOneWidget);
    });

    testWidgets('the source table itself is never a target', (tester) async {
      final actions = await startMove(tester);

      await tester.tap(find.text('Salon 1'));
      await tester.pump();

      expect(
          find.text('Taşınan masanın kendisi hedef olamaz.'), findsOneWidget);
      expect(actions.transfers, isEmpty);
      expect(find.byType(PosTableWorkspaceScreen), findsNothing);
    });

    testWidgets('Vazgeç ends move mode; tapping a table opens it again',
        (tester) async {
      final actions = await startMove(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Vazgeç'));
      await tester.pump();
      expect(find.byKey(const Key('tableMoveBanner')), findsNothing);

      await tester.tap(find.text('Salon 2'));
      await tester.pumpAndSettle();
      expect(actions.transfers, isEmpty);
      expect(find.byType(PosTableWorkspaceScreen), findsOneWidget);
    });

    testWidgets('a failed move shows a Turkish message and keeps move mode',
        (tester) async {
      final actions = await startMove(tester);
      actions.moveError = const PosActionException(
          'failed-precondition', 'The target table has a live reservation.');

      await tester.tap(find.text('Salon 2'));
      await tester.pumpAndSettle();

      expect(
          find.text('Masa taşınamadı. Lütfen tekrar deneyin.'), findsOneWidget);
      expect(find.byKey(const Key('tableMoveBanner')), findsOneWidget);
    });
  });
}
