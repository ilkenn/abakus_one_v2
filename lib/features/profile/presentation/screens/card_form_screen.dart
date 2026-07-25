import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../providers/saved_cards_provider.dart';

class CardFormScreen extends ConsumerStatefulWidget {
  const CardFormScreen({super.key});

  @override
  ConsumerState<CardFormScreen> createState() => _CardFormScreenState();
}

class _CardFormScreenState extends ConsumerState<CardFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _numberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    super.dispose();
  }

  void _saveCard() {
    if (_formKey.currentState?.validate() ?? false) {
      final expiryParts = _expiryController.text.split('/');
      final month = expiryParts[0].trim();
      final year = expiryParts.length > 1 ? expiryParts[1].trim() : '2030';

      ref.read(savedCardsProvider.notifier).addCard(
            cardHolderName: _nameController.text.trim(),
            cardNumber: _numberController.text.trim(),
            expiryMonth: month,
            expiryYear: year,
          );

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ödeme yöntemi başarıyla kaydedildi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Kart Ekle'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Kart Üzerindeki İsim',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Kart sahibi adı zorunludur'
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _numberController,
                keyboardType: TextInputType.number,
                maxLength: 19,
                decoration: const InputDecoration(
                  labelText: 'Kart Numarası',
                  counterText: '',
                ),
                validator: (v) {
                  if (v == null || v.replaceAll(' ', '').length < 16) {
                    return 'Geçerli bir kart numarası giriniz';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _expiryController,
                      decoration: const InputDecoration(
                        labelText: 'Son Kullanma Tarihi (AA/YY)',
                        hintText: 'AA/YY',
                      ),
                      validator: (v) {
                        if (v == null || !v.contains('/')) {
                          return 'AA/YY formatı zorunludur';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextFormField(
                      controller: _cvvController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 3,
                      decoration: const InputDecoration(
                        labelText: 'CVV',
                        counterText: '',
                      ),
                      validator: (v) => (v == null || v.trim().length < 3)
                          ? 'Geçersiz'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              ElevatedButton(
                onPressed: _saveCard,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                ),
                child: const Text('Kartı Güvenlice Kaydet'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
