import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/active_table_context_provider.dart';
import '../providers/table_guest_session_dependencies_provider.dart';
import 'table_confirmed_screen.dart';

/// Real entry point for "Masada Sipariş" — both Home's order-mode card and
/// the center-QR "Masada Sipariş Ver" sheet action push this exact same
/// screen (see `home_screen.dart`/`main_navigation_screen.dart`), so there
/// is only ever one scanner implementation.
///
/// Scans with a real camera (`mobile_scanner`), previews the decoded token
/// via [tableGuestSessionGatewayProvider]'s `resolveToken` (the
/// server-authoritative `resolveTableQrToken` Cloud Function — Phase 3;
/// the client never parses the token itself), then — only on a `valid`
/// preview — establishes a technical identity and opens a real,
/// server-authoritative Table Guest Session via
/// [openTableGuestSessionFromQrScanProvider], populating
/// [activeTableContextProvider] before handing off to
/// [TableConfirmedScreen]. Anything else (`notFound`/`invalid`/`expired`,
/// a camera-permission failure, Firebase not ready) shows a plain Turkish
/// message and lets the customer retry — never a simulated success.
class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({super.key});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  late final MobileScannerController _controller;

  /// Guards against a code still in frame firing `onDetect` dozens of
  /// times a second, and against a slow resolution being triggered twice
  /// by two rapid detections of the same code.
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final token =
        capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (token == null || token.isEmpty) return;

    if (!ref.read(firebaseReadyProvider)) {
      setState(() {
        _errorMessage =
            'QR ile masaya oturma şu anda kullanılamıyor. Lütfen tekrar '
            'deneyin.';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    final preview =
        await ref.read(tableGuestSessionGatewayProvider).resolveToken(token);

    if (!preview.isUsable) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorMessage = _messageFor(preview.status);
      });
      return;
    }

    try {
      final tableContext =
          await ref.read(openTableGuestSessionFromQrScanProvider).call(token);

      ref.read(activeTableContextProvider.notifier).set(tableContext);

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TableConfirmedScreen(
            branchName: tableContext.branchName,
            tableName: tableContext.tableName,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorMessage =
            'Masa açılırken bir sorun oluştu. Lütfen tekrar deneyin.';
      });
    }
  }

  /// [status] is [TableQrPreview.status] verbatim — `'valid'` never
  /// reaches here since callers only consult this after `!preview
  /// .isUsable`, but is included for an exhaustive, fail-safe default
  /// rather than assuming the caller always guards correctly.
  String _messageFor(String status) {
    return switch (status) {
      'notFound' => 'Bu QR kod tanınmadı. Lütfen masandaki kodu tekrar okut.',
      'invalid' =>
        'Bu QR kod şu anda geçerli değil. Lütfen masandaki kodu kontrol et '
            'veya bir çalışana bildir.',
      'expired' => 'Bu QR kodun süresi dolmuş. Lütfen bir çalışana bildir.',
      // Faz R.1C.2 §2/§20 — exact required message, no reservation details
      // of any kind (no time, no party size, no customer/staff info).
      'reserved' => 'Bu masa rezerve edilmiştir. Lütfen yetkili ile görüşün.',
      _ => 'Bu QR kod şu anda kullanılamıyor. Lütfen tekrar deneyin.',
    };
  }

  void _retry() {
    setState(() => _errorMessage = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('QR ile Sipariş'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => _CameraError(
                message: _cameraErrorMessage(error),
              ),
            ),
            _ScanOverlay(isProcessing: _isProcessing),
            Positioned(
              left: AppSpacing.xl,
              right: AppSpacing.xl,
              bottom: AppSpacing.xl,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_errorMessage != null) ...[
                    _ErrorBanner(message: _errorMessage!, onRetry: _retry),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  Text(
                    'Masandaki QR kodu kare içine hizala.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _cameraErrorMessage(MobileScannerException error) {
    return switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Kamera izni verilmedi. QR taramak için ayarlardan kamera erişimine '
            'izin ver.',
      MobileScannerErrorCode.unsupported =>
        'Bu cihazda kamera ile QR tarama desteklenmiyor.',
      _ => 'Kamera açılırken bir sorun oluştu. Lütfen tekrar deneyin.',
    };
  }
}

class _ScanOverlay extends StatelessWidget {
  final bool isProcessing;

  const _ScanOverlay({required this.isProcessing});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: AppRadius.kLarge,
            ),
          ),
          if (isProcessing) ...[
            const SizedBox(height: AppSpacing.xl),
            const CircularProgressIndicator(color: Colors.white),
          ],
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.kMedium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('Tekrar Dene'),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  final String message;

  const _CameraError({required this.message});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                color: Colors.white,
                size: 48,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                message,
                style: AppTypography.bodyLarge.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
