import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/data/admin_device_registration_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/device/admin_device_registration.dart';
import 'package:abakus_one_v2/features/admin/domain/device/device_type.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/device_registry_screen.dart';

import '../test_support/admin_test_fixtures.dart';

void main() {
  testWidgets('shows an empty state when there are no devices', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: DeviceRegistryScreen(branchId: 'branch-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bu şube için kayıtlı cihaz yok.'), findsOneWidget);
  });

  testWidgets('lists a registered POS terminal and can deactivate it',
      (tester) async {
    final adminDeviceRepository = InMemoryAdminDeviceRegistrationRepository();
    await adminDeviceRepository.save(AdminDeviceRegistration(
      id: 'pos-1',
      type: DeviceType.posTerminal,
      branchId: 'branch-1',
      label: 'Kasa 1',
      registeredByStaffId: 'manager-1',
      registeredAt: DateTime(2026, 1, 1),
      revision: 1,
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminDeviceRegistrationRepositoryProvider
              .overrideWithValue(adminDeviceRepository),
        ],
        child: const MaterialApp(
          home: DeviceRegistryScreen(
            branchId: 'branch-1',
            authorizationPolicy: AllowAllAdminPolicy(),
            performedByStaffId: 'manager-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kasa 1'), findsOneWidget);
    expect(find.text('POS Terminali · aktif'), findsOneWidget);

    await tester.tap(find.text('Pasifleştir (Kaldır)'));
    await tester.pumpAndSettle();

    expect(find.text('POS Terminali · pasif'), findsOneWidget);
  });
}
