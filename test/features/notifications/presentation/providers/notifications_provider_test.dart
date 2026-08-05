import 'package:abakus_one_v2/core/legal/legal_document_version.dart';
import 'package:abakus_one_v2/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationSettingsNotifier consent evidence (Sprint 9G, ADR-026)',
      () {
    test('no acceptance recorded by default', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(notificationSettingsProvider);

      expect(state.privacyPolicyAcceptedAt, isNull);
      expect(state.privacyPolicyAcceptedVersion, isNull);
      expect(state.termsAcceptedAt, isNull);
      expect(state.termsAcceptedVersion, isNull);
    });

    test('acceptPrivacyPolicy records the current DRAFT version and timestamp',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final now = DateTime(2026, 8, 5, 12, 0);

      container
          .read(notificationSettingsProvider.notifier)
          .acceptPrivacyPolicy(now);

      final state = container.read(notificationSettingsProvider);
      expect(state.privacyPolicyAcceptedAt, now);
      expect(
        state.privacyPolicyAcceptedVersion,
        LegalDocumentVersions.privacyPolicy,
      );
      // Accepting the privacy policy never implies terms acceptance too.
      expect(state.termsAcceptedAt, isNull);
    });

    test('acceptTerms records the current DRAFT version and timestamp', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final now = DateTime(2026, 8, 5, 12, 0);

      container.read(notificationSettingsProvider.notifier).acceptTerms(now);

      final state = container.read(notificationSettingsProvider);
      expect(state.termsAcceptedAt, now);
      expect(state.termsAcceptedVersion, LegalDocumentVersions.terms);
      expect(state.privacyPolicyAcceptedAt, isNull);
    });
  });
}
