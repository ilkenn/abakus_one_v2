/// A request that a manager approve one action — foundation only, no real
/// manager-approval UI exists this sprint. [requestedByStaffId] is always
/// externally supplied. [context] carries whatever the requesting use case
/// needs a future approval UI to display (e.g. `{'splitId': 'split-1'}`,
/// `{'action': 'reopenOrder', 'closureId': 'c1'}`) — deliberately untyped
/// since the set of approvable actions grows over time
/// (`PosAuthorizedAction`, a payment split requiring approval, ...).
class ApprovalRequest {
  const ApprovalRequest({
    required this.requestedByStaffId,
    required this.reason,
    this.context = const {},
  });

  final String requestedByStaffId;
  final String reason;
  final Map<String, String> context;
}
