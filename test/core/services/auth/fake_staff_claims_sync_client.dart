import 'dart:async';

import 'package:abakus_one_v2/core/services/auth/staff_claims_sync_client.dart';

/// A call-counting [StaffClaimsSyncClient] fake — no real
/// `cloud_functions`/`firebase_auth` SDK involved. Returns
/// [claimsToReturn] (default: [StaffAuthorizationClaims.empty], i.e. a
/// signed-in user with zero active memberships) on every call; set it to
/// `null` to simulate "no Firebase user actually signed in."
class FakeStaffClaimsSyncClient implements StaffClaimsSyncClient {
  FakeStaffClaimsSyncClient({
    StaffAuthorizationClaims? claimsToReturn,
    this.neverResolves = false,
  }) : claimsToReturn = claimsToReturn ?? StaffAuthorizationClaims.empty;

  int callCount = 0;
  StaffAuthorizationClaims? claimsToReturn;

  /// Simulates a callable/token-refresh call whose underlying JS-interop
  /// promise never settles (the real-world condition this class exists to
  /// reproduce deterministically — see `staff_auth_repository.dart`'s own
  /// `staffAuthNetworkTimeout`). `syncAndRefresh` returns a `Future` that
  /// never completes; the repository's own `.timeout(...)` is what's
  /// actually under test, not this fake.
  final bool neverResolves;

  @override
  Future<StaffAuthorizationClaims?> syncAndRefresh() async {
    callCount++;
    if (neverResolves) return Completer<StaffAuthorizationClaims?>().future;
    return claimsToReturn;
  }
}
