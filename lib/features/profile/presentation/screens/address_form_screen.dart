import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/repositories/address_data_repository.dart';
import '../../domain/models/address_model.dart';
import '../providers/addresses_provider.dart';

/// **LEGACY — not the canonical customer saved-address creation path**
/// (Faz P.2.1.1, `docs/decisions.md`). Writes through the legacy, purely
/// in-memory `AddressModel`/`addressesProvider` — no Firestore
/// persistence, no server address verification, no Google Maps
/// confirmation. `Profil → Adreslerim → +` no longer routes here (fixed
/// Faz P.2.1.1; now routes to `AddressSearchScreen`, the real
/// search → resolve → map confirmation → `SavedAddress` flow). **One
/// entry point still reaches this screen**, disclosed rather than
/// silently left: `features/cart/presentation/screens/checkout_screen.dart`'s
/// own "Adres Ekle" button — left untouched this phase per that screen's
/// own existing LEGACY marking (Faz P.1: "do not expand legacy delivery
/// code"), out of this phase's explicit Profil→Adresler scope. Not
/// deleted — kept exactly as-is, per explicit instruction, until a future
/// phase either migrates or removes it.
class AddressFormScreen extends ConsumerStatefulWidget {
  final AddressModel? addressToEdit;

  const AddressFormScreen({super.key, this.addressToEdit});

  @override
  ConsumerState<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends ConsumerState<AddressFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _buildingNameController;
  late final TextEditingController _apartmentNoController;
  late final TextEditingController _descriptionController;

  String? _selectedDistrict;
  String? _selectedNeighborhood;
  String? _selectedStreet;
  String? _selectedBuildingNo;

  double _currentLat = 41.0082;
  double _currentLng = 28.9784;
  bool _isDefault = false;

  @override
  void initState() {
    super.initState();
    final editItem = widget.addressToEdit;

    _titleController = TextEditingController(text: editItem?.title ?? '');
    _buildingNameController = TextEditingController(
      text: editItem?.buildingName ?? '',
    );
    _apartmentNoController = TextEditingController(
      text: editItem?.apartmentNo ?? '',
    );
    _descriptionController = TextEditingController(
      text: editItem?.addressDescription ?? '',
    );

    if (editItem != null) {
      _selectedDistrict = editItem.district;
      _selectedNeighborhood = editItem.neighborhood;
      _selectedStreet = editItem.street;
      _selectedBuildingNo = editItem.buildingNo;
      _currentLat = editItem.latitude;
      _currentLng = editItem.longitude;
      _isDefault = editItem.isDefault;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _buildingNameController.dispose();
    _apartmentNoController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _updateMapLocation() {
    if (_selectedDistrict != null && _selectedNeighborhood != null) {
      final details = AddressDataRepository.getZoneDetails(
        _selectedDistrict!,
        _selectedNeighborhood!,
      );
      if (details != null) {
        setState(() {
          _currentLat = details.latitude;
          _currentLng = details.longitude;
        });
      }
    }
  }

  void _saveForm() {
    if (_formKey.currentState?.validate() ?? false) {
      final finalAddress = AddressModel(
        id: widget.addressToEdit?.id ??
            'addr_${DateTime.now().millisecondsSinceEpoch}',
        title: _titleController.text.trim(),
        district: _selectedDistrict!,
        neighborhood: _selectedNeighborhood!,
        street: _selectedStreet!,
        buildingName: _buildingNameController.text.trim(),
        buildingNo: _selectedBuildingNo!,
        apartmentNo: _apartmentNoController.text.trim(),
        city: 'İstanbul',
        addressDescription: _descriptionController.text.trim(),
        latitude: _currentLat,
        longitude: _currentLng,
        isDefault: _isDefault,
      );

      if (widget.addressToEdit != null) {
        ref.read(addressesProvider.notifier).updateAddress(finalAddress);
      } else {
        ref.read(addressesProvider.notifier).addAddress(finalAddress);
      }

      Navigator.pop(context);
    }
  }

  void _showSearchSelectionBottomSheet({
    required String title,
    required List<String> items,
    required ValueChanged<String> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.kLarge.bottomLeft.x),
        ),
      ),
      builder: (context) {
        String filterQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredItems = items
                .where(
                  (i) => i.toLowerCase().contains(filterQuery.toLowerCase()),
                )
                .toList();
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  Text(
                    title,
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Ara...',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (val) {
                      setModalState(() => filterQuery = val);
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredItems.length,
                      itemBuilder: (context, idx) {
                        return ListTile(
                          title: Text(filteredItems[idx]),
                          onTap: () {
                            onSelected(filteredItems[idx]);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final districts = AddressDataRepository.getDistricts();
    final neighborhoods = _selectedDistrict != null
        ? AddressDataRepository.getNeighborhoods(_selectedDistrict!)
        : <String>[];
    final details = (_selectedDistrict != null && _selectedNeighborhood != null)
        ? AddressDataRepository.getZoneDetails(
            _selectedDistrict!,
            _selectedNeighborhood!,
          )
        : null;

    final streets = details?.streets ?? <String>[];
    final buildings = details?.buildings ?? <String>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.addressToEdit != null ? 'Adresi Düzenle' : 'Yeni Adres Ekle',
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          if (widget.addressToEdit != null)
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
              ),
              onPressed: () {
                ref
                    .read(addressesProvider.notifier)
                    .deleteAddress(widget.addressToEdit!.id);
                Navigator.pop(context);
              },
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Container(
              height: 180,
              width: double.infinity,
              color: AppColors.surfaceVariant,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _currentLat -= details.delta.dy * 0.0001;
                    _currentLng += details.delta.dx * 0.0001;
                  });
                },
                child: Stack(
                  children: [
                    CustomPaint(
                      size: Size.infinite,
                      painter: _MockMapGridPainter(),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_pin,
                            color: Colors.red,
                            size: 36,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: const BoxDecoration(
                              color: Colors.black87,
                              borderRadius: AppRadius.kSmall,
                            ),
                            child: Text(
                              '${_currentLat.toStringAsFixed(4)}, ${_currentLng.toStringAsFixed(4)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: AppRadius.kSmall,
                        ),
                        child: const Text(
                          'Parmağınızla pini haritada manuel kaydırabilirsiniz',
                          style: TextStyle(fontSize: 9),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Adres Başlığı (Örn: Ev, İş)',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Başlık zorunlu'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ListTile(
                    title: const Text('İlçe'),
                    subtitle: Text(_selectedDistrict ?? 'Seçiniz...'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      _showSearchSelectionBottomSheet(
                        title: 'İlçe Seçin',
                        items: districts,
                        onSelected: (val) {
                          setState(() {
                            _selectedDistrict = val;
                            _selectedNeighborhood = null;
                            _selectedStreet = null;
                            _selectedBuildingNo = null;
                          });
                          _updateMapLocation();
                        },
                      );
                    },
                  ),
                  const Divider(),
                  ListTile(
                    enabled: _selectedDistrict != null,
                    title: const Text('Mahalle'),
                    subtitle: Text(_selectedNeighborhood ?? 'Seçiniz...'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      _showSearchSelectionBottomSheet(
                        title: 'Mahalle Seçin',
                        items: neighborhoods,
                        onSelected: (val) {
                          setState(() {
                            _selectedNeighborhood = val;
                            _selectedStreet = null;
                            _selectedBuildingNo = null;
                          });
                          _updateMapLocation();
                        },
                      );
                    },
                  ),
                  const Divider(),
                  ListTile(
                    enabled: _selectedNeighborhood != null,
                    title: const Text('Cadde / Sokak'),
                    subtitle: Text(_selectedStreet ?? 'Seçiniz...'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      _showSearchSelectionBottomSheet(
                        title: 'Sokak Seçin',
                        items: streets,
                        onSelected: (val) {
                          setState(() {
                            _selectedStreet = val;
                          });
                        },
                      );
                    },
                  ),
                  const Divider(),
                  ListTile(
                    enabled: _selectedStreet != null,
                    title: const Text('Bina Numarası'),
                    subtitle: Text(_selectedBuildingNo ?? 'Seçiniz...'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      _showSearchSelectionBottomSheet(
                        title: 'Bina Numarası Seçin',
                        items: buildings,
                        onSelected: (val) {
                          setState(() {
                            _selectedBuildingNo = val;
                          });
                        },
                      );
                    },
                  ),
                  const Divider(),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _buildingNameController,
                    decoration: const InputDecoration(
                      labelText: 'Bina / Blok Adı (Opsiyonel)',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _apartmentNoController,
                    decoration: const InputDecoration(
                      labelText: 'Daire Numarası',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Adres Tarifi / Açıklama',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SwitchListTile(
                    title: const Text('Varsayılan Adres Yap'),
                    value: _isDefault,
                    trackColor: WidgetStateProperty.resolveWith<Color?>((
                      Set<WidgetState> states,
                    ) {
                      if (states.contains(WidgetState.selected)) {
                        return AppColors.primary;
                      }
                      return null;
                    }),
                    onChanged: (val) => setState(() => _isDefault = val),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  ElevatedButton(
                    onPressed: (_selectedDistrict != null &&
                            _selectedNeighborhood != null &&
                            _selectedStreet != null &&
                            _selectedBuildingNo != null)
                        ? _saveForm
                        : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                    ),
                    child: const Text('Adresi Kaydet'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MockMapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintGrid = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1.0;

    for (double i = 0; i < size.width; i += 20) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paintGrid);
    }
    for (double i = 0; i < size.height; i += 20) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paintGrid);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
