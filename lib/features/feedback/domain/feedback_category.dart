/// The kind of feedback a customer is submitting — Sprint 5D's Customer
/// Feedback Center. Closed enum, extended additively as new categories
/// are approved, mirroring `CustomerCategory`'s own convention.
enum FeedbackCategory {
  suggestion,
  complaint,
  thankYou,
  menuSuggestion,
  bugReport,
  deliveryIssue,
  restaurantExperience,
  staffFeedback,
  generalFeedback,
}
