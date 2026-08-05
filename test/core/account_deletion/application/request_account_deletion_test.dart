import 'package:abakus_one_v2/core/account_deletion/application/account_deletion_request_id_generator.dart';
import 'package:abakus_one_v2/core/account_deletion/application/request_account_deletion.dart';
import 'package:abakus_one_v2/core/account_deletion/data/account_deletion_request_repository.dart';
import 'package:abakus_one_v2/core/account_deletion/domain/account_deletion_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RequestAccountDeletion', () {
    test(
        'creates a new request in coolingOff status, ending coolingOffPeriod after now',
        () async {
      final repository = InMemoryAccountDeletionRequestRepository();
      final useCase = RequestAccountDeletion(
        repository: repository,
        idGenerator: SequentialAccountDeletionRequestIdGenerator(),
      );
      final now = DateTime(2026, 8, 5);

      final request = await useCase.call(uid: 'uid-1', now: now);

      expect(request.uid, 'uid-1');
      expect(request.status, AccountDeletionStatus.coolingOff);
      expect(request.requestedAt, now);
      expect(request.coolingOffEndsAt, now.add(const Duration(days: 7)));
      expect(await repository.findById(request.id), request);
    });

    test('defaults to a 7-day cooling-off period', () async {
      final useCase = RequestAccountDeletion(
        repository: InMemoryAccountDeletionRequestRepository(),
        idGenerator: SequentialAccountDeletionRequestIdGenerator(),
      );

      expect(useCase.coolingOffPeriod, const Duration(days: 7));
    });

    test(
        'is idempotent — a second call for the same uid returns the existing active request, not a duplicate',
        () async {
      final repository = InMemoryAccountDeletionRequestRepository();
      final useCase = RequestAccountDeletion(
        repository: repository,
        idGenerator: SequentialAccountDeletionRequestIdGenerator(),
      );

      final first = await useCase.call(uid: 'uid-1', now: DateTime(2026, 8, 5));
      final second =
          await useCase.call(uid: 'uid-1', now: DateTime(2026, 8, 6));

      expect(second.id, first.id);
      expect(second.requestedAt, first.requestedAt);
    });

    test('a cancelled request does not block a new request for the same uid',
        () async {
      final repository = InMemoryAccountDeletionRequestRepository();
      await repository.save(AccountDeletionRequest(
        id: 'old-request',
        uid: 'uid-1',
        status: AccountDeletionStatus.cancelled,
        requestedAt: DateTime(2026, 1, 1),
        coolingOffEndsAt: DateTime(2026, 1, 8),
        revision: 2,
      ));
      final useCase = RequestAccountDeletion(
        repository: repository,
        idGenerator: SequentialAccountDeletionRequestIdGenerator(),
      );

      final request =
          await useCase.call(uid: 'uid-1', now: DateTime(2026, 8, 5));

      expect(request.id, isNot('old-request'));
      expect(request.status, AccountDeletionStatus.coolingOff);
    });
  });
}
