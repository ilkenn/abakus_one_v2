import 'package:abakus_one_v2/core/account_deletion/domain/account_deletion_request.dart';
import 'package:flutter_test/flutter_test.dart';

AccountDeletionRequest _buildRequest({
  AccountDeletionStatus status = AccountDeletionStatus.coolingOff,
  DateTime? coolingOffEndsAt,
}) {
  final now = DateTime(2026, 8, 1);
  return AccountDeletionRequest(
    id: 'req-1',
    uid: 'uid-1',
    status: status,
    requestedAt: now,
    coolingOffEndsAt: coolingOffEndsAt ?? now.add(const Duration(days: 7)),
    revision: 1,
  );
}

void main() {
  group('AccountDeletionRequest.canCancelAt', () {
    test('true while coolingOff and the window has not elapsed', () {
      final request = _buildRequest(
        status: AccountDeletionStatus.coolingOff,
        coolingOffEndsAt: DateTime(2026, 8, 8),
      );
      expect(request.canCancelAt(DateTime(2026, 8, 3)), isTrue);
    });

    test('false once the window has elapsed', () {
      final request = _buildRequest(
        status: AccountDeletionStatus.coolingOff,
        coolingOffEndsAt: DateTime(2026, 8, 8),
      );
      expect(request.canCancelAt(DateTime(2026, 8, 9)), isFalse);
    });

    test('false for a cancelled request', () {
      final request = _buildRequest(status: AccountDeletionStatus.cancelled);
      expect(request.canCancelAt(DateTime(2026, 8, 2)), isFalse);
    });

    test('false for a completed request', () {
      final request = _buildRequest(status: AccountDeletionStatus.completed);
      expect(request.canCancelAt(DateTime(2026, 8, 2)), isFalse);
    });
  });

  group('AccountDeletionRequest.isDue', () {
    test('true once coolingOffEndsAt has passed relative to now', () {
      final endsAt = DateTime(2026, 1, 8);
      final request = _buildRequest(
        status: AccountDeletionStatus.coolingOff,
        coolingOffEndsAt: endsAt,
      );
      expect(request.isDue(DateTime(2026, 1, 9)), isTrue);
      expect(request.isDue(DateTime(2026, 1, 8)), isTrue);
    });

    test('false before coolingOffEndsAt', () {
      final endsAt = DateTime(2026, 1, 8);
      final request = _buildRequest(
        status: AccountDeletionStatus.coolingOff,
        coolingOffEndsAt: endsAt,
      );
      expect(request.isDue(DateTime(2026, 1, 7)), isFalse);
    });

    test('false for a non-coolingOff request even if the window elapsed', () {
      final request = _buildRequest(
        status: AccountDeletionStatus.cancelled,
        coolingOffEndsAt: DateTime(2026, 7, 31),
      );
      expect(request.isDue(DateTime(2026, 8, 2)), isFalse);
    });
  });

  test(
      'copyWith preserves id/uid/requestedAt/coolingOffEndsAt and bumps only what is asked',
      () {
    final original = _buildRequest();
    final updated = original.copyWith(
      status: AccountDeletionStatus.cancelled,
      cancelledAt: DateTime(2026, 8, 2),
      revision: original.revision + 1,
    );

    expect(updated.id, original.id);
    expect(updated.uid, original.uid);
    expect(updated.requestedAt, original.requestedAt);
    expect(updated.coolingOffEndsAt, original.coolingOffEndsAt);
    expect(updated.status, AccountDeletionStatus.cancelled);
    expect(updated.cancelledAt, DateTime(2026, 8, 2));
    expect(updated.revision, original.revision + 1);
  });
}
