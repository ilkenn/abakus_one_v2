class SavedCardModel {
  final String id;
  final String cardHolderName;
  final String lastFourDigits;
  final String expiryMonth;
  final String expiryYear;
  final String cardBrand; // 'Visa', 'Mastercard', 'Bilinmeyen'
  final bool isDefault;

  const SavedCardModel({
    required this.id,
    required this.cardHolderName,
    required this.lastFourDigits,
    required this.expiryMonth,
    required this.expiryYear,
    required this.cardBrand,
    required this.isDefault,
  });

  SavedCardModel copyWith({
    String? id,
    String? cardHolderName,
    String? lastFourDigits,
    String? expiryMonth,
    String? expiryYear,
    String? cardBrand,
    bool? isDefault,
  }) {
    return SavedCardModel(
      id: id ?? this.id,
      cardHolderName: cardHolderName ?? this.cardHolderName,
      lastFourDigits: lastFourDigits ?? this.lastFourDigits,
      expiryMonth: expiryMonth ?? this.expiryMonth,
      expiryYear: expiryYear ?? this.expiryYear,
      cardBrand: cardBrand ?? this.cardBrand,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
