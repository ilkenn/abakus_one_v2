import '../../orders/domain/models/order_channel.dart';
import '../domain/models/channel_operation_policy.dart';

/// Append-only storage for [ChannelOperationPolicy] revisions, keyed by
/// `(branchId, channel, externalPlatformCode)`.
abstract interface class ChannelOperationPolicyRepository {
  Future<void> save(ChannelOperationPolicy policy);

  /// The latest revision for this branch/channel/platform, or `null` if
  /// none has ever been set.
  Future<ChannelOperationPolicy?> findCurrent(
    String branchId,
    OrderChannel channel, {
    String? externalPlatformCode,
  });

  /// Every revision ever saved for this branch/channel/platform, oldest
  /// first.
  Future<List<ChannelOperationPolicy>> findHistory(
    String branchId,
    OrderChannel channel, {
    String? externalPlatformCode,
  });

  /// The latest revision of every policy currently set for [branchId] —
  /// what a branch-wide settings screen or `EmergencyCloseDeliveryChannels`
  /// iterates over.
  Future<List<ChannelOperationPolicy>> findAllCurrentForBranch(String branchId);
}

/// In-memory [ChannelOperationPolicyRepository] — the only implementation
/// this sprint.
class InMemoryChannelOperationPolicyRepository
    implements ChannelOperationPolicyRepository {
  final Map<String, List<ChannelOperationPolicy>> _historyByKey = {};

  String _key(
      String branchId, OrderChannel channel, String? externalPlatformCode) {
    return '$branchId|${channel.name}|${externalPlatformCode ?? ''}';
  }

  @override
  Future<void> save(ChannelOperationPolicy policy) async {
    final key =
        _key(policy.branchId, policy.channel, policy.externalPlatformCode);
    _historyByKey.putIfAbsent(key, () => []).add(policy);
  }

  @override
  Future<ChannelOperationPolicy?> findCurrent(
    String branchId,
    OrderChannel channel, {
    String? externalPlatformCode,
  }) async {
    final history =
        _historyByKey[_key(branchId, channel, externalPlatformCode)];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }

  @override
  Future<List<ChannelOperationPolicy>> findHistory(
    String branchId,
    OrderChannel channel, {
    String? externalPlatformCode,
  }) async {
    return List.unmodifiable(
      _historyByKey[_key(branchId, channel, externalPlatformCode)] ?? const [],
    );
  }

  @override
  Future<List<ChannelOperationPolicy>> findAllCurrentForBranch(
      String branchId) async {
    final result = <ChannelOperationPolicy>[];
    for (final history in _historyByKey.values) {
      if (history.isNotEmpty && history.last.branchId == branchId) {
        result.add(history.last);
      }
    }
    return List.unmodifiable(result);
  }
}
