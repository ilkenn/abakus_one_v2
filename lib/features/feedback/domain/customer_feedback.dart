import 'feedback_category.dart';

/// One immutable, append-only customer feedback submission — Sprint 5D's
/// Customer Feedback Center. Carries no `status`/`priority` field of its
/// own: those live on a separate append-only `CustomerFeedbackStatusEvent`
/// trail (mirrors `CourierMessageStatusEvent`'s "immutable core + separate
/// mutable-over-time log" pattern), so a full history of every triage
/// decision is always available, never overwritten.
///
/// [customerId] is nullable — feedback may be submitted by a signed-in
/// customer or anonymously. [attachmentRefs] are opaque references (e.g.
/// an uploaded-file id), never raw blobs — mirrors the courier feature's
/// `locationRef` opacity precedent.
class CustomerFeedback {
  const CustomerFeedback({
    required this.id,
    this.customerId,
    required this.branchId,
    required this.category,
    required this.subject,
    required this.body,
    this.attachmentRefs = const [],
    required this.submittedAt,
  });

  final String id;
  final String? customerId;
  final String branchId;
  final FeedbackCategory category;
  final String subject;
  final String body;
  final List<String> attachmentRefs;
  final DateTime submittedAt;
}
