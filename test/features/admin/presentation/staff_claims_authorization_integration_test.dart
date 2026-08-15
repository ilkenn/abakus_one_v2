import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/core/services/auth/staff_claims_sync_client.dart';
import 'package:abakus_one_v2/features/admin/data/staff_auth_repository.dart';
import 'package:abakus_one_v2/features/admin/data/staff_member_repository.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_reservation_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/staff_session_controller.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_shell_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/reservation_operations_screen.dart';
import 'package:abakus_one_v2/core/services/feature_flags/feature_flags_keys.dart';
import 'package:abakus_one_v2/core/services/feature_flags/feature_flags_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/actor_session_provider.dart';

import '../../../core/services/auth/fake_email_password_auth_client.dart';
import '../../../core/services/auth/fake_staff_claims_sync_client.dart';
import '../../entitlements/test_support/entitlement_test_fixtures.dart';
import '../test_support/admin_test_fixtures.dart';
import 'test_support/fake_admin_reservation_gateway.dart';
import 'test_support/fake_admin_reservation_repository.dart';

/// Faz R.3A.2 — proves the FULL chain end-to-end, not just its two halves
/// independently (repository-level "claims -> ActorSession" tests in
/// `firebase_staff_auth_repository_test.dart`, and widget-level
/// "ActorSession with role X -> nav visibility" tests in
/// `admin_shell_screen_test.dart`): a real sign-in through
/// `StaffSessionController` against a `FirebaseStaffAuthRepository` backed
/// only by fake Firebase Auth + fake refreshed claims (never a
/// `StaffMember` roster) actually reaches `actorSessionProvider` and
/// correctly drives `AdminShellScreen`'s Rezervasyonlar visibility.
void main() {
  Future<ProviderContainer> signInAndPump(
    WidgetTester tester, {
    required String role,
    required Widget child,
  }) async {
    final authClient = FakeEmailPasswordAuthClient();
    final created = await authClient.createAccount(
        email: 'staff@abakus.test', password: 'S3curePass!');
    // A linked StaffMember is seeded here purely as profile metadata (id);
    // its OWN `roles`/`branchAccess` are deliberately the opposite of the
    // claims below to prove the effective role AND branch access still
    // come from claims, never from this record (Faz R.3A.2 for roles,
    // Faz R.3C.2 for branchAccess).
    final staffMemberRepository = InMemoryStaffMemberRepository();
    await staffMemberRepository.save(buildTestStaffMember(
      id: 'profile-1',
      branchAccess: const {'branch-not-in-claims'},
      authUid: created.uid,
    ));
    final repository = FirebaseStaffAuthRepository(
      authClient: authClient,
      staffMemberRepository: staffMemberRepository,
      sessionDuration: () => const Duration(hours: 1),
      claimsSyncClient: FakeStaffClaimsSyncClient(
        claimsToReturn: StaffAuthorizationClaims(
          organizationAccess: const ['org-1'],
          rolesByOrganization: {
            'org-1': [role],
          },
          branchAccessByOrganization: const {
            'org-1': ['branch-1'],
          },
        ),
      ),
      organizationId: () => 'org-1',
    );

    final container = ProviderContainer(overrides: [
      staffAuthRepositoryProvider.overrideWithValue(repository),
      featureFlagsServiceProvider.overrideWithValue(
        FakeFeatureFlagsService(
            enabledKeys: {FeatureFlagsKeys.reservationsEnabled}),
      ),
      adminReservationGatewayProvider
          .overrideWithValue(FakeAdminReservationGateway()),
      adminReservationRepositoryProvider
          .overrideWithValue(FakeAdminReservationRepository()),
    ]);
    addTearDown(container.dispose);

    final signedIn = await container
        .read(staffSessionControllerProvider)
        .signIn(email: 'staff@abakus.test', password: 'S3curePass!');
    expect(signedIn, isTrue,
        reason: 'sign-in against real (fake-backed) claims must succeed');

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: child),
      ),
    );
    await tester.pumpAndSettle();

    return container;
  }

  testWidgets(
      'a real sign-in that resolves manager claims reaches actorSessionProvider '
      'and Rezervasyonlar is visible/openable end-to-end', (tester) async {
    await signInAndPump(tester,
        role: 'manager', child: const AdminShellScreen());

    expect(find.text('Rezervasyonlar'), findsOneWidget);
    await tester.tap(find.text('Rezervasyonlar'));
    await tester.pumpAndSettle();

    expect(find.byType(ReservationOperationsScreen), findsOneWidget);
  });

  testWidgets(
      'a real sign-in that resolves tenantOwner claims reaches actorSessionProvider '
      'and Rezervasyonlar is visible/openable end-to-end', (tester) async {
    await signInAndPump(tester,
        role: 'tenantOwner', child: const AdminShellScreen());

    expect(find.text('Rezervasyonlar'), findsWidgets);
    expect(find.byType(ReservationOperationsScreen), findsOneWidget);
  });

  testWidgets(
      'a real sign-in that resolves only the staff role (no manageReservations) '
      'never shows Rezervasyonlar end-to-end', (tester) async {
    await signInAndPump(tester, role: 'staff', child: const AdminShellScreen());

    expect(find.text('Rezervasyonlar'), findsNothing);
  });

  testWidgets('signOut clears the claims-derived ActorSession state',
      (tester) async {
    final container = await signInAndPump(
      tester,
      role: 'manager',
      child: const AdminShellScreen(),
    );
    expect(container.read(actorSessionProvider), isNotNull);

    await container.read(staffSessionControllerProvider).signOut();

    expect(container.read(actorSessionProvider), isNull);
  });
}
