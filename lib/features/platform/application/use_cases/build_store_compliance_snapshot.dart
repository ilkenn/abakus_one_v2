import '../../../../core/errors/business_rule_violation.dart';
import '../../domain/authorization/platform_authorization_policy.dart';
import '../../domain/authorization/platform_authorized_action.dart';
import '../../domain/store_compliance_criterion.dart';
import '../../domain/store_compliance_criterion_status.dart';
import '../../domain/store_compliance_snapshot.dart';

/// Builds the [StoreComplianceSnapshot] — Phase 8Q
/// (`docs/decisions.md` ADR-025), "Store Compliance Foundation."
///
/// This does **not** submit or publish anything to the App Store or
/// Google Play — it only evaluates known, code-verifiable facts about
/// this codebase's current store-policy posture (account deletion,
/// data export, privacy policy, terms of use, data-safety
/// declarations) and reports them honestly, mirroring
/// `BuildReleaseReadinessSnapshot`'s shape one axis over. Gated by
/// `PlatformAuthorizedAction.managePlatformStoreCompliance` — the
/// wholly separate platform authorization stack (8A).
class BuildStoreComplianceSnapshot {
  const BuildStoreComplianceSnapshot({
    required PlatformAuthorizationPolicy authorizationPolicy,
  }) : _authorizationPolicy = authorizationPolicy;

  final PlatformAuthorizationPolicy _authorizationPolicy;

  static const _criteria = [
    StoreComplianceCriterion(
      key: 'accountDeletion',
      label: 'Hesap Silme',
      status: StoreComplianceCriterionStatus.notReady,
      note: 'AccountDataScreen._processDeleteAccount yalnızca bir onay '
          'diyaloğu ve başarı SnackBar\'ı gösteriyor — hiçbir repository/use '
          'case çağrısı yok, hiçbir veri gerçekten silinmiyor. Apple Kılavuz '
          'İlke 5.1.1(v) ve Google Play hesap silme gereksinimi karşılanmıyor.',
    ),
    StoreComplianceCriterion(
      key: 'dataExport',
      label: 'Veri Dışa Aktarma',
      status: StoreComplianceCriterionStatus.notReady,
      note: 'AccountDataProvider.requestDataExport sahte bir gecikmeli durum '
          'geçişi (Future.delayed) — gerçek bir dışa aktarma boru hattı yok.',
    ),
    StoreComplianceCriterion(
      key: 'privacyPolicyDocument',
      label: 'Gizlilik Politikası Belgesi',
      status: StoreComplianceCriterionStatus.notReady,
      note: 'LoginScreen yalnızca bir onay metni gösteriyor ("...Gizlilik '
          'Politikası\'nı kabul etmiş olursun") — bağlı bir ekran, rota veya '
          'yayınlanmış belge yok.',
    ),
    StoreComplianceCriterion(
      key: 'termsOfUseDocument',
      label: 'Kullanım Koşulları Belgesi',
      status: StoreComplianceCriterionStatus.notReady,
      note: 'Gizlilik politikasıyla aynı durum — LoginScreen\'deki metin '
          'dışında bağlı bir belge veya rota yok.',
    ),
    StoreComplianceCriterion(
      key: 'dataSafetyDeclaration',
      label: 'Mağaza Veri Güvenliği Beyanı '
          '(Google Play Data Safety / Apple Privacy Nutrition Label)',
      status: StoreComplianceCriterionStatus.manualStepRequired,
      note: 'Bu beyanlar mağaza konsollarında doldurulur, uygulama içinde '
          'değil — LogRedactor (P1-013) hangi alanların günlüğe hiç '
          'yazılmadığını zaten belgeliyor, bu da beyan için doğru bir temel '
          'oluşturuyor, ancak beyanın kendisi henüz doldurulmadı.',
    ),
  ];

  Future<StoreComplianceSnapshot> call({
    required String actorId,
  }) async {
    const action = PlatformAuthorizedAction.managePlatformStoreCompliance;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorId: actorId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    return StoreComplianceSnapshot(
      criteria: _criteria,
      generatedAt: DateTime.now(),
    );
  }
}
