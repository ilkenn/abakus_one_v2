import 'supported_language.dart';

/// Future seam for a paid AI translation service — Phase 6N
/// (`docs/decisions.md` ADR-023). "Do not call a paid AI translation
/// service" — no implementation of this interface exists anywhere in
/// this codebase; nothing constructs or calls it. Exists only so the
/// shape a future integration would fill is on record, mirroring how
/// `CrashReportingService`/`RemoteConfigService` stayed dormant
/// contracts before Firebase wiring was approved.
abstract interface class AiTranslationProvider {
  /// Returns a machine-generated translation of [sourceText] into
  /// [targetLanguage], or `null` if unavailable. A caller passing the
  /// result into `SetTranslationContent` must set
  /// `isMachineGenerated: true` — "do not fabricate translations" means
  /// this marker must always accompany machine output, never be
  /// presented as manually authored.
  Future<String?> translate({
    required String sourceText,
    required SupportedLanguage targetLanguage,
  });
}

/// The only implementation of [AiTranslationProvider] today — always
/// returns `null`. Not wired into any Riverpod provider; kept here only
/// to document the "no provider is integrated" state explicitly rather
/// than leaving the interface unimplemented and unexplained.
class UnavailableAiTranslationProvider implements AiTranslationProvider {
  const UnavailableAiTranslationProvider();

  @override
  Future<String?> translate({
    required String sourceText,
    required SupportedLanguage targetLanguage,
  }) async =>
      null;
}
