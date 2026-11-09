import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../../admin/domain/trusted_device/device_registration_state.dart';
import '../../../admin/presentation/providers/trusted_device_session_providers.dart';
import '../../../printing/data/windows_raw_printer_adapter.dart';
import '../../../printing/domain/receipt_codepage.dart';
import '../../data/pax_gmp3_terminal_client.dart';
import '../../application/use_cases/capture_offline_cash_payment.dart';
import '../../application/use_cases/ensure_offline_lease.dart';
import '../../application/use_cases/print_kitchen_ticket.dart';
import '../../application/use_cases/print_table_receipt.dart';
import '../../application/use_cases/sync_offline_payment_outbox.dart';
import '../../data/cash_register_gateway.dart';
import '../../data/fiscal_offline_gateway.dart';
import '../../data/offline_lease_store.dart';
import '../../data/offline_payment_outbox_repository.dart';
import '../../data/payment_gateway.dart';
import '../../data/pos_action_gateway.dart';
import '../../data/pos_operational_view_gateway.dart';
import '../../data/scale_reader_port.dart';

/// AP-3 continuation — POS workspace provider wiring, gated end-to-end on
/// the real trusted-device session (`docs/decisions.md` ADR-041). No
/// provider here ever fabricates a `PosDeviceContext` — it only exists once
/// [trustedDeviceSessionControllerProvider] genuinely reports
/// [ActiveSession]/[ExpiringRefreshing].

final posOperationalViewGatewayProvider =
    Provider<PosOperationalViewGateway>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (isFirebaseReady) return FirebasePosOperationalViewGateway();
  return const UnavailablePosOperationalViewGateway();
});

final posActionGatewayProvider = Provider<PosActionGateway>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (isFirebaseReady) return FirebasePosActionGateway();
  return const UnavailablePosActionGateway();
});

/// "Çok Tercih Edilenler" (Top 20), 2026-11-03 — product owner-approved
/// minimal design (`docs/business_rules.md` BR-POS-001). Deliberately a
/// plain (non-`autoDispose`) `FutureProvider.family`: fetched once per
/// [PosDeviceContext] and kept for the rest of this app session (the
/// product owner's own "oturum boyunca cache" ask) rather than refetched on
/// every rebuild — the staff-facing POS screen never needs this to be more
/// real-time than that. Call `ref.invalidate(topSellingProductsProvider(ctx))`
/// to force a refresh (e.g. a manual "yenile" action, if one is added later).
final topSellingProductsProvider =
    FutureProvider.family<List<PosTopSellingProduct>, PosDeviceContext>(
        (ref, ctx) {
  return ref.read(posOperationalViewGatewayProvider).getTopSellingProducts(
        organizationId: ctx.organizationId,
        branchId: ctx.branchId,
        deviceId: ctx.deviceId,
        deviceSessionId: ctx.deviceSessionId,
      );
});

/// AP-4 Wave D wiring — the real payment/cash/fiscal boundaries, gated on
/// Firebase readiness exactly like every gateway above. Never falls back to
/// an in-memory/mock implementation that could silently fabricate a money
/// result — see each `Unavailable*Gateway`'s own fail-closed doc comment.
final paymentGatewayProvider = Provider<PaymentGateway>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (isFirebaseReady) return FirebasePaymentGateway();
  return const UnavailablePaymentGateway();
});

final cashRegisterGatewayProvider = Provider<CashRegisterGateway>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (isFirebaseReady) return FirebaseCashRegisterGateway();
  return const UnavailableCashRegisterGateway();
});

final fiscalOfflineGatewayProvider = Provider<FiscalOfflineGateway>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (isFirebaseReady) return FirebaseFiscalOfflineGateway();
  return const UnavailableFiscalOfflineGateway();
});

/// `null` until a real trusted-device session is active — every POS screen
/// must treat `null` as "show the trusted-device gate," never attempt a
/// device-gated call with a placeholder context.
final posDeviceContextProvider = Provider<PosDeviceContext?>((ref) {
  final args = ref.watch(currentTrustedDeviceSessionControllerProvider);
  if (args == null) return null;
  final state = ref.watch(trustedDeviceSessionControllerProvider(args));
  return switch (state) {
    ActiveSession(:final deviceId, :final sessionId) => PosDeviceContext(
        organizationId: args.organizationId,
        branchId: args.branchId,
        deviceId: deviceId,
        deviceSessionId: sessionId,
      ),
    ExpiringRefreshing(:final deviceId, :final sessionId) => PosDeviceContext(
        organizationId: args.organizationId,
        branchId: args.branchId,
        deviceId: deviceId,
        deviceSessionId: sessionId,
      ),
    _ => null,
  };
});

/// Currently selected table (branch overview -> table workspace
/// navigation) — `null` while on the branch overview itself.
final selectedPosTableIdProvider = StateProvider<String?>((ref) => null);

/// 2026-11-05 real printer integration. Fails closed with
/// [UnavailableRawPrinterAdapter] off Windows (this app also builds for
/// Android/iOS/Web) rather than attempting a `winspool.drv` FFI call that
/// doesn't exist on those platforms.
final rawPrinterAdapterProvider = Provider<RawPrinterAdapter>((ref) {
  return !kIsWeb && Platform.isWindows
      ? const WindowsRawPrinterAdapter()
      : const UnavailableRawPrinterAdapter();
});

/// The staff-confirmed Windows-installed queue name for the till's 80mm
/// ESC/POS printer, durable across app restarts via `shared_preferences`
/// (same storage this file already uses for the offline payment outbox) —
/// deliberately not a hardcoded constant: a different till/branch may have
/// the printer installed under a different Windows queue name.
class ReceiptPrinterSettings {
  const ReceiptPrinterSettings(this._prefs);

  final SharedPreferences _prefs;

  static const _printerNameKey = 'posReceiptPrinterName';
  static const _codepageKey = 'posReceiptPrinterCodepage';
  static const _openCashDrawerOnCashPaymentKey =
      'posOpenCashDrawerOnCashPayment';

  /// The exact Windows queue name confirmed for the first till ("POS80
  /// Printer") — used only until staff override it for a different device.
  static const defaultPrinterName = 'POS80 Printer';

  String get printerName =>
      _prefs.getString(_printerNameKey) ?? defaultPrinterName;

  Future<void> setPrinterName(String name) =>
      _prefs.setString(_printerNameKey, name);

  /// Which `ESC t` character-code table [EscPosReceiptEncoder]/
  /// [EscPosKitchenTicketEncoder] select before printing — see
  /// [ReceiptCodepage]'s own doc comment. Defaults to
  /// [ReceiptCodepage.wpc1254] (full Turkish support); there is no
  /// automated way to detect from software whether a given table rendered
  /// correctly on the physical printer (ESC/POS has no such feedback
  /// channel), so this is a one-time, staff-confirmed choice, durable
  /// across restarts exactly like [printerName] above.
  ReceiptCodepage get codepage {
    final stored = _prefs.getString(_codepageKey);
    return ReceiptCodepage.values.firstWhere(
      (c) => c.name == stored,
      orElse: () => ReceiptCodepage.wpc1254,
    );
  }

  Future<void> setCodepage(ReceiptCodepage value) =>
      _prefs.setString(_codepageKey, value.name);

  /// Adım 4 (2026-11-07) — whether a successfully-confirmed cash tender
  /// should fire [kCashDrawerKickBytes] at the same printer queue.
  /// **Default flipped to `false` 2026-11-08** (operator's own explicit
  /// instruction: no physical drawer wired to the printer for the till
  /// currently under test) — still a real, working feature behind this
  /// same persisted setting, just off until a till that actually has a
  /// drawer turns it on.
  bool get openCashDrawerOnCashPayment =>
      _prefs.getBool(_openCashDrawerOnCashPaymentKey) ?? false;

  Future<void> setOpenCashDrawerOnCashPayment(bool value) =>
      _prefs.setBool(_openCashDrawerOnCashPaymentKey, value);
}

final receiptPrinterSettingsProvider =
    FutureProvider<ReceiptPrinterSettings>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return ReceiptPrinterSettings(prefs);
});

/// The branch's PAX A910SF terminal address, durable across app restarts
/// via `shared_preferences` — same reasoning as [ReceiptPrinterSettings]:
/// a different till/branch may have the terminal provisioned at a
/// different LAN IP/port, so this is never a hardcoded constant.
class PaxTerminalSettings {
  const PaxTerminalSettings(this._prefs);

  final SharedPreferences _prefs;

  static const _ipKey = 'posPaxTerminalIp';
  static const _portKey = 'posPaxTerminalPort';

  /// The device IP the operator's own setup notes gave (2026-11-06) —
  /// used only until staff override it for a different terminal/branch.
  static const defaultIp = '192.168.1.86';

  /// Standard ECR/GMP-3 TCP socket default; configurable to 8080 per the
  /// operator's own note that the terminal's port can be changed from its
  /// settings.
  static const defaultPort = 9000;

  String get ip => _prefs.getString(_ipKey) ?? defaultIp;

  Future<void> setIp(String value) => _prefs.setString(_ipKey, value);

  int get port => _prefs.getInt(_portKey) ?? defaultPort;

  Future<void> setPort(int value) => _prefs.setInt(_portKey, value);
}

final paxTerminalSettingsProvider =
    FutureProvider<PaxTerminalSettings>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return PaxTerminalSettings(prefs);
});

/// **No real implementation exists yet** — see
/// [UnavailablePaxGmp3TerminalClient]'s own doc comment
/// (`docs/decisions.md` ADR-032). Always resolves to the unavailable
/// stub, on every platform, until real PAX SDK/GMP-3 vendor
/// documentation is obtained and a real implementation is built behind
/// this same provider.
final paxGmp3TerminalClientProvider = Provider<PaxGmp3TerminalClient>((ref) {
  return const UnavailablePaxGmp3TerminalClient();
});

/// Adım 4 (2026-11-07) — same "no real transport yet" reasoning as
/// [paxGmp3TerminalClientProvider]. Always resolves to the unavailable
/// stub until a real serial-port scale protocol is specified.
final scaleReaderPortProvider = Provider<ScaleReaderPort>((ref) {
  return const UnavailableScaleReaderPort();
});

final printTableReceiptProvider = Provider<PrintTableReceipt>((ref) {
  return PrintTableReceipt(
    operationalViewGateway: ref.watch(posOperationalViewGatewayProvider),
    rawPrinterAdapter: ref.watch(rawPrinterAdapterProvider),
  );
});

/// Self-Order QR Faz 5 — same Windows printer queue as the till receipt
/// (`ReceiptPrinterSettings`'s own "POS80 Printer" default; the 23-rule
/// plan's own §6 names this exact queue for the kitchen ticket too, not a
/// separate device).
final printKitchenTicketProvider = Provider<PrintKitchenTicket>((ref) {
  return PrintKitchenTicket(
    rawPrinterAdapter: ref.watch(rawPrinterAdapterProvider),
  );
});

/// AP-4 Wave D — the device-local, durable offline cash-payment queue
/// (`docs`'s offline-outbox contract). `FutureProvider` because
/// `SharedPreferences.getInstance()` is itself async; every consumer reads
/// this once (`ref.watch(...).value`/`AsyncValue.when`) rather than each
/// constructing its own instance, so the whole app shares one queue.
final offlinePaymentOutboxRepositoryProvider =
    FutureProvider<OfflinePaymentOutboxRepository>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return SharedPreferencesOfflinePaymentOutboxRepository(prefs);
});

/// The real replay/sync use case, built once the durable queue is ready.
final syncOfflinePaymentOutboxProvider =
    FutureProvider<SyncOfflinePaymentOutbox>((ref) async {
  final repository =
      await ref.watch(offlinePaymentOutboxRepositoryProvider.future);
  final gateway = ref.watch(paymentGatewayProvider);
  return SyncOfflinePaymentOutbox(
    paymentGateway: gateway,
    outboxRepository: repository,
  );
});

/// AP-4 Wave E — the device's locally-held offline authorization lease
/// record. Same async-init reasoning as [offlinePaymentOutboxRepositoryProvider].
final offlineLeaseStoreProvider =
    FutureProvider<OfflineLeaseStore>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return SharedPreferencesOfflineLeaseStore(prefs);
});

/// Acquires/renews the held lease while online — the checkout screen calls
/// this opportunistically (e.g. on load) so a later, unpredictable loss of
/// connectivity already has a valid lease to capture against.
final ensureOfflineLeaseProvider =
    FutureProvider<EnsureOfflineLease>((ref) async {
  final leaseStore = await ref.watch(offlineLeaseStoreProvider.future);
  final gateway = ref.watch(fiscalOfflineGatewayProvider);
  return EnsureOfflineLease(
    fiscalOfflineGateway: gateway,
    leaseStore: leaseStore,
  );
});

/// The real offline-capture decision point the checkout screen's cash
/// tender submission calls into when the device is offline.
final captureOfflineCashPaymentProvider =
    FutureProvider<CaptureOfflineCashPayment>((ref) async {
  final leaseStore = await ref.watch(offlineLeaseStoreProvider.future);
  final repository =
      await ref.watch(offlinePaymentOutboxRepositoryProvider.future);
  return CaptureOfflineCashPayment(
    leaseStore: leaseStore,
    outboxRepository: repository,
  );
});
