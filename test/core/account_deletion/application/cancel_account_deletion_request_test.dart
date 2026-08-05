import 'package:abakus_one_v2/core/account_deletion/application/cancel_account_deletion_request.dart';
import 'package:abakus_one_v2/core/account_deletion/data/account_deletion_request_repository.dart';
import 'package:abakus_one_v2/core/account_deletion/domain/account_deletion_request.dart';
import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CancelAccountDeletionRequest', () {
    test('cancels a request that is still within its cooling-off window',
        () async {
      final repository = InMemoryAccountDeletionRequestRepository();
      await repository.save(AccountDeletionRequest(
        id: 'req-1',
        uid: 'uid-1',
        status: AccountDeletionStatus.coolingOff,
        requestedAt: DateTime(2026, 8, 1),
        coolingOffEndsAt: DateTime(2026, 8, 8),
        revision: 1,
      ));
      final useCase = CancelAccountDeletionRequest(repository: repository);

      final cancelled = await useCase.call(
        requestId: 'req-1',
        uid: 'uid-1',
        now: DateTime(2026, 8, 3),
      );

      expect(cancelled.status, AccountDeletionStatus.cancelled);
      expect(cancelled.cancelledAt, DateTime(2026, 8, 3));
      expect(cancelled.revision, 2);
      expect(
        (await repository.findById('req-1'))?.status,
        AccountDeletionStatus.cancelled,
      );
    });

    test('throws for a request whose cooling-off window has already elapsed',
        () async {
      final repository = InMemoryAccountDeletionRequestRepository();
      await repository.save(AccountDeletionRequest(
        id: 'req-1',
        uid: 'uid-1',
        status: AccountDeletionStatus.coolingOff,
        requestedAt: DateTime(2026, 8, 1),
        coolingOffEndsAt: DateTime(2026, 8, 8),
        revision: 1,
      ));
      final useCase = CancelAccountDeletionRequest(repository: repository);

      await expectLater(
        useCase.call(
          requestId: 'req-1',
          uid: 'uid-1',
          now: DateTime(2026, 8, 9),
        ),
        throwsA(isA<AccountDeletionRequestNotCancellableViolation>()),
      );
    });

    test('throws for an already-completed request', () async {
      final repository = InMemoryAccountDeletionRequestRepository();
      await repository.save(AccountDeletionRequest(
        id: 'req-1',
        uid: 'uid-1',
        status: AccountDeletionStatus.completed,
        requestedAt: DateTime(2026, 8, 1),
        coolingOffEndsAt: DateTime(2026, 8, 8),
        completedAt: DateTime(2026, 8, 8),
        revision: 2,
      ));
      final useCase = CancelAccountDeletionRequest(repository: repository);

      await expectLater(
        useCase.call(
          requestId: 'req-1',
          uid: 'uid-1',
          now: DateTime(2026, 8, 9),
        ),
        throwsA(isA<AccountDeletionRequestNotCancellableViolation>()),
      );
    });

    test('throws for an unknown requestId', () async {
      final useCase = CancelAccountDeletionRequest(
        repository: InMemoryAccountDeletionRequestRepository(),
      );

      await expectLater(
        useCase.call(
          requestId: 'missing',
          uid: 'uid-1',
          now: DateTime(2026, 8, 9),
        ),
        throwsA(isA<AccountDeletionRequestNotCancellableViolation>()),
      );
    });

    test(
        'throws (never cancels) when the caller does not own the request — '
        'IDOR protection, closed during the Phase 9 adversarial security '
        'review', () async {
      final repository = InMemoryAccountDeletionRequestRepository();
      await repository.save(AccountDeletionRequest(
        id: 'req-1',
        uid: 'victim-uid',
        status: AccountDeletionStatus.coolingOff,
        requestedAt: DateTime(2026, 8, 1),
        coolingOffEndsAt: DateTime(2026, 8, 8),
        revision: 1,
      ));
      final useCase = CancelAccountDeletionRequest(repository: repository);

      await expectLater(
        useCase.call(
          requestId: 'req-1',
          uid: 'attacker-uid',
          now: DateTime(2026, 8, 3),
        ),
        throwsA(isA<AccountDeletionRequestNotCancellableViolation>()),
      );
      expect(
        (await repository.findById('req-1'))?.status,
        AccountDeletionStatus.coolingOff,
      );
    });
  });
}
