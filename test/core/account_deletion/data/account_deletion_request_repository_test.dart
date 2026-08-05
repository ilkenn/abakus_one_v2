import 'package:abakus_one_v2/core/account_deletion/data/account_deletion_request_repository.dart';
import 'package:abakus_one_v2/core/account_deletion/domain/account_deletion_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryAccountDeletionRequestRepository', () {
    test('save then findById returns the saved request', () async {
      final repository = InMemoryAccountDeletionRequestRepository();
      final request = AccountDeletionRequest(
        id: 'req-1',
        uid: 'uid-1',
        status: AccountDeletionStatus.coolingOff,
        requestedAt: DateTime(2026, 1, 1),
        coolingOffEndsAt: DateTime(2026, 1, 8),
        revision: 1,
      );

      await repository.save(request);

      expect(await repository.findById('req-1'), request);
    });

    test('findById returns null for an unknown id', () async {
      final repository = InMemoryAccountDeletionRequestRepository();
      expect(await repository.findById('missing'), isNull);
    });

    test(
        'findActiveByUid returns a coolingOff/pendingVerification request but not cancelled/completed',
        () async {
      final repository = InMemoryAccountDeletionRequestRepository();
      await repository.save(AccountDeletionRequest(
        id: 'req-cancelled',
        uid: 'uid-1',
        status: AccountDeletionStatus.cancelled,
        requestedAt: DateTime(2026, 1, 1),
        coolingOffEndsAt: DateTime(2026, 1, 8),
        revision: 2,
      ));
      expect(await repository.findActiveByUid('uid-1'), isNull);

      await repository.save(AccountDeletionRequest(
        id: 'req-active',
        uid: 'uid-1',
        status: AccountDeletionStatus.coolingOff,
        requestedAt: DateTime(2026, 1, 2),
        coolingOffEndsAt: DateTime(2026, 1, 9),
        revision: 1,
      ));
      final active = await repository.findActiveByUid('uid-1');
      expect(active?.id, 'req-active');
    });

    test(
        'findLatestByUid returns the most recently requested record regardless of status',
        () async {
      final repository = InMemoryAccountDeletionRequestRepository();
      await repository.save(AccountDeletionRequest(
        id: 'req-older',
        uid: 'uid-1',
        status: AccountDeletionStatus.cancelled,
        requestedAt: DateTime(2026, 1, 1),
        coolingOffEndsAt: DateTime(2026, 1, 8),
        revision: 2,
      ));
      await repository.save(AccountDeletionRequest(
        id: 'req-newer',
        uid: 'uid-1',
        status: AccountDeletionStatus.coolingOff,
        requestedAt: DateTime(2026, 1, 5),
        coolingOffEndsAt: DateTime(2026, 1, 12),
        revision: 1,
      ));

      final latest = await repository.findLatestByUid('uid-1');

      expect(latest?.id, 'req-newer');
    });

    test('findLatestByUid returns null when no request exists for the uid',
        () async {
      final repository = InMemoryAccountDeletionRequestRepository();
      expect(await repository.findLatestByUid('unknown-uid'), isNull);
    });

    test(
        'findDueForProcessing returns only coolingOff requests whose window elapsed',
        () async {
      final repository = InMemoryAccountDeletionRequestRepository();
      final now = DateTime(2026, 1, 10);
      await repository.save(AccountDeletionRequest(
        id: 'req-due',
        uid: 'uid-1',
        status: AccountDeletionStatus.coolingOff,
        requestedAt: DateTime(2026, 1, 1),
        coolingOffEndsAt: DateTime(2026, 1, 8),
        revision: 1,
      ));
      await repository.save(AccountDeletionRequest(
        id: 'req-not-due',
        uid: 'uid-2',
        status: AccountDeletionStatus.coolingOff,
        requestedAt: DateTime(2026, 1, 9),
        coolingOffEndsAt: DateTime(2026, 1, 16),
        revision: 1,
      ));
      await repository.save(AccountDeletionRequest(
        id: 'req-cancelled-past-window',
        uid: 'uid-3',
        status: AccountDeletionStatus.cancelled,
        requestedAt: DateTime(2026, 1, 1),
        coolingOffEndsAt: DateTime(2026, 1, 8),
        revision: 2,
      ));

      final due = await repository.findDueForProcessing(now);

      expect(due.map((r) => r.id), ['req-due']);
    });
  });
}
