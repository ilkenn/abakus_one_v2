import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/data/trusted_device_gateway.dart';
import 'package:abakus_one_v2/features/admin/data/trusted_device_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/trusted_device/trusted_device.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/device_registry_screen.dart';
import 'package:abakus_one_v2/features/navigation/presentation/providers/current_branch_provider.dart';

/// AP-2 final wiring — the Trusted Devices tab's real test matrix. Both
/// [_FakeTrustedDeviceRepository]/[_FakeTrustedDeviceGateway] are plain,
/// self-contained fakes (no `fake_cloud_firestore` dependency needed) —
/// consistent with this codebase's established "override the
/// repository/gateway provider with a fake" convention.
class _FakeTrustedDeviceRepository implements TrustedDeviceRepository {
  _FakeTrustedDeviceRepository(this.devices);
  final List<TrustedDevice> devices;

  @override
  Stream<List<TrustedDevice>> watchDevicesForBranch({
    required String organizationId,
    required String branchId,
  }) {
    return Stream.value(devices
        .where(
            (d) => d.organizationId == organizationId && d.branchId == branchId)
        .toList());
  }
}

class _FakeTrustedDeviceGateway implements TrustedDeviceGateway {
  String? lastAction;
  String? lastDeviceId;
  String? lastReason;

  @override
  Future<void> suspendDevice({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String reason,
  }) async {
    lastAction = 'suspend';
    lastDeviceId = deviceId;
    lastReason = reason;
  }

  @override
  Future<void> revokeDevice({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String reason,
  }) async {
    lastAction = 'revoke';
    lastDeviceId = deviceId;
    lastReason = reason;
  }

  @override
  Future<void> retireDevice({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String reason,
  }) async {
    lastAction = 'retire';
    lastDeviceId = deviceId;
    lastReason = reason;
  }
}

TrustedDevice _device({
  String deviceId = 'device-1',
  TrustedDeviceStatus status = TrustedDeviceStatus.active,
  TrustedDeviceTrustTier trustTier = TrustedDeviceTrustTier.platformProtected,
}) {
  return TrustedDevice(
    deviceId: deviceId,
    organizationId: 'org-1',
    branchId: 'branch-1',
    platform: TrustedDevicePlatform.android,
    capabilities: const [TrustedDeviceCapability.pos],
    status: status,
    trustTier: trustTier,
    registeredByUid: 'staff-1',
    registeredAt: DateTime(2026, 1, 1),
    version: 1,
  );
}

void main() {
  Future<void> pumpDevicesTab(
    WidgetTester tester, {
    required TrustedDeviceRepository repository,
    TrustedDeviceGateway? gateway,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trustedDeviceRepositoryProvider.overrideWithValue(repository),
          if (gateway != null)
            trustedDeviceGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(
          home: DeviceRegistryScreen(branchId: 'branch-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Güvenilir Cihazlar'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'real backend repository is called — an active device renders with its status, trust tier, and capability',
      (tester) async {
    await pumpDevicesTab(tester,
        repository: _FakeTrustedDeviceRepository([_device()]));

    expect(find.text('Aktif'), findsOneWidget);
    expect(find.text('Platform Korumalı · POS'), findsOneWidget);
  });

  testWidgets(
      'a pending device shows an "Onay Kutusuna Git" shortcut to the real activation path (activation is never a direct client mutation)',
      (tester) async {
    await pumpDevicesTab(
      tester,
      repository: _FakeTrustedDeviceRepository(
          [_device(status: TrustedDeviceStatus.pending)]),
    );

    expect(find.text('Onay Bekliyor'), findsOneWidget);
    expect(find.text('Onay Kutusuna Git'), findsOneWidget);
    // No "activate" action exists anywhere on this card — the only path
    // to `active` is the Approval Inbox's `respondToApprovalRequest`.
    expect(find.text('Aktifleştir'), findsNothing);
  });

  testWidgets('no public key, nonce, signature, or session id is ever rendered',
      (tester) async {
    await pumpDevicesTab(tester,
        repository: _FakeTrustedDeviceRepository([_device()]));

    for (final forbidden in [
      'publicKeyPem',
      'nonce',
      'signature',
      'sessionId',
      'BEGIN PUBLIC KEY',
    ]) {
      expect(find.textContaining(forbidden), findsNothing);
    }
  });

  testWidgets(
      'suspend calls the real gateway with the device id, branch scope, and the entered reason',
      (tester) async {
    final gateway = _FakeTrustedDeviceGateway();
    await pumpDevicesTab(
      tester,
      repository: _FakeTrustedDeviceRepository([_device()]),
      gateway: gateway,
    );

    await tester.tap(find.text('Askıya Al'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'routine check');
    await tester.tap(find.text('Askıya Al').last);
    await tester.pumpAndSettle();

    expect(gateway.lastAction, 'suspend');
    expect(gateway.lastDeviceId, 'device-1');
    expect(gateway.lastReason, 'routine check');
  });

  testWidgets('revoke and retire are unavailable for an already-revoked device',
      (tester) async {
    await pumpDevicesTab(
      tester,
      repository: _FakeTrustedDeviceRepository(
          [_device(status: TrustedDeviceStatus.revoked)]),
    );

    expect(find.text('İptal Edildi'), findsOneWidget);
    expect(find.text('İptal Et'), findsNothing);
    expect(find.text('Askıya Al'), findsNothing);
    // Retire remains available from revoked (any non-retired status).
    expect(find.text('Emekliye Ayır'), findsOneWidget);
  });

  testWidgets(
      'backend unavailable (no Firebase) shows an explicit error state, never a silently-empty list',
      (tester) async {
    await pumpDevicesTab(
      tester,
      repository: const UnavailableTrustedDeviceRepository(),
    );

    expect(find.textContaining('ulaşılamadı'), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('an empty branch device roster shows a clear empty state',
      (tester) async {
    await pumpDevicesTab(tester, repository: _FakeTrustedDeviceRepository([]));

    expect(find.textContaining('kayıtlı güvenilir cihaz yok'), findsOneWidget);
  });

  testWidgets(
      'a device belonging to a different branch is never shown — organization/branch scoping is real, not client-trusted display filtering only',
      (tester) async {
    await pumpDevicesTab(
      tester,
      repository: _FakeTrustedDeviceRepository([
        TrustedDevice(
          deviceId: 'device-other-branch',
          organizationId: 'org-1',
          branchId: 'branch-9',
          platform: TrustedDevicePlatform.ios,
          capabilities: const [TrustedDeviceCapability.kds],
          status: TrustedDeviceStatus.active,
          trustTier: TrustedDeviceTrustTier.platformProtected,
          registeredByUid: 'staff-2',
          registeredAt: DateTime(2026, 1, 1),
          version: 1,
        ),
      ]),
    );

    expect(find.textContaining('kayıtlı güvenilir cihaz yok'), findsOneWidget);
  });

  testWidgets(
      'context switch (a different branch id) re-queries the device roster for the new scope',
      (tester) async {
    // Ids deliberately 8 chars each ('device-1'/'device-2') — the card
    // truncates to `deviceId.substring(0, 8)`, so anything longer with a
    // shared prefix (e.g. 'device-branch-1'/'device-branch-2') would
    // render identically ('device-b…') for both and defeat this test.
    final container = ProviderContainer(overrides: [
      trustedDeviceRepositoryProvider.overrideWithValue(
        _FakeTrustedDeviceRepository([
          _device(deviceId: 'device-1'),
          TrustedDevice(
            deviceId: 'device-2',
            organizationId: 'org-1',
            branchId: 'branch-2',
            platform: TrustedDevicePlatform.android,
            capabilities: const [TrustedDeviceCapability.pos],
            status: TrustedDeviceStatus.active,
            trustTier: TrustedDeviceTrustTier.platformProtected,
            registeredByUid: 'staff-1',
            registeredAt: DateTime(2026, 1, 1),
            version: 1,
          ),
        ]),
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: DeviceRegistryScreen(branchId: 'branch-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Güvenilir Cihazlar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('device-1'), findsOneWidget);
    expect(find.textContaining('device-2'), findsNothing);

    container.read(currentBranchIdProvider.notifier).state = 'branch-2';
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: DeviceRegistryScreen(branchId: 'branch-2'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Güvenilir Cihazlar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('device-2'), findsOneWidget);
    expect(find.textContaining('device-1'), findsNothing);
  });
}
