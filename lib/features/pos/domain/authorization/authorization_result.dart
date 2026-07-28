/// The outcome of a [PosAuthorizationPolicy] check.
class AuthorizationResult {
  const AuthorizationResult({
    required this.granted,
    this.requiresManagerApproval = false,
    this.reason,
  });

  final bool granted;

  /// Whether, even if [granted], a manager's [ApprovalResult] is also
  /// required before the action may actually proceed — a policy can
  /// permit a staff member to *request* something while still requiring
  /// a second, separate sign-off.
  final bool requiresManagerApproval;

  final String? reason;
}
