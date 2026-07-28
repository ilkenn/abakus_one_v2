/// The outcome of a manager-approval request for one action/payment split
/// that requires it (`PaymentMethod.requiresApproval`,
/// `PosAuthorizedAction`) — foundation only this sprint: nothing produces
/// a real [ApprovalResult] yet (no manager-auth UI exists), but every use
/// case that needs to check "was this approved" depends on this shape, not
/// an ad hoc boolean.
class ApprovalResult {
  const ApprovalResult({
    required this.granted,
    this.approvedByStaffId,
    this.reason,
  });

  final bool granted;

  /// Who granted (or denied) this — always externally supplied, never
  /// generated or guessed.
  final String? approvedByStaffId;

  /// Free-text reason, e.g. for a denial.
  final String? reason;
}
