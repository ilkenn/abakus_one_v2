import 'actor_session.dart';
import 'pos_authorized_action.dart';
import 'staff_role.dart';

/// The role → permission mapping [RealPosAuthorizationPolicy] consults —
/// Sprint 5E's chosen resolution to the required "flat vs. split vs.
/// wrapped" design decision (`docs/decisions.md` ADR-022): `PosAuthorizedAction`
/// stays a single flat enum (splitting or renaming its values across
/// 100+ existing call sites and 5 prior ADRs would be exactly the "large
/// destructive migration" this sprint was told to avoid unless necessary),
/// and this file is the new layer wrapping it in role-scoped groups
/// instead. Phase 6 (`docs/decisions.md` ADR-023) extended the enum again
/// rather than splitting it, for the same reason — now approaching the
/// ~150-value threshold ADR-022 itself named as the trigger for a future
/// bounded-context split.
///
/// **This categorization is a first-pass, naming-pattern-plus-judgment
/// partition, not a business-signed-off security policy** — it should be
/// reviewed by an actual product/security owner before this authorization
/// model is treated as final. It is recorded here, openly, rather than
/// left unstated.
///
/// Tiering rule: [StaffRole.staff] ⊂ [StaffRole.manager] ⊂
/// [StaffRole.admin] — each higher tier is the lower tier's set plus its
/// own additions, computed once in [permissionsFor], never duplicated by
/// hand. [StaffRole.courier] is lateral (a courier's own delivery-lifecycle
/// actions only — never a superset/subset of the other three).
///
/// If this file grows hard to review (many more actions, or actions from
/// 3+ more bounded contexts), that is the trigger to revisit `PosAuthorizedAction`
/// itself for a bounded-context split — not before.
abstract final class RolePermissionMap {
  RolePermissionMap._();

  /// The most sensitive/least-reversible actions — irreversible financial
  /// corrections, emergency overrides, broadcast-to-everyone messaging.
  static const Set<PosAuthorizedAction> _adminOnly = {
    PosAuthorizedAction.correctPayment,
    PosAuthorizedAction.voidPayment,
    PosAuthorizedAction.recloseOrder,
    PosAuthorizedAction.emergencyChannelClosure,
    PosAuthorizedAction.transferOrMergeAfterPayment,
    PosAuthorizedAction.operationalCorrection,
    PosAuthorizedAction.recordCashAdjustment,
    PosAuthorizedAction.recordCourierSettlementAdjustment,
    PosAuthorizedAction.reviewFailureResponsibility,
    PosAuthorizedAction.manageCourierCompensationProfile,
    PosAuthorizedAction.createCourierEarningsAdjustment,
    PosAuthorizedAction.markCourierEarningsPaid,
    PosAuthorizedAction.approveCancelledDeliveryEarnings,
    PosAuthorizedAction.grantLocationEmergencyOverride,
    PosAuthorizedAction.resetCourierLocationHistory,
    PosAuthorizedAction.transferCourierShift,
    PosAuthorizedAction.setTemporaryPackageBlocking,
    PosAuthorizedAction.sendBroadcastMessage,
    PosAuthorizedAction.sendEmergencyMessage,
    PosAuthorizedAction.manageCustomerNotificationCampaigns,
    // Phase 6 Admin Platform (`docs/decisions.md` ADR-023) — the most
    // sensitive/irreversible admin actions: account lifecycle, granting
    // the admin role itself, forced session revocation, org/restaurant
    // structural changes, a whole-branch emergency stop, and system-wide
    // maintenance mode.
    PosAuthorizedAction.manageStaffAccounts,
    PosAuthorizedAction.manageStaffAdminRole,
    PosAuthorizedAction.revokeStaffSession,
    PosAuthorizedAction.manageOrganization,
    PosAuthorizedAction.manageRestaurant,
    PosAuthorizedAction.branchEmergencyStop,
    PosAuthorizedAction.manageLocalizationConfig,
    PosAuthorizedAction.manageMaintenanceMode,
  };

  /// Supervisory/approval/oversight actions — reviewing, overriding,
  /// scheduling, configuring — as opposed to day-to-day execution.
  static const Set<PosAuthorizedAction> _managerTier = {
    PosAuthorizedAction.viewClosedAccount,
    PosAuthorizedAction.reopenOrder,
    PosAuthorizedAction.reopenTableCheck,
    PosAuthorizedAction.cancelAfterPreparation,
    PosAuthorizedAction.packageCompletionOverride,
    PosAuthorizedAction.reprintOrDuplicateReceipt,
    PosAuthorizedAction.reviewCashReconciliation,
    PosAuthorizedAction.reviewCourierSettlement,
    PosAuthorizedAction.activateCourier,
    PosAuthorizedAction.deactivateCourier,
    PosAuthorizedAction.reviewCourierShift,
    PosAuthorizedAction.manuallyAssignDelivery,
    PosAuthorizedAction.reassignDelivery,
    PosAuthorizedAction.cancelDeliveryAssignment,
    PosAuthorizedAction.overrideGeofence,
    PosAuthorizedAction.accessCustomerContactAction,
    PosAuthorizedAction.scheduleCourierShift,
    PosAuthorizedAction.calculateCourierEarnings,
    PosAuthorizedAction.viewCourierLiveTracking,
    PosAuthorizedAction.reorderCourierDeliverySequence,
    PosAuthorizedAction.groupSameDestinationDeliveries,
    PosAuthorizedAction.manageVisitRewardRules,
    PosAuthorizedAction.manageSurveys,
    PosAuthorizedAction.manageCustomerFeedback,
    // Phase 6 Admin Platform (`docs/decisions.md` ADR-023) — supervisory
    // day-to-day admin: assigning non-admin roles, branch access grants,
    // staff audit inspection, branch-level configuration, customer
    // account restriction, photo moderation, device registry, and
    // read-only audit-center/feature-flag visibility.
    PosAuthorizedAction.manageStaffRoles,
    PosAuthorizedAction.manageStaffBranchAccess,
    PosAuthorizedAction.viewStaffAudit,
    PosAuthorizedAction.manageBranch,
    PosAuthorizedAction.manageCustomerAccountStatus,
    PosAuthorizedAction.moderateCustomerPhoto,
    PosAuthorizedAction.manageDeviceRegistry,
    PosAuthorizedAction.viewAuditCenter,
    PosAuthorizedAction.viewFeatureFlags,
  };

  /// Front-line, day-to-day execution actions.
  static const Set<PosAuthorizedAction> _staffTier = {
    PosAuthorizedAction.acknowledgeKitchenItem,
    PosAuthorizedAction.startKitchenPreparation,
    PosAuthorizedAction.markKitchenItemReady,
    PosAuthorizedAction.cancelKitchenLine,
    PosAuthorizedAction.recallKitchenLine,
    PosAuthorizedAction.changeKitchenStation,
    PosAuthorizedAction.completeOrderPreparation,
    PosAuthorizedAction.createDelivery,
    PosAuthorizedAction.offerDeliveryAssignment,
    // Phase 6 Admin Platform (`docs/decisions.md` ADR-023) — base,
    // limited-scope customer-admin visibility. "Staff: limited
    // operational access" per the brief — further data-level narrowing
    // (e.g. hiding sensitive fields) happens presentation-side, not by a
    // second action.
    PosAuthorizedAction.viewCustomerAdmin,
  };

  /// A courier's own delivery-lifecycle actions — never automatically
  /// available to any other tier, and this tier never automatically gains
  /// any other tier's actions either (lateral, not hierarchical).
  static const Set<PosAuthorizedAction> _courierTier = {
    PosAuthorizedAction.startCourierShift,
    PosAuthorizedAction.endCourierShift,
    PosAuthorizedAction.changeCourierAvailability,
    PosAuthorizedAction.respondToDeliveryAssignment,
    PosAuthorizedAction.confirmRestaurantArrival,
    PosAuthorizedAction.confirmPackagePickup,
    PosAuthorizedAction.startDelivery,
    PosAuthorizedAction.confirmCustomerArrival,
    PosAuthorizedAction.completeDelivery,
    PosAuthorizedAction.recordFailedDelivery,
    PosAuthorizedAction.startCourierLocationTracking,
    PosAuthorizedAction.stopCourierLocationTracking,
    PosAuthorizedAction.publishOwnLocationOnly,
    PosAuthorizedAction.sendCourierMessage,
  };

  /// The full set of actions [role] may perform — [StaffRole.manager]
  /// includes everything [StaffRole.staff] can do, and [StaffRole.admin]
  /// includes everything [StaffRole.manager] can do, each computed here
  /// rather than repeated by hand in the tier constants above.
  static Set<PosAuthorizedAction> permissionsFor(StaffRole role) {
    switch (role) {
      case StaffRole.courier:
        return _courierTier;
      case StaffRole.staff:
        return _staffTier;
      case StaffRole.manager:
        return {..._staffTier, ..._managerTier};
      case StaffRole.admin:
        return {..._staffTier, ..._managerTier, ..._adminOnly};
    }
  }

  /// Whether any role in [roles] permits [action] — the "multi-role user
  /// receives the union of valid permissions" rule. An action not present
  /// in any tier at all is denied by every role, including admin — there
  /// is no implicit uncategorized-action fallback.
  static bool allows(Set<StaffRole> roles, PosAuthorizedAction action) {
    for (final role in roles) {
      if (permissionsFor(role).contains(action)) return true;
    }
    return false;
  }

  /// Whether [session]'s *currently active* role alone (not the full
  /// union — see [ActorSession.activeRole]'s own doc comment) permits
  /// [action]. Scoped, context-aware check for UI that should reflect
  /// "what am I doing right now" (e.g. hub sections) rather than
  /// everything the actor is ever capable of.
  static bool allowsForActiveRole(
    ActorSession session,
    PosAuthorizedAction action,
  ) {
    return permissionsFor(session.activeRole).contains(action);
  }
}
