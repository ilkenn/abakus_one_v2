import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/data/admin_reservation_gateway.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_reservation_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/branch_operating_hours_screen.dart';

import '../test_support/fake_admin_reservation_gateway.dart';

Future<FakeAdminReservationGateway> _pumpScreen(
  WidgetTester tester, {
  FakeAdminReservationGateway? gateway,
}) async {
  final fakeGateway = gateway ?? FakeAdminReservationGateway();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminReservationGatewayProvider.overrideWithValue(fakeGateway)
      ],
      child: const MaterialApp(home: BranchOperatingHoursScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return fakeGateway;
}

void main() {
  testWidgets(
      'shows every weekday, defaulting to "Kapalı" when no hours document exists',
      (tester) async {
    await _pumpScreen(tester);

    expect(find.text('Pazartesi'), findsOneWidget);
    expect(find.text('Salı'), findsOneWidget);
    expect(find.text('Çarşamba'), findsOneWidget);
    expect(find.text('Perşembe'), findsOneWidget);
    expect(find.text('Cuma'), findsOneWidget);
    expect(find.text('Cumartesi'), findsOneWidget);
    expect(find.text('Pazar'), findsOneWidget);
    expect(find.text('Kapalı'), findsNWidgets(7));
  });

  testWidgets('loads and displays an existing weekly schedule', (tester) async {
    final gateway = FakeAdminReservationGateway()
      ..hoursToReturn = const BranchOperatingHoursSnapshot(
        exists: true,
        weeklySchedule: {
          'monday': [
            BranchOperatingHoursInterval(start: '11:00', end: '23:00')
          ],
          'tuesday': [],
          'wednesday': [],
          'thursday': [],
          'friday': [],
          'saturday': [],
          'sunday': [],
        },
        dateOverrides: {},
      );
    await _pumpScreen(tester, gateway: gateway);

    expect(find.text('11:00–23:00'), findsOneWidget);
  });

  testWidgets('displays existing date overrides with a closed toggle',
      (tester) async {
    final gateway = FakeAdminReservationGateway()
      ..hoursToReturn = const BranchOperatingHoursSnapshot(
        exists: true,
        weeklySchedule: {
          'monday': [],
          'tuesday': [],
          'wednesday': [],
          'thursday': [],
          'friday': [],
          'saturday': [],
          'sunday': [],
        },
        dateOverrides: {
          '2026-12-25': BranchOperatingHoursDateOverride(closed: true),
        },
      );
    await _pumpScreen(tester, gateway: gateway);

    expect(find.text('2026-12-25'), findsOneWidget);
    expect(find.text('Kapalı'), findsWidgets);
  });

  testWidgets(
      'saving calls updateBranchOperatingHours with the current schedule',
      (tester) async {
    final gateway = FakeAdminReservationGateway()
      ..hoursToReturn = const BranchOperatingHoursSnapshot(
        exists: true,
        weeklySchedule: {
          'monday': [
            BranchOperatingHoursInterval(start: '11:00', end: '23:00')
          ],
          'tuesday': [],
          'wednesday': [],
          'thursday': [],
          'friday': [],
          'saturday': [],
          'sunday': [],
        },
        dateOverrides: {},
      );
    await _pumpScreen(tester, gateway: gateway);

    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(gateway.updateHoursCalls, hasLength(1));
    expect(gateway.updateHoursCalls.single['organizationId'],
        adminReservationOrganizationId);
    expect(
        gateway.updateHoursCalls.single['branchId'], adminReservationBranchId);
    final savedSchedule = gateway.updateHoursCalls.single['weeklySchedule']
        as Map<String, List<BranchOperatingHoursInterval>>;
    expect(savedSchedule['monday'],
        [const BranchOperatingHoursInterval(start: '11:00', end: '23:00')]);

    expect(find.text('Çalışma saatleri güncellendi.'), findsOneWidget);
  });

  testWidgets(
      'a getBranchOperatingHours failure shows the mapped error with retry',
      (tester) async {
    final gateway = FakeAdminReservationGateway()
      ..getHoursError =
          const AdminReservationException('not-found', 'Branch not found.');
    await _pumpScreen(tester, gateway: gateway);

    expect(find.text('Kayıt bulunamadı. Sayfayı yenileyip tekrar deneyin.'),
        findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);

    gateway.getHoursError = null;
    await tester.tap(find.text('Tekrar Dene'));
    await tester.pumpAndSettle();

    expect(find.text('Pazartesi'), findsOneWidget);
  });

  testWidgets(
      'an updateBranchOperatingHours failure shows the mapped error inline, without discarding the edit',
      (tester) async {
    final gateway = FakeAdminReservationGateway()
      ..hoursToReturn = const BranchOperatingHoursSnapshot(
        exists: true,
        weeklySchedule: {
          'monday': [],
          'tuesday': [],
          'wednesday': [],
          'thursday': [],
          'friday': [],
          'saturday': [],
          'sunday': [],
        },
        dateOverrides: {},
      )
      ..updateHoursError =
          const AdminReservationException('permission-denied', '');
    await _pumpScreen(tester, gateway: gateway);

    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
    // The edit surface (weekday rows) is still present, not blown away by the error.
    expect(find.text('Pazartesi'), findsOneWidget);
  });

  testWidgets(
      'the never-touches-existing-reservations reminder is always visible',
      (tester) async {
    await _pumpScreen(tester);

    expect(
      find.textContaining(
          'Saat değişikliği mevcut rezervasyonları etkilemez veya iptal etmez.'),
      findsOneWidget,
    );
  });
}
