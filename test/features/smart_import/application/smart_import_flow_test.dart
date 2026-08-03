import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/menu/application/identity/menu_category_id_generator.dart';
import 'package:abakus_one_v2/features/menu/application/identity/menu_product_id_generator.dart';
import 'package:abakus_one_v2/features/menu/data/menu_category_repository.dart';
import 'package:abakus_one_v2/features/menu/data/menu_product_repository.dart';
import 'package:abakus_one_v2/features/smart_import/application/identity/import_draft_id_generator.dart';
import 'package:abakus_one_v2/features/smart_import/application/identity/import_job_id_generator.dart';
import 'package:abakus_one_v2/features/smart_import/application/use_cases/approve_import_draft.dart';
import 'package:abakus_one_v2/features/smart_import/application/use_cases/commit_import_draft.dart';
import 'package:abakus_one_v2/features/smart_import/application/use_cases/create_import_draft.dart';
import 'package:abakus_one_v2/features/smart_import/application/use_cases/create_import_job.dart';
import 'package:abakus_one_v2/features/smart_import/application/use_cases/normalize_and_analyze_parsed_menu.dart';
import 'package:abakus_one_v2/features/smart_import/application/use_cases/parse_import_source.dart';
import 'package:abakus_one_v2/features/smart_import/application/use_cases/rollback_import_commit.dart';
import 'package:abakus_one_v2/features/smart_import/data/import_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/smart_import/data/import_draft_repository.dart';
import 'package:abakus_one_v2/features/smart_import/data/import_job_repository.dart';
import 'package:abakus_one_v2/features/smart_import/domain/import_approval.dart';
import 'package:abakus_one_v2/features/smart_import/domain/import_review_decision.dart';
import 'package:abakus_one_v2/features/smart_import/domain/import_source.dart';
import 'package:abakus_one_v2/features/smart_import/domain/import_source_type.dart';
import 'package:abakus_one_v2/features/smart_import/domain/import_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/smart_import_test_fixtures.dart';

const _csv = 'category,name,description,price,currency\n'
    'Bowl,Tavuklu Bowl,Izgara tavuk ile,189.90,TRY\n'
    'Bowl,Somonlu Bowl,Taze somon ile,219.90,TRY\n';

void main() {
  group('The full Smart Import pipeline', () {
    late ImportJobRepository jobRepository;
    late ImportDraftRepository draftRepository;
    late ImportAuditEntryRepository auditRepository;
    late MenuCategoryRepository categoryRepository;
    late MenuProductRepository productRepository;
    late CreateImportJob createImportJob;
    late ParseImportSource parseImportSource;
    late CreateImportDraft createImportDraft;
    late ApproveImportDraft approveImportDraft;
    late CommitImportDraft commitImportDraft;
    late RollbackImportCommit rollbackImportCommit;

    setUp(() {
      jobRepository = InMemoryImportJobRepository();
      draftRepository = InMemoryImportDraftRepository();
      auditRepository = InMemoryImportAuditEntryRepository();
      categoryRepository = InMemoryMenuCategoryRepository();
      productRepository = InMemoryMenuProductRepository();

      createImportJob = CreateImportJob(
        authorizationPolicy: const AllowAllImportPolicy(),
        idGenerator: SequentialImportJobIdGenerator(),
        repository: jobRepository,
        auditRepository: auditRepository,
      );
      parseImportSource = ParseImportSource(
        jobRepository: jobRepository,
        auditRepository: auditRepository,
      );
      createImportDraft = CreateImportDraft(
        jobRepository: jobRepository,
        draftRepository: draftRepository,
        idGenerator: SequentialImportDraftIdGenerator(),
        auditRepository: auditRepository,
      );
      approveImportDraft = ApproveImportDraft(
        authorizationPolicy: const AllowAllImportPolicy(),
        jobRepository: jobRepository,
        auditRepository: auditRepository,
      );
      commitImportDraft = CommitImportDraft(
        jobRepository: jobRepository,
        draftRepository: draftRepository,
        categoryRepository: categoryRepository,
        productRepository: productRepository,
        categoryIdGenerator: SequentialMenuCategoryIdGenerator(),
        productIdGenerator: SequentialMenuProductIdGenerator(),
        auditRepository: auditRepository,
      );
      rollbackImportCommit = RollbackImportCommit(
        authorizationPolicy: const AllowAllImportPolicy(),
        jobRepository: jobRepository,
        categoryRepository: categoryRepository,
        productRepository: productRepository,
        auditRepository: auditRepository,
      );
    });

    test(
        'goes from a CSV source to real, approved MenuCategory/MenuProduct '
        'records, then can be rolled back', () async {
      final job = await createImportJob(
        organizationId: 'org-1',
        restaurantId: 'restaurant-1',
        branchId: 'branch-1',
        source: const ImportSource(type: ImportSourceType.csv, rawText: _csv),
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final rawMenu = await parseImportSource(
        importJobId: job.id,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1, 0, 1),
      );
      expect(rawMenu.products, hasLength(2));
      expect(
          (await jobRepository.findById(job.id))!.status, ImportStatus.parsed);

      final analyzedMenu = const NormalizeAndAnalyzeParsedMenu()(rawMenu);

      final draft = await createImportDraft(
        importJobId: job.id,
        parsedMenu: analyzedMenu,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1, 0, 2),
      );
      expect((await jobRepository.findById(job.id))!.status,
          ImportStatus.draftReady);

      final categoryTempId = draft.parsedMenu.categories.single.tempId;
      final approval = await approveImportDraft(
        importJobId: job.id,
        decisions: [
          ImportReviewDecision(
            tempId: categoryTempId,
            outcome: ImportReviewOutcome.approved,
          ),
          for (final product in draft.parsedMenu.products)
            ImportReviewDecision(
              tempId: product.tempId,
              outcome: ImportReviewOutcome.approved,
            ),
        ],
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1, 0, 3),
      );
      expect((await jobRepository.findById(job.id))!.status,
          ImportStatus.approved);

      final commitResult = await commitImportDraft(
        importJobId: job.id,
        approval: approval,
        performedAt: DateTime(2026, 1, 1, 0, 4),
      );
      expect(commitResult.createdCategoryIds, hasLength(1));
      expect(commitResult.createdProductIds, hasLength(2));
      expect((await jobRepository.findById(job.id))!.status,
          ImportStatus.committed);

      final createdCategory = await categoryRepository
          .findById(commitResult.createdCategoryIds.single);
      expect(createdCategory!.name, 'Bowl');
      final createdProducts = await productRepository.findAll();
      expect(createdProducts, hasLength(2));

      await rollbackImportCommit(
        importJobId: job.id,
        commitResult: commitResult,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1, 0, 5),
      );

      expect((await jobRepository.findById(job.id))!.status,
          ImportStatus.rolledBack);
      final rolledBackCategory = await categoryRepository
          .findById(commitResult.createdCategoryIds.single);
      expect(rolledBackCategory!.isActive, isFalse);
      for (final productId in commitResult.createdProductIds) {
        final product = await productRepository.findById(productId);
        expect(product!.isAvailable, isFalse);
      }
    });

    test(
        'an unsupported source type fails parsing honestly, never fakes a '
        'result', () async {
      final job = await createImportJob(
        organizationId: 'org-1',
        restaurantId: 'restaurant-1',
        branchId: 'branch-1',
        source: const ImportSource(
          type: ImportSourceType.pdf,
          fileReference: null,
        ),
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      await expectLater(
        parseImportSource(
          importJobId: job.id,
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnsupportedImportSourceViolation>()),
      );
      expect((await jobRepository.findById(job.id))!.status,
          ImportStatus.parseFailed);
    });

    test('committing without approval is refused', () async {
      final job = await createImportJob(
        organizationId: 'org-1',
        restaurantId: 'restaurant-1',
        branchId: 'branch-1',
        source: const ImportSource(type: ImportSourceType.csv, rawText: _csv),
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );
      final rawMenu = await parseImportSource(
        importJobId: job.id,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );
      await createImportDraft(
        importJobId: job.id,
        parsedMenu: rawMenu,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      await expectLater(
        commitImportDraft(
          importJobId: job.id,
          approval: ImportApproval(
            importJobId: job.id,
            approvedByStaffId: 'manager-1',
            approvedAt: DateTime(2026, 1, 1),
          ),
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<ImportNotApprovedViolation>()),
      );
    });

    test('an unauthorized actor cannot create an import job', () async {
      final useCase = CreateImportJob(
        authorizationPolicy: const DenyAllImportPolicy(),
        idGenerator: SequentialImportJobIdGenerator(),
        repository: jobRepository,
        auditRepository: auditRepository,
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          restaurantId: 'restaurant-1',
          branchId: 'branch-1',
          source: const ImportSource(type: ImportSourceType.csv, rawText: ''),
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
