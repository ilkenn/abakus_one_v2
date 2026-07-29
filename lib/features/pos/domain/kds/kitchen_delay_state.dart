/// Branch-configurable delay thresholds — the only persisted/authoritative
/// input to [KitchenDelayState] computation. Order-channel-aware: a
/// `null` per-channel override falls back to the branch default.
class KitchenDelayThresholds {
  const KitchenDelayThresholds({
    required this.warningThreshold,
    required this.criticalThreshold,
    this.channelOverrides = const {},
  });

  final Duration warningThreshold;
  final Duration criticalThreshold;

  /// Keyed by `OrderChannel.name` (a raw string, matching
  /// `KitchenRoutingCriteria.channelName`'s same reasoning) — e.g.
  /// delivery orders may warrant a tighter threshold than dine-in.
  final Map<String, ({Duration warning, Duration critical})> channelOverrides;

  ({Duration warning, Duration critical}) resolveFor(String? channelName) {
    final override = channelName == null ? null : channelOverrides[channelName];
    return override ?? (warning: warningThreshold, critical: criticalThreshold);
  }
}

/// A [KitchenWorkItem]'s current delay standing — **always computed fresh
/// from timestamps + [KitchenDelayThresholds] via an injected `Clock`,
/// never persisted as authoritative data** (a continuously-changing "how
/// long has this been queued" figure would go stale the instant it was
/// stored). Mirrors `CashVariance`/`CourierSettlementVariance`'s
/// computed-value-object shape.
class KitchenDelayState {
  const KitchenDelayState({
    required this.workItemId,
    required this.queuedDuration,
    required this.preparingDuration,
    required this.totalDuration,
    required this.isWarning,
    required this.isCritical,
    required this.isOverdue,
  });

  final String workItemId;
  final Duration queuedDuration;
  final Duration preparingDuration;
  final Duration totalDuration;
  final bool isWarning;
  final bool isCritical;

  /// `true` once [totalDuration] exceeds the critical threshold — a
  /// convenience alias kept distinct from [isCritical] only in name, so
  /// call sites reading "is this order overdue" don't need to know the
  /// warning/critical distinction exists.
  final bool isOverdue;

  /// Computes delay state for one work item — pure, no I/O, deterministic
  /// given [now] (always caller-supplied via an injected `Clock`, never
  /// `DateTime.now()` directly).
  factory KitchenDelayState.compute({
    required String workItemId,
    required DateTime queuedAt,
    DateTime? preparingStartedAt,
    DateTime? readyAt,
    required DateTime now,
    required KitchenDelayThresholds thresholds,
    String? channelName,
  }) {
    final endOfPreparation = readyAt ?? now;
    final queuedDuration =
        (preparingStartedAt ?? endOfPreparation).difference(queuedAt);
    final preparingDuration = preparingStartedAt == null
        ? Duration.zero
        : endOfPreparation.difference(preparingStartedAt);
    final totalDuration = endOfPreparation.difference(queuedAt);

    final resolved = thresholds.resolveFor(channelName);
    final isCritical = totalDuration >= resolved.critical;
    final isWarning = !isCritical && totalDuration >= resolved.warning;

    return KitchenDelayState(
      workItemId: workItemId,
      queuedDuration: queuedDuration,
      preparingDuration: preparingDuration,
      totalDuration: totalDuration,
      isWarning: isWarning,
      isCritical: isCritical,
      isOverdue: isCritical,
    );
  }
}
