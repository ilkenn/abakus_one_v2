/// One "Bugünün Boncuk Görevleri" daily task.
///
/// Progress is read-only display data seeded by [LoyaltyNotifier] today —
/// nothing yet hooks a real order/QR-order/referral event up to advance a
/// task's [progressCurrent] automatically. That cross-feature wiring
/// (checkout → loyalty, referral → loyalty, ...) is future work; this model
/// only defines the shape a task has once that wiring exists.
class LoyaltyTaskModel {
  final String id;
  final String title;
  final int rewardPoints;
  final int progressCurrent;
  final int progressTarget;

  const LoyaltyTaskModel({
    required this.id,
    required this.title,
    required this.rewardPoints,
    required this.progressCurrent,
    required this.progressTarget,
  });

  bool get isCompleted => progressCurrent >= progressTarget;

  double get progressRatio {
    if (progressTarget <= 0) return 0.0;
    return (progressCurrent / progressTarget).clamp(0.0, 1.0);
  }

  LoyaltyTaskModel copyWith({
    String? id,
    String? title,
    int? rewardPoints,
    int? progressCurrent,
    int? progressTarget,
  }) {
    return LoyaltyTaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      rewardPoints: rewardPoints ?? this.rewardPoints,
      progressCurrent: progressCurrent ?? this.progressCurrent,
      progressTarget: progressTarget ?? this.progressTarget,
    );
  }
}
