import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/offline/held_offline_lease.dart';

/// AP-4 Wave E — the device's own local record of its currently-held
/// offline authorization lease, keyed by `leaseId` so a device holding
/// leases from more than one prior session never confuses them. Mirrors
/// `SharedPreferencesOfflinePaymentOutboxRepository`'s exact persistence
/// shape and reasoning (small, bounded state; `shared_preferences` is
/// already a pinned dependency).
abstract interface class OfflineLeaseStore {
  Future<HeldOfflineLease?> currentLease();
  Future<void> saveLease(HeldOfflineLease lease);

  /// Claims and persists the next device-sequence number for [leaseId] —
  /// this is the ONLY place a device-sequence number is ever minted, so
  /// two concurrent captures can never claim the same one. Starts at 1.
  Future<int> claimNextDeviceSequence(String leaseId);

  /// Records this lease's own transaction as now used locally — advances
  /// [HeldOfflineLease.transactionsUsedLocally] by exactly 1.
  Future<void> recordLocalUsage(String leaseId);

  Future<void> clearLease();
}

class SharedPreferencesOfflineLeaseStore implements OfflineLeaseStore {
  SharedPreferencesOfflineLeaseStore(this._prefs);
  final SharedPreferences _prefs;

  static const _leaseKey = 'pos_offline_lease_v1';
  static const _sequenceKeyPrefix = 'pos_offline_lease_sequence_v1_';

  @override
  Future<HeldOfflineLease?> currentLease() async {
    final raw = _prefs.getString(_leaseKey);
    if (raw == null || raw.isEmpty) return null;
    return HeldOfflineLease.fromJson(
        jsonDecode(raw) as Map<String, Object?>);
  }

  @override
  Future<void> saveLease(HeldOfflineLease lease) async {
    await _prefs.setString(_leaseKey, jsonEncode(lease.toJson()));
  }

  @override
  Future<int> claimNextDeviceSequence(String leaseId) async {
    final key = '$_sequenceKeyPrefix$leaseId';
    final last = _prefs.getInt(key) ?? 0;
    final next = last + 1;
    await _prefs.setInt(key, next);
    return next;
  }

  @override
  Future<void> recordLocalUsage(String leaseId) async {
    final current = await currentLease();
    if (current == null || current.leaseId != leaseId) return;
    await saveLease(current.copyWith(
        transactionsUsedLocally: current.transactionsUsedLocally + 1));
  }

  @override
  Future<void> clearLease() async {
    await _prefs.remove(_leaseKey);
  }
}
