/// A closed set of predefined quick messages — Sprint 5C Part 8's "ready
/// messages," matching this codebase's existing predefined-tag convention
/// (`CourierFeedbackTag`, delivery-rejection reason codes) rather than
/// free text for the common cases. [text] is Turkish, matching this
/// app's user-facing-copy convention. A manager/courier may still send
/// genuine free-text via [CourierMessageType.direct] — this is a
/// convenience source for [SendCourierMessage.body], not the only way to
/// send a message.
enum CourierReadyMessageTemplate {
  onTheWay('Yoldayım, birkaç dakikaya varıyorum.'),
  trafficDelay('Trafik yoğun, gecikebilirim.'),
  arrivedAtRestaurant('Restorana vardım.'),
  packagePickedUp('Paketi aldım, yola çıkıyorum.'),
  arrivedAtCustomer('Müşteriye vardım.'),
  cannotReachCustomer('Müşteriye ulaşamıyorum.'),
  delivered('Teslimatı tamamladım.'),
  needAssistance('Yardıma ihtiyacım var.');

  const CourierReadyMessageTemplate(this.text);

  final String text;
}
