import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/clock_provider.dart';
import '../../../restaurant/presentation/providers/restaurant_operations_dependencies_provider.dart';
import '../../application/identity/guest_session_id_generator.dart';
import '../../application/use_cases/create_guest_session.dart';
import '../../application/use_cases/resolve_table_qr_token.dart';
import '../../data/dev_table_qr_seed.dart';
import '../../data/table_qr_code_repository.dart';
import '../../domain/i18n/guest_locale.dart';
import '../../domain/models/active_table_context.dart';

/// The [TableQrCodeRepository] currently in use — in-memory, seeded once
/// with `DevTableQrSeed`'s dev-only tokens (see that file's doc comment;
/// no backend exists yet). Mirrors `tableSessionRepositoryProvider`'s
/// shape. Deliberately reuses [restaurantTableRepositoryProvider] (the
/// same provider `FloorPlanEditorScreen`/`LiveFloorMapScreen` already
/// read) rather than a second, competing `RestaurantTableRepository`
/// instance — one in-memory table store for the whole app, not two.
final tableQrCodeRepositoryProvider = Provider<TableQrCodeRepository>((ref) {
  final repository = InMemoryTableQrCodeRepository();
  DevTableQrSeed.seed(
    tableRepository: ref.watch(restaurantTableRepositoryProvider),
    qrCodeRepository: repository,
  );
  return repository;
});

final guestSessionIdGeneratorProvider =
    Provider<GuestSessionIdGenerator>((ref) {
  return SequentialGuestSessionIdGenerator();
});

final resolveTableQrTokenProvider = Provider<ResolveTableQrToken>((ref) {
  return ResolveTableQrToken(
    clock: ref.watch(clockProvider),
    qrCodeRepository: ref.watch(tableQrCodeRepositoryProvider),
    tableRepository: ref.watch(restaurantTableRepositoryProvider),
  );
});

final createGuestSessionProvider = Provider<CreateGuestSession>((ref) {
  return CreateGuestSession(
    clock: ref.watch(clockProvider),
    idGenerator: ref.watch(guestSessionIdGeneratorProvider),
  );
});

/// The customer app's "current table" state — `null` until a QR scan
/// resolves and a `TableSession`/`GuestSession` are created, matching the
/// `NavigationNotifier`/`AuthNotifier` shape already established for
/// app-wide client state that must survive navigation (a plain
/// `Notifier<T>` singleton, not a `.family`/scoped provider).
class ActiveTableContextNotifier extends Notifier<ActiveTableContext?> {
  @override
  ActiveTableContext? build() => null;

  void set(ActiveTableContext context) {
    state = context;
  }

  /// Self-Order QR Faz 1 — the guest's manual override from
  /// `TableContextBadge`'s flag switcher. Only changes
  /// `GuestSession.selectedLanguageCode`; `detectedLanguageCode` (what the
  /// device originally reported) is never overwritten, per
  /// `docs/table_qr_architecture.md` §9.
  void setLanguage(String languageCode) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      guestSession: current.guestSession.copyWith(
        selectedLanguageCode: languageCode,
      ),
    );
  }

  /// No product rule defines when a customer's table context should be
  /// cleared today (see this feature's final report on "leaving table
  /// mode") — this method exists for completeness/tests, not because any
  /// UI currently calls it.
  void clear() {
    state = null;
  }
}

final activeTableContextProvider =
    NotifierProvider<ActiveTableContextNotifier, ActiveTableContext?>(() {
  return ActiveTableContextNotifier();
});

/// Self-Order QR Faz 1 — derives the active [GuestLocale] from
/// [activeTableContextProvider]'s `GuestSession.selectedLanguageCode`,
/// falling back to `tr` when there is no active table context yet (the
/// value is only actually rendered by screens reachable after a table
/// context exists).
final guestLocaleProvider = Provider<GuestLocale>((ref) {
  final context = ref.watch(activeTableContextProvider);
  if (context == null) return GuestLocale.tr;
  return guestLocaleFromLanguageCode(context.guestSession.selectedLanguageCode);
});
