/// Every Admin Platform mutation Phase 6 covers — one value per
/// [AdminAuditEntry] this codebase actually writes.
enum AdminAuditEventType {
  staffMemberRegistered,
  staffRoleGranted,
  staffRoleRevoked,
  staffBranchAccessGranted,
  staffBranchAccessRevoked,
  staffMemberSuspended,
  staffMemberReinstated,
  staffMemberArchived,
  staffSessionRevoked,
  organizationCreated,
  restaurantCreated,
  branchCreated,
  branchStatusChanged,
  branchEmergencyStopTriggered,
  customerAccountStatusChanged,
  customerPhotoModerated,
  deviceRegistered,
  deviceStatusChanged,
  localizationConfigChanged,
}
