import 'package:abakus_one_v2/bootstrap/firebase_ready_provider.dart';
import 'package:abakus_one_v2/features/admin/data/staff_auth_repository.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('staffAuthRepositoryProvider', () {
    test(
        'resolves to ProductionUnavailableStaffAuthRepository when '
        'Firebase is not ready (default) — never fakes a success', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(staffAuthRepositoryProvider),
        isA<ProductionUnavailableStaffAuthRepository>(),
      );
    });

    test(
        'resolves to FirebaseStaffAuthRepository when Firebase is ready — '
        'in every build mode, not just debug', () {
      final container = ProviderContainer(
        overrides: [firebaseReadyProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      expect(
        container.read(staffAuthRepositoryProvider),
        isA<FirebaseStaffAuthRepository>(),
      );
    });
  });
}
