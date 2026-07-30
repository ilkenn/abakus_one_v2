/// The kind of one [CourierMessage] — Sprint 5C Part 8's Communication
/// Center. [direct] is a manager↔courier chat message; [broadcast] goes
/// to every courier currently on shift for a branch; [emergency] is the
/// full-screen, acknowledgement-required alert.
enum CourierMessageType { direct, broadcast, emergency }
