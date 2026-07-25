import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/saved_card_model.dart';

class SavedCardsNotifier extends Notifier<List<SavedCardModel>> {
  @override
  List<SavedCardModel> build() {
    return const [
      SavedCardModel(
        id: 'card_1',
        cardHolderName: 'Ahmet Yılmaz',
        lastFourDigits: '4321',
        expiryMonth: '12',
        expiryYear: '2029',
        cardBrand: 'Visa',
        isDefault: true,
      ),
      SavedCardModel(
        id: 'card_2',
        cardHolderName: 'Ahmet Yılmaz',
        lastFourDigits: '5678',
        expiryMonth: '08',
        expiryYear: '2031',
        cardBrand: 'Mastercard',
        isDefault: false,
      ),
    ];
  }

  void addCard({
    required String cardHolderName,
    required String cardNumber,
    required String expiryMonth,
    required String expiryYear,
  }) {
    final cleanNumber = cardNumber.replaceAll(' ', '');
    final lastFour = cleanNumber.length >= 4
        ? cleanNumber.substring(cleanNumber.length - 4)
        : '0000';

    String brand = 'Bilinmeyen';
    if (cleanNumber.startsWith('4')) {
      brand = 'Visa';
    } else if (cleanNumber.startsWith('5')) {
      brand = 'Mastercard';
    }

    final isFirstCard = state.isEmpty;

    final newCard = SavedCardModel(
      id: 'card_${DateTime.now().millisecondsSinceEpoch}',
      cardHolderName: cardHolderName,
      lastFourDigits: lastFour,
      expiryMonth: expiryMonth,
      expiryYear: expiryYear,
      cardBrand: brand,
      isDefault: isFirstCard,
    );

    state = [...state, newCard];
  }

  void deleteCard(String id) {
    final cardToDelete = state.firstWhere(
      (c) => c.id == id,
      orElse: () => state.first,
    );
    final wasDefault = cardToDelete.isDefault;

    final updatedList = state.where((c) => c.id != id).toList();

    if (wasDefault && updatedList.isNotEmpty) {
      updatedList[0] = updatedList[0].copyWith(isDefault: true);
    }

    state = updatedList;
  }

  void setDefaultCard(String id) {
    state = [for (final card in state) card.copyWith(isDefault: card.id == id)];
  }
}

final savedCardsProvider =
    NotifierProvider<SavedCardsNotifier, List<SavedCardModel>>(() {
  return SavedCardsNotifier();
});
