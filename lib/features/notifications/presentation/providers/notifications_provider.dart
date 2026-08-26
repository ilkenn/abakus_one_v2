import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/legal/legal_document_version.dart';
import '../../domain/models/notification_settings_model.dart';

// Mevcut bildirim sayaçları ve listeleriyle entegre modern Riverpod Notifier katmanı
class NotificationSettingsNotifier extends Notifier<NotificationSettingsModel> {
  @override
  NotificationSettingsModel build() {
    return const NotificationSettingsModel();
  }

  void toggleOrderStatus(bool value) =>
      state = state.copyWith(orderStatus: value);
  void toggleCourierApproaching(bool value) =>
      state = state.copyWith(courierApproaching: value);
  void toggleCampaigns(bool value) => state = state.copyWith(campaigns: value);
  void toggleCoupons(bool value) => state = state.copyWith(coupons: value);
  void toggleLoyaltyPoints(bool value) =>
      state = state.copyWith(loyaltyPoints: value);

  /// Records versioned consent evidence — Sprint 9G
  /// (`docs/decisions.md` ADR-026). The current version is always
  /// `LegalDocumentVersions.privacyPolicy`/`.terms` (DRAFT — see that
  /// file's own doc comment); no caller may supply an arbitrary version
  /// string, so an acceptance record can never claim consent to content
  /// that was never actually shown.
  void acceptPrivacyPolicy(DateTime now) {
    state = state.copyWith(
      privacyPolicyAcceptedAt: now,
      privacyPolicyAcceptedVersion: LegalDocumentVersions.privacyPolicy,
    );
  }

  void acceptTerms(DateTime now) {
    state = state.copyWith(
      termsAcceptedAt: now,
      termsAcceptedVersion: LegalDocumentVersions.terms,
    );
  }

  void requestSystemPermission() {
    // Gerçek push notification servis bağlantı noktası simülasyonu
    state = state.copyWith(systemPermissionStatus: 'granted');
  }

  void denySystemPermission() {
    state = state.copyWith(systemPermissionStatus: 'denied');
  }
}

final notificationSettingsProvider =
    NotifierProvider<NotificationSettingsNotifier, NotificationSettingsModel>(
  () {
    return NotificationSettingsNotifier();
  },
);

/// No real notification backend exists yet (push messaging remains dormant
/// per CLAUDE.md §5 — no `firebase_messaging`, no server-side notification
/// record). Always `0`, honestly, rather than a hardcoded placeholder count
/// — never presented to the customer as a real unread number.
final unreadNotificationsCountProvider = Provider<int>((ref) => 0);
