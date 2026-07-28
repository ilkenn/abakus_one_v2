import 'authorization_result.dart';
import 'pos_authorized_action.dart';

/// Gates every closed-account/correction action
/// (`ReopenClosedOrder`/`CorrectPaymentMethod`/`VoidPayment`/
/// `CloseOrderAccount`'s reclose path/closed-account visibility) behind an
/// actual authorization check.
///
/// **No production implementation exists this sprint, and deliberately
/// no `NoOp`-style "grant everything" default either** — unlike
/// `UnavailableExchangeRateProvider` (an honest "not available" stand-in
/// that's safe to wire by default), a NoOp authorization policy that
/// auto-grants would be an unsafe default masquerading as a placeholder.
/// Every use case that depends on this contract is therefore genuinely
/// unreachable from any wired production Riverpod provider this sprint —
/// testable via a fake implementation (`test/features/pos/test_support/
/// fake_pos_authorization_policy.dart`), not reachable from the app
/// (`docs/decisions.md` ADR-012).
abstract interface class PosAuthorizationPolicy {
  Future<AuthorizationResult> authorize({
    required PosAuthorizedAction action,
    required String actorStaffId,
    Map<String, String> context = const {},
  });
}
