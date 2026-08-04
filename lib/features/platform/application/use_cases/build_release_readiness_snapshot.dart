import '../../../../core/config/app_environment_config.dart';
import '../../../../core/errors/business_rule_violation.dart';
import '../../domain/authorization/platform_authorization_policy.dart';
import '../../domain/authorization/platform_authorized_action.dart';
import '../../domain/release_readiness_criterion.dart';
import '../../domain/release_readiness_criterion_status.dart';
import '../../domain/release_readiness_snapshot.dart';

/// Builds the [ReleaseReadinessSnapshot] — Phase 8P
/// (`docs/decisions.md` ADR-025), "Release Readiness Foundation."
///
/// This does **not** publish anything and has no relationship to any
/// app-store submission API — it only evaluates known, code-verifiable
/// facts about this codebase's current release posture (crash
/// reporting, environment separation, feature-flag production values,
/// build-version observability, platform monitoring/audit coverage)
/// and reports them honestly, mirroring
/// `BuildPlatformMonitoringSnapshot`'s "real counts plus an honest
/// static list of what's dormant" shape. Gated by
/// `PlatformAuthorizedAction.managePlatformRelease` — the wholly
/// separate platform authorization stack (8A).
class BuildReleaseReadinessSnapshot {
  const BuildReleaseReadinessSnapshot({
    required PlatformAuthorizationPolicy authorizationPolicy,
    required AppEnvironmentConfig environmentConfig,
  })  : _authorizationPolicy = authorizationPolicy,
        _environmentConfig = environmentConfig;

  final PlatformAuthorizationPolicy _authorizationPolicy;
  final AppEnvironmentConfig _environmentConfig;

  Future<ReleaseReadinessSnapshot> call({
    required String actorId,
  }) async {
    const action = PlatformAuthorizedAction.managePlatformRelease;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorId: actorId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final criteria = [
      ReleaseReadinessCriterion(
        key: 'environmentSeparation',
        label: 'Ortam Ayrımı (Dev/Staging/Prod)',
        status: ReleaseReadinessCriterionStatus.ready,
        note:
            'Üç ayrı Firebase projesi (${_environmentConfig.firebaseProjectId} '
            'dahil) provizyonlandı; build zamanında --dart-define=ENVIRONMENT '
            'ile seçiliyor.',
      ),
      const ReleaseReadinessCriterion(
        key: 'crashReporting',
        label: 'Çökme Raporlama',
        status: ReleaseReadinessCriterionStatus.notReady,
        note: 'CrashReportingService yalnızca NoOpCrashReportingService\'e '
            'çözümleniyor — aktif provider\'a bağlı gerçek bir sağlayıcı SDK\'sı '
            '(ör. Crashlytics) yok.',
      ),
      const ReleaseReadinessCriterion(
        key: 'remoteConfigFeatureFlags',
        label: 'Özellik Bayrağı Üretim Değerleri',
        status: ReleaseReadinessCriterionStatus.manualStepRequired,
        note: 'Firebase başarıyla başlatıldığında bayraklar gerçek Remote '
            'Config\'e bağlanır, ancak her bayrak için üretim değerleri henüz '
            'Firebase konsolunda ayarlanmadı — tümü belgelenen NoOp '
            'varsayılanlarını döndürüyor.',
      ),
      const ReleaseReadinessCriterion(
        key: 'appVersionObservability',
        label: 'Uygulama Sürümü Gözlemlenebilirliği',
        status: ReleaseReadinessCriterionStatus.notReady,
        note: 'Çalışan build\'in sürüm/derleme numarasını runtime\'da okuyacak '
            'bir bağımlılık (ör. package_info_plus) yok — tek kaynak '
            'pubspec.yaml\'in version alanı ve uygulama içinde hiçbir yerde '
            'gösterilmiyor.',
      ),
      const ReleaseReadinessCriterion(
        key: 'platformMonitoring',
        label: 'Platform İzleme',
        status: ReleaseReadinessCriterionStatus.ready,
        note: 'BuildPlatformMonitoringSnapshot (8O) platform operatörlerine '
            'gerçek, her çağrıda güncel hesaplanan çapraz-kiracı bir görünüm '
            'sağlıyor.',
      ),
      const ReleaseReadinessCriterion(
        key: 'integrationAuditTrail',
        label: 'Entegrasyon Denetim İzi',
        status: ReleaseReadinessCriterionStatus.ready,
        note: 'BuildIntegrationAuditCenterProjection (8N) marketplace/ödeme/'
            'entegrasyon olayları için gerçek, sorgulanabilir bir denetim izi '
            'sağlıyor.',
      ),
    ];

    return ReleaseReadinessSnapshot(
      environment: _environmentConfig.environment,
      criteria: criteria,
      generatedAt: DateTime.now(),
    );
  }
}
