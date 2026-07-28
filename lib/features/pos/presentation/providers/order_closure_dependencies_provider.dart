import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/closure_audit_entry_repository.dart';
import '../../data/order_closure_repository.dart';
import '../../domain/receipts/receipt_print_provider.dart';

/// The [OrderClosureRepository] currently in use —
/// [InMemoryOrderClosureRepository] today. Mirrors
/// `posOrderRepositoryProvider`/`paymentSessionRepositoryProvider`'s
/// existing shape.
final orderClosureRepositoryProvider = Provider<OrderClosureRepository>((ref) {
  return InMemoryOrderClosureRepository();
});

/// The [ClosureAuditEntryRepository] currently in use.
final closureAuditEntryRepositoryProvider =
    Provider<ClosureAuditEntryRepository>((ref) {
  return InMemoryClosureAuditEntryRepository();
});

/// The [ReceiptPrintProvider] currently in use —
/// [NoOpReceiptPrintProvider] today (no real printer integration exists;
/// see that class's own doc comment for why an honest always-unavailable
/// default is safe to wire here, unlike `PosAuthorizationPolicy`).
final receiptPrintProviderProvider = Provider<ReceiptPrintProvider>((ref) {
  return const NoOpReceiptPrintProvider();
});
