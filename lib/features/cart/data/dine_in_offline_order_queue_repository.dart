import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/pending_dine_in_submission.dart';

/// The device-local, durable queue of [PendingDineInSubmission]s captured
/// while offline — Self-Order QR Faz 6. Deliberately much simpler than
/// `OfflinePaymentOutboxRepository` (POS's own offline queue): a guest
/// order has no lease/sequence concept to replay in strict order against
/// — each entry's own `submissionKey` is already globally idempotent
/// server-side, so entries may be flushed in any order, independently.
abstract interface class DineInOfflineOrderQueueRepository {
  Future<void> enqueue(PendingDineInSubmission submission);
  Future<List<PendingDineInSubmission>> findAll();
  Future<void> remove(String submissionKey);
}

/// Real implementation backed by `shared_preferences` (already a pinned
/// dependency) — the whole queue stored as one JSON array under a single
/// key, mirroring `OfflinePaymentOutboxRepository`'s own storage shape.
class SharedPreferencesDineInOfflineOrderQueueRepository
    implements DineInOfflineOrderQueueRepository {
  SharedPreferencesDineInOfflineOrderQueueRepository(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'dineInOfflineOrderQueue';

  Future<List<PendingDineInSubmission>> _readAll() async {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List;
    return decoded
        .map((e) => PendingDineInSubmission.fromJson(
            Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _writeAll(List<PendingDineInSubmission> entries) async {
    await _prefs.setString(
      _key,
      jsonEncode([for (final e in entries) e.toJson()]),
    );
  }

  @override
  Future<void> enqueue(PendingDineInSubmission submission) async {
    final entries = await _readAll();
    // Idempotent by submissionKey — re-enqueuing (e.g. a UI double-tap
    // before the first enqueue was confirmed) never duplicates.
    if (entries.any((e) => e.submissionKey == submission.submissionKey)) {
      return;
    }
    entries.add(submission);
    await _writeAll(entries);
  }

  @override
  Future<List<PendingDineInSubmission>> findAll() => _readAll();

  @override
  Future<void> remove(String submissionKey) async {
    final entries = await _readAll();
    entries.removeWhere((e) => e.submissionKey == submissionKey);
    await _writeAll(entries);
  }
}
