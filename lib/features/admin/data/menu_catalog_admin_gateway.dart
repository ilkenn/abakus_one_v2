import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../../core/services/functions/rest_callable_client.dart';

/// A minimal, display-safe projection of a `menuCategories` document —
/// deliberately not the customer-facing `features/menu/domain/models
/// /menu_category.dart` `MenuCategory` (that type is correct for its own
/// purpose, but this admin list only ever has what
/// `listMenuCategories` actually returns; forcing a shared model would
/// mean fabricating fields this flow never collects). Mirrors
/// `AdminPaymentSessionSummary`'s own precedent in this exact admin area.
class AdminMenuCategory {
  const AdminMenuCategory({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.isActive,
    this.defaultStation,
  });

  final String id;
  final String name;
  final int sortOrder;
  final bool isActive;
  final String? defaultStation;
}

class AdminMenuProduct {
  const AdminMenuProduct({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.basePriceMinorUnits,
    required this.isAvailable,
  });

  final String id;
  final String categoryId;
  final String name;
  final int basePriceMinorUnits;
  final bool isAvailable;
}

class MenuCatalogAdminException implements Exception {
  const MenuCatalogAdminException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'MenuCatalogAdminException($code): $message';
}

/// The real backend boundary for the admin Menü module — 2026-10-28.
/// `menuCategories`/`menuProducts` carry no `firestore.rules` entry at
/// all (served only via callables, by design — see `menuCatalogAdmin.ts`'s
/// own doc comment), so every read and write here goes through a real
/// Cloud Function, never a direct Firestore query/write.
abstract interface class MenuCatalogAdminGateway {
  Future<List<AdminMenuCategory>> listCategories(
      {required String organizationId});

  Future<String> createCategory({
    required String organizationId,
    required String restaurantId,
    required String name,
    int sortOrder = 0,
  });

  Future<List<AdminMenuProduct>> listProducts({required String organizationId});

  Future<String> createProduct({
    required String organizationId,
    required String restaurantId,
    required String categoryId,
    required String name,
    required int basePriceMinorUnits,
  });

  /// At least one of [name]/[basePriceMinorUnits] must be provided.
  Future<void> updateProduct({
    required String organizationId,
    required String productId,
    String? name,
    int? basePriceMinorUnits,
  });

  /// The "Tükendi (86)" toggle.
  Future<void> setProductAvailability({
    required String organizationId,
    required String productId,
    required bool isAvailable,
  });

  Future<void> deleteProduct({
    required String organizationId,
    required String productId,
  });
}

/// Fail-closed pre-Firebase fallback — mirrors
/// `UnavailableKitchenActionGateway`'s exact shape and reasoning: there is
/// no meaningful in-memory menu-catalog-admin concept to simulate (the
/// customer-facing `InMemoryMenuCategoryRepository`/
/// `InMemoryMenuProductRepository` are a different feature's shape, not
/// reusable here), so every method fails closed rather than silently
/// pretending to work.
class UnavailableMenuCatalogAdminGateway implements MenuCatalogAdminGateway {
  const UnavailableMenuCatalogAdminGateway();

  Never _unavailable() => throw const MenuCatalogAdminException(
        'unavailable',
        'Menü yönetimi servisi şu anda kullanılamıyor.',
      );

  @override
  Future<List<AdminMenuCategory>> listCategories({
    required String organizationId,
  }) async =>
      _unavailable();

  @override
  Future<String> createCategory({
    required String organizationId,
    required String restaurantId,
    required String name,
    int sortOrder = 0,
  }) async =>
      _unavailable();

  @override
  Future<List<AdminMenuProduct>> listProducts({
    required String organizationId,
  }) async =>
      _unavailable();

  @override
  Future<String> createProduct({
    required String organizationId,
    required String restaurantId,
    required String categoryId,
    required String name,
    required int basePriceMinorUnits,
  }) async =>
      _unavailable();

  @override
  Future<void> updateProduct({
    required String organizationId,
    required String productId,
    String? name,
    int? basePriceMinorUnits,
  }) async =>
      _unavailable();

  @override
  Future<void> setProductAvailability({
    required String organizationId,
    required String productId,
    required bool isAvailable,
  }) async =>
      _unavailable();

  @override
  Future<void> deleteProduct({
    required String organizationId,
    required String productId,
  }) async =>
      _unavailable();
}

class FirebaseMenuCatalogAdminGateway implements MenuCatalogAdminGateway {
  FirebaseMenuCatalogAdminGateway({RestCallableClient? restClient})
      : _restClient = restClient ?? RestCallableClient();

  final RestCallableClient _restClient;

  bool get _useRest =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw MenuCatalogAdminException(
      error.code,
      error.message ?? 'Menü işlemi gerçekleştirilemedi.',
    );
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    if (_useRest) {
      try {
        return await _restClient.call(name, data);
      } on RestCallableException catch (error) {
        throw MenuCatalogAdminException(error.code, error.message);
      }
    }
    try {
      final result = await functions.FirebaseFunctions.instance
          .httpsCallable(name)
          .call<Map<String, dynamic>>(data);
      return result.data;
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<List<AdminMenuCategory>> listCategories({
    required String organizationId,
  }) async {
    final result =
        await _call('listMenuCategories', {'organizationId': organizationId});
    final raw = (result['categories'] as List).cast<Map<dynamic, dynamic>>();
    return [
      for (final c in raw)
        AdminMenuCategory(
          id: c['id'] as String,
          name: c['name'] as String,
          sortOrder: c['sortOrder'] as int,
          isActive: c['isActive'] as bool,
          defaultStation: c['defaultStation'] as String?,
        ),
    ];
  }

  @override
  Future<String> createCategory({
    required String organizationId,
    required String restaurantId,
    required String name,
    int sortOrder = 0,
  }) async {
    final result = await _call('createMenuCategory', {
      'organizationId': organizationId,
      'restaurantId': restaurantId,
      'name': name,
      'sortOrder': sortOrder,
    });
    return result['id'] as String;
  }

  @override
  Future<List<AdminMenuProduct>> listProducts({
    required String organizationId,
  }) async {
    final result =
        await _call('listMenuProducts', {'organizationId': organizationId});
    final raw = (result['products'] as List).cast<Map<dynamic, dynamic>>();
    return [
      for (final p in raw)
        AdminMenuProduct(
          id: p['id'] as String,
          categoryId: p['categoryId'] as String,
          name: p['name'] as String,
          basePriceMinorUnits: p['basePriceMinorUnits'] as int,
          isAvailable: p['isAvailable'] as bool,
        ),
    ];
  }

  @override
  Future<String> createProduct({
    required String organizationId,
    required String restaurantId,
    required String categoryId,
    required String name,
    required int basePriceMinorUnits,
  }) async {
    final result = await _call('createMenuProduct', {
      'organizationId': organizationId,
      'restaurantId': restaurantId,
      'categoryId': categoryId,
      'name': name,
      'basePriceMinorUnits': basePriceMinorUnits,
    });
    return result['id'] as String;
  }

  @override
  Future<void> updateProduct({
    required String organizationId,
    required String productId,
    String? name,
    int? basePriceMinorUnits,
  }) async {
    await _call('updateMenuProduct', {
      'organizationId': organizationId,
      'productId': productId,
      if (name != null) 'name': name,
      if (basePriceMinorUnits != null)
        'basePriceMinorUnits': basePriceMinorUnits,
    });
  }

  @override
  Future<void> setProductAvailability({
    required String organizationId,
    required String productId,
    required bool isAvailable,
  }) async {
    await _call('setMenuProductAvailability', {
      'organizationId': organizationId,
      'productId': productId,
      'isAvailable': isAvailable,
    });
  }

  @override
  Future<void> deleteProduct({
    required String organizationId,
    required String productId,
  }) async {
    await _call('deleteMenuProduct', {
      'organizationId': organizationId,
      'productId': productId,
    });
  }
}
