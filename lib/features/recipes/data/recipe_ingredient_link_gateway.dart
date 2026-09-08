import 'package:cloud_functions/cloud_functions.dart' as functions;

/// AP-5 Sprint 6 — the real backend boundary for `setRecipeIngredientLink`
/// (AP-5 Sprint 2's callable, which had no Dart caller anywhere until
/// now — `recipe_dependencies_provider.dart`'s own prior doc comment:
/// "no screen consumes this feature this sprint, callable-only per
/// confirmed scope"). Mirrors `PrintJobActionGateway`'s exact shape
/// (`lib/features/printing/data/print_job_action_gateway.dart`): an
/// interface, a [FirebaseRecipeIngredientLinkGateway], and a fail-closed
/// [UnavailableRecipeIngredientLinkGateway] for when Firebase isn't ready.
class RecipeIngredientLinkException implements Exception {
  const RecipeIngredientLinkException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'RecipeIngredientLinkException($code): $message';
}

class RecipeIngredientLinkLineInput {
  const RecipeIngredientLinkLineInput({
    required this.inventoryItemId,
    required this.quantitySmallestUnits,
    required this.unitCode,
  });

  final String inventoryItemId;
  final int quantitySmallestUnits;
  final String unitCode;

  Map<String, dynamic> toWire() => {
        'inventoryItemId': inventoryItemId,
        'quantitySmallestUnits': quantitySmallestUnits,
        'unitCode': unitCode,
      };
}

class SetRecipeIngredientLinkResult {
  const SetRecipeIngredientLinkResult({
    required this.linkId,
    required this.revision,
  });

  final String linkId;
  final int revision;
}

abstract interface class RecipeIngredientLinkGateway {
  Future<SetRecipeIngredientLinkResult> setLink({
    required String organizationId,
    required String productId,
    required String recipeVersionId,
    required List<RecipeIngredientLinkLineInput> ingredients,
  });
}

class FirebaseRecipeIngredientLinkGateway
    implements RecipeIngredientLinkGateway {
  const FirebaseRecipeIngredientLinkGateway();

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw RecipeIngredientLinkException(
      error.code,
      error.message ?? 'Reçete bağlantısı kaydedilemedi.',
    );
  }

  @override
  Future<SetRecipeIngredientLinkResult> setLink({
    required String organizationId,
    required String productId,
    required String recipeVersionId,
    required List<RecipeIngredientLinkLineInput> ingredients,
  }) async {
    try {
      final result = await functions.FirebaseFunctions.instance
          .httpsCallable('setRecipeIngredientLink')
          .call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'productId': productId,
        'recipeVersionId': recipeVersionId,
        'ingredients': [for (final line in ingredients) line.toWire()],
      });
      final data = result.data;
      return SetRecipeIngredientLinkResult(
        linkId: data['linkId'] as String,
        revision: data['revision'] as int,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }
}

class UnavailableRecipeIngredientLinkGateway
    implements RecipeIngredientLinkGateway {
  const UnavailableRecipeIngredientLinkGateway();

  @override
  Future<SetRecipeIngredientLinkResult> setLink({
    required String organizationId,
    required String productId,
    required String recipeVersionId,
    required List<RecipeIngredientLinkLineInput> ingredients,
  }) async {
    throw const RecipeIngredientLinkException(
        'unavailable', 'Reçete bağlantısı servisi şu anda kullanılamıyor.');
  }
}
