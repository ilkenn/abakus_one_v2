import '../segmentation/customer_category.dart';
import 'customer_notification_campaign_status.dart';

/// An administrator-authored, audience-targeted notification campaign —
/// Sprint 5D's CRM Notification Foundation, **architecture only**.
/// Nothing in this feature sends a real push notification: no
/// `firebase_messaging`/APNs dependency exists, and [status] never
/// reaches [CustomerNotificationCampaignStatus.sent] anywhere in this
/// codebase. Fields are deliberately shaped to convert into the existing
/// `features/notifications`' `NotificationPayload` (title/body/data)
/// without redesign once a real push provider is wired — that hand-off is
/// explicitly future work, not built here.
///
/// A mutable registry entity, mirrors `VisitRewardRule`/`Survey`'s own
/// shape.
class CustomerNotificationCampaign {
  const CustomerNotificationCampaign({
    required this.id,
    required this.title,
    required this.body,
    this.targetCategory,
    this.targetCustomerIds = const [],
    this.scheduledFor,
    this.linkedCampaignId,
    this.status = CustomerNotificationCampaignStatus.draft,
    required this.createdByStaffId,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String title;
  final String body;

  /// Segment targeting — `null` means "not targeted by category."
  final CustomerCategory? targetCategory;

  /// Explicit targeting — an empty list means "not targeted by explicit
  /// id." See `ResolveNotificationCampaignAudience` for how the two
  /// targeting modes combine.
  final List<String> targetCustomerIds;

  /// `null` means "not yet scheduled" (still a draft, or send-on-demand
  /// once real sending exists).
  final DateTime? scheduledFor;

  /// References an existing `CampaignModel.id` (`features/campaigns`) —
  /// "campaign linkage." Never a duplicate copy of that campaign's data.
  final String? linkedCampaignId;

  final CustomerNotificationCampaignStatus status;

  final String createdByStaffId;
  final DateTime createdAt;
  final int revision;

  CustomerNotificationCampaign copyWith({
    String? title,
    String? body,
    CustomerCategory? targetCategory,
    bool clearTargetCategory = false,
    List<String>? targetCustomerIds,
    DateTime? scheduledFor,
    bool clearScheduledFor = false,
    String? linkedCampaignId,
    bool clearLinkedCampaignId = false,
    CustomerNotificationCampaignStatus? status,
    required int revision,
  }) {
    return CustomerNotificationCampaign(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      targetCategory:
          clearTargetCategory ? null : (targetCategory ?? this.targetCategory),
      targetCustomerIds: targetCustomerIds ?? this.targetCustomerIds,
      scheduledFor:
          clearScheduledFor ? null : (scheduledFor ?? this.scheduledFor),
      linkedCampaignId: clearLinkedCampaignId
          ? null
          : (linkedCampaignId ?? this.linkedCampaignId),
      status: status ?? this.status,
      createdByStaffId: createdByStaffId,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
