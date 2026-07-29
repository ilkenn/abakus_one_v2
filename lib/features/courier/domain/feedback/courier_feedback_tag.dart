/// Predefined courier feedback tags — **the only tags feedback may ever
/// use**, per the explicit "reuse predefined feedback tags" rule (also
/// reused by `DeliveryAssignment.rejectionReasonCode`-style predefined
/// reason requirements elsewhere in this feature).
enum CourierFeedbackTag {
  trafficDelay,
  addressUnclear,
  customerFriendly,
  customerDifficult,
  restaurantSlow,
  restaurantFast,
  packagingGood,
  packagingIssue,
  vehicleIssue,
  weatherIssue,
  other,
}
