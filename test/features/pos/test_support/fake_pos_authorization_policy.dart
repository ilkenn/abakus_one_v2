import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorization_policy.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorized_action.dart';

/// Test-only [PosAuthorizationPolicy] — every result is supplied by the
/// test itself, never computed or defaulted to "granted". Deliberately
/// lives under `test/` rather than `lib/`, so no build-reachable class
/// could ever be mistaken for (or accidentally wired as) a production
/// "grant everything" default (`docs/decisions.md` ADR-012).
class FakePosAuthorizationPolicy implements PosAuthorizationPolicy {
  FakePosAuthorizationPolicy(this._result);

  final AuthorizationResult _result;

  int callCount = 0;
  PosAuthorizedAction? lastAction;
  String? lastActorStaffId;

  @override
  Future<AuthorizationResult> authorize({
    required PosAuthorizedAction action,
    required String actorStaffId,
    Map<String, String> context = const {},
  }) async {
    callCount += 1;
    lastAction = action;
    lastActorStaffId = actorStaffId;
    return _result;
  }
}
