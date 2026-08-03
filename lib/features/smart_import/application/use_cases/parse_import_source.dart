import '../../../../core/errors/business_rule_violation.dart';
import '../../data/import_audit_entry_repository.dart';
import '../../data/import_job_repository.dart';
import '../../domain/import_audit_entry.dart';
import '../../domain/import_audit_event_type.dart';
import '../../domain/import_source_type.dart';
import '../../domain/import_status.dart';
import '../../domain/parsed_menu.dart';
import '../../domain/parsing/csv_menu_parser.dart';
import '../../domain/parsing/json_menu_parser.dart';

/// Runs the "Parse" stage of the Smart Import flow — Phase 7
/// (`docs/decisions.md` ADR-024). `Source -> Parse` only; **never**
/// `Source -> direct database write` — the returned [ParsedMenu] is
/// transient, handed to `NormalizeAndAnalyzeParsedMenu` next, and no
/// domain repository outside `ImportJobRepository` (status bookkeeping
/// only) is touched here.
///
/// Throws [UnsupportedImportSourceViolation] for any
/// [ImportSourceType] without `supportsDeterministicLocalParsing` —
/// "unsupported sources must produce an honest 'provider required'
/// result," never a fabricated parse.
class ParseImportSource {
  const ParseImportSource({
    required ImportJobRepository jobRepository,
    required ImportAuditEntryRepository auditRepository,
    CsvMenuParser csvParser = const CsvMenuParser(),
    JsonMenuParser jsonParser = const JsonMenuParser(),
  })  : _jobRepository = jobRepository,
        _auditRepository = auditRepository,
        _csvParser = csvParser,
        _jsonParser = jsonParser;

  final ImportJobRepository _jobRepository;
  final ImportAuditEntryRepository _auditRepository;
  final CsvMenuParser _csvParser;
  final JsonMenuParser _jsonParser;

  Future<ParsedMenu> call({
    required String importJobId,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    final job = await _jobRepository.findById(importJobId);
    if (job == null) {
      throw UnknownImportEntityViolation(
        entityName: 'ImportJob',
        id: importJobId,
      );
    }
    if (job.status != ImportStatus.pending) {
      throw InvalidImportStatusTransitionViolation(
        fromStatusName: job.status.name,
        toStatusName: ImportStatus.parsing.name,
      );
    }

    final sourceType = job.source.type;
    if (!sourceType.supportsDeterministicLocalParsing) {
      final failed = job.copyWith(
        status: ImportStatus.parseFailed,
        errorMessage: 'Bu kaynak türü için henüz bir sağlayıcı bağlanmadı: '
            '${sourceType.name}',
        revision: job.revision + 1,
      );
      await _jobRepository.save(failed);
      throw UnsupportedImportSourceViolation(sourceTypeName: sourceType.name);
    }

    await _jobRepository.save(job.copyWith(
      status: ImportStatus.parsing,
      startedAt: performedAt,
      revision: job.revision + 1,
    ));

    final rawText = job.source.rawText ?? '';
    final parsedMenu = switch (sourceType) {
      ImportSourceType.csv ||
      ImportSourceType.manualPaste =>
        _csvParser.parse(rawText),
      ImportSourceType.structuredJson => _jsonParser.parse(rawText),
      _ => throw UnsupportedImportSourceViolation(
          sourceTypeName: sourceType.name,
        ),
    };

    await _jobRepository.save(job.copyWith(
      status: ImportStatus.parsed,
      revision: job.revision + 2,
    ));

    await _auditRepository.appendEvent(ImportAuditEntry(
      id: '$importJobId-audit-parsed-${performedAt.microsecondsSinceEpoch}',
      branchId: job.branchId,
      actorId: performedByStaffId,
      type: ImportAuditEventType.sourceParsed,
      description: 'Source parsed: ${parsedMenu.products.length} products, '
          '${parsedMenu.categories.length} categories',
      targetEntityId: importJobId,
      timestamp: performedAt,
    ));

    return parsedMenu;
  }
}
