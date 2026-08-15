import 'package:abakus_one_v2/core/services/auth/staff_claims_sync_client.dart';

/// A call-counting [StaffClaimsSyncClient] fake — no real
/// `cloud_functions`/`firebase_auth` SDK involved. Returns
/// [claimsToReturn] (default: [StaffAuthorizationClaims.empty], i.e. a
/// signed-in user with zero active memberships) on every call; set it to
/// `null` to simulate "no Firebase user actually signed in."
class FakeStaffClaimsSyncClient implements StaffClaimsSyncClient {
  FakeStaffClaimsSyncClient({
    StaffAuthorizationClaims? claimsToReturn,
  }) : claimsToReturn = claimsToReturn ?? StaffAuthorizationClaims.empty;

  int callCount = 0;
  StaffAuthorizationClaims? claimsToReturn;

  @override
  Future<StaffAuthorizationClaims?> syncAndRefresh() async {
    callCount++;
    return claimsToReturn;
  }
}
