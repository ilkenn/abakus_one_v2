import 'package:abakus_one_v2/features/courier/data/courier_dispatch_gateway.dart';
import 'package:abakus_one_v2/features/courier/domain/identity/courier.dart';
import 'package:abakus_one_v2/features/courier/domain/identity/courier_status.dart';
import 'package:abakus_one_v2/features/pos/data/courier_pool_gateway.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/courier_dispatch_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/widgets/courier_roster_dialogs.dart';
import 'package:abakus_one_v2/shared/models/courier_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-11-12 (Faz 3b) — courier roster/edit (type, districts, linked
/// sign-in e-mail) and the branch's default pool district.
class _FakeDispatchGateway implements CourierDispatchGateway {
  Map<String, Object?>? last;
  CourierDispatchException? error;

  @override
  Future<String> setCourier({
    required String organizationId,
    required String branchId,
    required String displayName,
    required String phoneNumber,
    CourierType type = CourierType.internal,
    String? courierId,
    List<String> serviceDistrictIds = const [],
    String? authEmail,
    CourierStatus? dispatchStatus,
  }) async {
    final e = error;
    if (e != null) throw e;
    last = {
      'branchId': branchId,
      'courierId': courierId,
      'displayName': displayName,
      'type': type,
      'districts': serviceDistrictIds,
      'authEmail': authEmail,
      'dispatchStatus': dispatchStatus,
    };
    return courierId ?? 'new';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakePoolGateway implements CourierPoolGateway {
  String? savedDistrict;
  CourierPoolException? error;

  @override
  Future<BranchPoolSettings> branchSettings({
    required String organizationId,
    required String branchId,
  }) async =>
      const BranchPoolSettings(
          defaultDeliveryDistrictId: null,
          serviceDistrictIds: ['kadikoy', 'uskudar']);

  @override
  Future<BranchPoolSettings> setDefaultDistrict({
    required String organizationId,
    required String branchId,
    required String districtId,
  }) async {
    final e = error;
    if (e != null) throw e;
    savedDistrict = districtId;
    return BranchPoolSettings(
        defaultDeliveryDistrictId: districtId, serviceDistrictIds: const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final _courier = Courier(
  id: 'c1',
  primaryBranchId: 'branch-home',
  displayName: 'Ali',
  phoneNumber: '+905550000001',
  registeredAt: DateTime(2026, 11, 1),
  type: CourierType.pool,
  serviceDistrictIds: const ['kadikoy'],
  authEmail: 'ali@example.com',
);

Future<void> _pumpDialog(WidgetTester tester, Widget dialog,
    {required List<Override> overrides}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                showDialog<void>(context: context, builder: (_) => dialog),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'roster lists couriers with type, districts and linked sign-in; '
      'editing keeps the courier\'s own branch', (tester) async {
    final gateway = _FakeDispatchGateway();
    await _pumpDialog(
      tester,
      const CourierRosterDialog(organizationId: 'org-1', branchId: 'branch-1'),
      overrides: [
        allCouriersForBranchProvider(
                (organizationId: 'org-1', branchId: 'branch-1'))
            .overrideWith((ref) => Stream.value([_courier])),
        courierDispatchGatewayProvider.overrideWithValue(gateway),
      ],
    );
    expect(find.textContaining('Dış Kurye · kadikoy'), findsOneWidget);
    expect(find.textContaining('Giriş: ali@example.com'), findsOneWidget);

    await tester.tap(find.byKey(const Key('rosterCourier-c1')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('editCourierDistricts')), 'Kadıköy, Üsküdar');
    await tester.tap(find.byKey(const Key('saveCourierButton')));
    await tester.pumpAndSettle();

    expect(gateway.last!['branchId'], 'branch-home');
    expect(gateway.last!['courierId'], 'c1');
    expect(gateway.last!['districts'], ['Kadıköy', 'Üsküdar']);
    expect(gateway.last!['authEmail'], isNull,
        reason: 'unchanged e-mail is not sent (link untouched)');
  });

  testWidgets(
      'linking a new e-mail sends it; the server refusals are explained',
      (tester) async {
    final gateway = _FakeDispatchGateway();
    await _pumpDialog(
      tester,
      CourierEditDialog(organizationId: 'org-1', courier: _courier),
      overrides: [courierDispatchGatewayProvider.overrideWithValue(gateway)],
    );

    gateway.error = const CourierDispatchException('failed-precondition',
        'This account is not an active courier of this organization.');
    await tester.enterText(
        find.byKey(const Key('editCourierEmail')), 'Veli@Example.com');
    await tester.tap(find.byKey(const Key('saveCourierButton')));
    await tester.pumpAndSettle();
    expect(find.textContaining('aktif bir kurye hesabı değil'), findsOneWidget);

    gateway.error =
        const CourierDispatchException('permission-denied', 'denied');
    await tester.tap(find.byKey(const Key('saveCourierButton')));
    await tester.pumpAndSettle();
    expect(find.textContaining('müdür ve üstü'), findsOneWidget);

    gateway.error = null;
    await tester.tap(find.byKey(const Key('saveCourierButton')));
    await tester.pumpAndSettle();
    expect(gateway.last!['authEmail'], 'veli@example.com');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('switching to a restaurant courier sends no districts',
      (tester) async {
    final gateway = _FakeDispatchGateway();
    await _pumpDialog(
      tester,
      CourierEditDialog(organizationId: 'org-1', courier: _courier),
      overrides: [courierDispatchGatewayProvider.overrideWithValue(gateway)],
    );
    await tester.tap(find.byKey(const Key('editCourierInternal')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('editCourierDistricts')), findsNothing);
    await tester.tap(find.byKey(const Key('saveCourierButton')));
    await tester.pumpAndSettle();
    expect(gateway.last!['type'], CourierType.internal);
    expect(gateway.last!['districts'], isEmpty);
  });

  testWidgets(
      'region settings: pick a service district as the default; a staff '
      'refusal is explained', (tester) async {
    final pool = _FakePoolGateway();
    await _pumpDialog(
      tester,
      const BranchPoolSettingsDialog(
          organizationId: 'org-1', branchId: 'branch-1'),
      overrides: [courierPoolGatewayProvider.overrideWithValue(pool)],
    );

    pool.error = const CourierPoolException('permission_denied', 'denied');
    await tester.tap(find.byKey(const Key('serviceDistrict-uskudar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('savePoolSettingsButton')));
    await tester.pumpAndSettle();
    expect(find.textContaining('yalnızca müdür ve üstü'), findsOneWidget);

    pool.error = null;
    await tester.tap(find.byKey(const Key('savePoolSettingsButton')));
    await tester.pumpAndSettle();
    expect(pool.savedDistrict, 'uskudar');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
      'Müsait / Çevrimdışı switch: an offline courier is made available, a '
      'delivering one shows its packages and has no switch', (tester) async {
    final gateway = _FakeDispatchGateway();
    final offline = Courier(
      id: 'c2',
      primaryBranchId: 'branch-1',
      displayName: 'Mehmet',
      phoneNumber: '+905550000002',
      registeredAt: DateTime(2026, 11, 1),
      dispatchStatus: CourierStatus.offline,
    );
    final delivering = Courier(
      id: 'c3',
      primaryBranchId: 'branch-1',
      displayName: 'Ayşe',
      phoneNumber: '+905550000003',
      registeredAt: DateTime(2026, 11, 1),
      dispatchStatus: CourierStatus.delivering,
      activeOrderIds: const ['o1', 'o2'],
    );
    await _pumpDialog(
      tester,
      const CourierRosterDialog(organizationId: 'org-1', branchId: 'branch-1'),
      overrides: [
        allCouriersForBranchProvider(
                (organizationId: 'org-1', branchId: 'branch-1'))
            .overrideWith((ref) => Stream.value([offline, delivering])),
        courierDispatchGatewayProvider.overrideWithValue(gateway),
      ],
    );

    expect(find.textContaining('Durum: Çevrimdışı'), findsOneWidget);
    expect(find.textContaining('Durum: Dağıtımda (2 paket)'), findsOneWidget);
    expect(find.byKey(const Key('courierAvailable-c3')), findsNothing);

    await tester.tap(find.byKey(const Key('courierAvailable-c2')));
    await tester.pumpAndSettle();
    expect(gateway.last!['courierId'], 'c2');
    expect(gateway.last!['dispatchStatus'], CourierStatus.available);
    expect(gateway.last!['branchId'], 'branch-1');
  });
}
