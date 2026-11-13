import 'package:abakus_one_v2/features/admin/data/staff_auth_repository.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/staff_session_controller.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_shell_screen.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/actor_session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// ADR-085 phase B — after the customer app's phone + SMS sign-in, the same
/// account's staff role is discovered in the background.
class _DiscoveryRepository implements StaffAuthRepository {
  _DiscoveryRepository(this._discover);

  final Future<ActorSession?> Function(String uid) _discover;
  final List<String> discoveredUids = [];

  @override
  Future<ActorSession?> discoverSessionForSignedInUser(String uid) {
    discoveredUids.add(uid);
    return _discover(uid);
  }

  @override
  Future<ActorSession?> signIn({
    required String email,
    required String password,
  }) async =>
      null;

  @override
  Future<String> startPhoneSignIn(String phoneNumber) async => 'unused';

  @override
  Future<ActorSession?> completePhoneSignIn({
    required String verificationId,
    required String smsCode,
  }) async =>
      null;

  @override
  Future<ActorSession?> refreshSession(ActorSession current) async => current;

  @override
  Future<void> signOut() async {}
}

ActorSession _session(String uid, StaffRole role) {
  final now = DateTime.now();
  return ActorSession(
    actorId: uid,
    roles: {role},
    activeRole: role,
    issuedAt: now,
    expiresAt: now.add(const Duration(hours: 8)),
  );
}

ProviderContainer _container(_DiscoveryRepository repository) {
  final container = ProviderContainer(overrides: [
    staffAuthRepositoryProvider.overrideWithValue(repository),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('StaffSessionController.discoverForSignedInUser', () {
    test('a staff account gets its session without a second sign-in', () async {
      final repository =
          _DiscoveryRepository((uid) async => _session(uid, StaffRole.courier));
      final container = _container(repository);

      final found = await container
          .read(staffSessionControllerProvider)
          .discoverForSignedInUser('uid-1');

      expect(found, isTrue);
      expect(container.read(actorSessionProvider)?.actorId, 'uid-1');
      expect(
          container.read(actorSessionProvider)?.activeRole, StaffRole.courier);
    });

    test('an ordinary customer gets no staff session', () async {
      final repository = _DiscoveryRepository((uid) async => null);
      final container = _container(repository);

      final found = await container
          .read(staffSessionControllerProvider)
          .discoverForSignedInUser('uid-1');

      expect(found, isFalse);
      expect(container.read(actorSessionProvider), isNull);
    });

    test('a failed lookup leaves the customer app undisturbed', () async {
      final repository = _DiscoveryRepository((uid) async =>
          throw const StaffAuthUnavailableException('zaman aşımı'));
      final container = _container(repository);

      final found = await container
          .read(staffSessionControllerProvider)
          .discoverForSignedInUser('uid-1');

      expect(found, isFalse);
      expect(container.read(actorSessionProvider), isNull);
    });

    test('an existing valid session for the same account is kept, no lookup',
        () async {
      final repository =
          _DiscoveryRepository((uid) async => _session(uid, StaffRole.manager));
      final container = _container(repository);
      final existing = _session('uid-1', StaffRole.cashier);
      container.read(actorSessionProvider.notifier).state = existing;

      final found = await container
          .read(staffSessionControllerProvider)
          .discoverForSignedInUser('uid-1');

      expect(found, isTrue);
      expect(repository.discoveredUids, isEmpty);
      expect(container.read(actorSessionProvider), same(existing));
    });

    test('clearDiscoveredSession ends the staff session', () async {
      final repository =
          _DiscoveryRepository((uid) async => _session(uid, StaffRole.cashier));
      final container = _container(repository);
      final controller = container.read(staffSessionControllerProvider);
      await controller.discoverForSignedInUser('uid-1');

      controller.clearDiscoveredSession();

      expect(container.read(actorSessionProvider), isNull);
    });
  });

  group('AdminShellScreen.roleLandingNavItemId', () {
    test('staff and cashiers open the POS, the packing lead the kitchen', () {
      for (final role in [StaffRole.staff, StaffRole.cashier]) {
        expect(AdminShellScreen.roleLandingNavItemId(role), 'pos',
            reason: role.name);
      }
      expect(AdminShellScreen.roleLandingNavItemId(StaffRole.packingLead),
          'kitchen');
    });

    test('managers and owners open the default overview', () {
      for (final role in [
        StaffRole.manager,
        StaffRole.admin,
        StaffRole.tenantOwner,
      ]) {
        expect(AdminShellScreen.roleLandingNavItemId(role), isNull,
            reason: role.name);
      }
    });
  });
}
