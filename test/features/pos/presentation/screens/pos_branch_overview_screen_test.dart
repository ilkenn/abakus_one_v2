import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/data/device_key_store.dart';
import 'package:abakus_one_v2/features/admin/data/device_session_cache.dart';
import 'package:abakus_one_v2/features/admin/data/trusted_device_repository.dart';
import 'package:abakus_one_v2/features/admin/data/trusted_device_session_gateway.dart';
import 'package:abakus_one_v2/features/admin/domain/trusted_device/trusted_device.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/trusted_device_session_providers.dart';
import 'package:abakus_one_v2/features/pos/data/pos_action_gateway.dart';
import 'package:abakus_one_v2/features/pos/data/pos_operational_view_gateway.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/pos_workspace_providers.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/pos_branch_overview_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/trusted_device_status_screen.dart';

class _FakePosOperationalViewGateway implements PosOperationalViewGateway {
  List<PosBranchTableSummary> tables = const [];
  int callCount = 0;

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
    throw UnimplementedError();
  }
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
    expect(find.text('Boş'), findsOneWidget);
    expect(find.text('Dolu'), findsOneWidget);
    expect(find.textContaining('2 bekleyen'), findsOneWidget);
  });
}
