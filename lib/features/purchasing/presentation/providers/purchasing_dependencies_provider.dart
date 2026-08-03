import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/goods_receipt_id_generator.dart';
import '../../application/identity/goods_receipt_line_id_generator.dart';
import '../../application/identity/purchase_order_id_generator.dart';
import '../../application/identity/purchase_order_line_id_generator.dart';
import '../../application/identity/purchase_return_id_generator.dart';
import '../../application/identity/supplier_id_generator.dart';
import '../../application/identity/supplier_price_id_generator.dart';
import '../../application/identity/supplier_product_id_generator.dart';
import '../../data/goods_receipt_line_repository.dart';
import '../../data/goods_receipt_repository.dart';
import '../../data/purchase_order_line_repository.dart';
import '../../data/purchase_order_repository.dart';
import '../../data/purchase_return_repository.dart';
import '../../data/supplier_audit_entry_repository.dart';
import '../../data/supplier_branch_repository.dart';
import '../../data/supplier_price_repository.dart';
import '../../data/supplier_product_repository.dart';
import '../../data/supplier_repository.dart';

/// Central Riverpod wiring for `features/purchasing` — Phase 7
/// (`docs/decisions.md` ADR-024). Repository/id-generator providers
/// only, matching the pattern established across every other Phase 7
/// feature — no pre-wired, authorization-policy-baked use-case
/// providers.
final supplierRepositoryProvider = Provider<SupplierRepository>((ref) {
  return InMemorySupplierRepository();
});

final supplierIdGeneratorProvider = Provider<SupplierIdGenerator>((ref) {
  return SequentialSupplierIdGenerator();
});

final supplierBranchRepositoryProvider =
    Provider<SupplierBranchRepository>((ref) {
  return InMemorySupplierBranchRepository();
});

final supplierProductRepositoryProvider =
    Provider<SupplierProductRepository>((ref) {
  return InMemorySupplierProductRepository();
});

final supplierProductIdGeneratorProvider =
    Provider<SupplierProductIdGenerator>((ref) {
  return SequentialSupplierProductIdGenerator();
});

final supplierPriceRepositoryProvider =
    Provider<SupplierPriceRepository>((ref) {
  return InMemorySupplierPriceRepository();
});

final supplierPriceIdGeneratorProvider =
    Provider<SupplierPriceIdGenerator>((ref) {
  return SequentialSupplierPriceIdGenerator();
});

final purchaseOrderRepositoryProvider =
    Provider<PurchaseOrderRepository>((ref) {
  return InMemoryPurchaseOrderRepository();
});

final purchaseOrderIdGeneratorProvider =
    Provider<PurchaseOrderIdGenerator>((ref) {
  return SequentialPurchaseOrderIdGenerator();
});

final purchaseOrderLineRepositoryProvider =
    Provider<PurchaseOrderLineRepository>((ref) {
  return InMemoryPurchaseOrderLineRepository();
});

final purchaseOrderLineIdGeneratorProvider =
    Provider<PurchaseOrderLineIdGenerator>((ref) {
  return SequentialPurchaseOrderLineIdGenerator();
});

final goodsReceiptRepositoryProvider = Provider<GoodsReceiptRepository>((ref) {
  return InMemoryGoodsReceiptRepository();
});

final goodsReceiptIdGeneratorProvider =
    Provider<GoodsReceiptIdGenerator>((ref) {
  return SequentialGoodsReceiptIdGenerator();
});

final goodsReceiptLineRepositoryProvider =
    Provider<GoodsReceiptLineRepository>((ref) {
  return InMemoryGoodsReceiptLineRepository();
});

final goodsReceiptLineIdGeneratorProvider =
    Provider<GoodsReceiptLineIdGenerator>((ref) {
  return SequentialGoodsReceiptLineIdGenerator();
});

final purchaseReturnRepositoryProvider =
    Provider<PurchaseReturnRepository>((ref) {
  return InMemoryPurchaseReturnRepository();
});

final purchaseReturnIdGeneratorProvider =
    Provider<PurchaseReturnIdGenerator>((ref) {
  return SequentialPurchaseReturnIdGenerator();
});

final supplierAuditEntryRepositoryProvider =
    Provider<SupplierAuditEntryRepository>((ref) {
  return InMemorySupplierAuditEntryRepository();
});
