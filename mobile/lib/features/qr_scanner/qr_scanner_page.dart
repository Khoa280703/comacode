import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../connection/connection_providers.dart';
import '../../core/theme.dart';
import 'dart:convert';

/// QR Scanner page
///
/// Phase 06: Refactor to Riverpod
/// Scans QR code containing connection details (IP, port, token, fingerprint)
class QrScannerPage extends ConsumerStatefulWidget {
  const QrScannerPage({super.key});

  @override
  ConsumerState<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends ConsumerState<QrScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isScanning = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Handle QR code detection
  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning) return;

    for (final barcode in capture.barcodes) {
      if (barcode.rawValue != null) {
        _handleQrCode(barcode.rawValue!);
        break;
      }
    }
  }

  /// Process scanned QR code
  void _handleQrCode(String rawJson) {
    setState(() => _isScanning = false);

    // Validate QR payload format before connecting
    if (!_isValidQrPayload(rawJson)) {
      _showError('Invalid QR code format');
      setState(() => _isScanning = true);
      return;
    }

    // Connect using connection provider
    _connect(rawJson);
  }

  /// Validate QR payload has required fields
  bool _isValidQrPayload(String json) {
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded['ip'] is String &&
          (decoded['port'] is int) &&
          decoded['token'] is String &&
          decoded['fingerprint'] is String;
    } catch (_) {
      return false;
    }
  }

  /// Connect to host via provider
  Future<void> _connect(String qrJson) async {
    try {
      await ref.read(connectionStateProvider.notifier).connect(qrJson);

      if (mounted) {
        // Navigate to terminal on success
        Navigator.of(context).pushReplacementNamed('/terminal');
      }
    } catch (e) {
      if (mounted) {
        _showError('Connection failed: $e');
        setState(() => _isScanning = true);
      }
    }
  }

  /// Show error message
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: CatppuccinMocha.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        backgroundColor: CatppuccinMocha.mantle,
      ),
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Dark overlay
          Container(
            color: Colors.black.withValues(alpha: 0.3),
          ),

          // Scan frame
          Center(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                border: Border.all(
                  color: CatppuccinMocha.lavender,
                  width: 4,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              // Corner markers
              child: Stack(
                children: [
                  // Top-left
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: CatppuccinMocha.green, width: 4),
                          left: BorderSide(color: CatppuccinMocha.green, width: 4),
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                        ),
                      ),
                    ),
                  ),
                  // Top-right
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: CatppuccinMocha.green, width: 4),
                          right: BorderSide(color: CatppuccinMocha.green, width: 4),
                        ),
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(20),
                        ),
                      ),
                    ),
                  ),
                  // Bottom-left
                  Positioned(
                    bottom: 0,
                    left: 0,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: CatppuccinMocha.green, width: 4),
                          left: BorderSide(color: CatppuccinMocha.green, width: 4),
                        ),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(20),
                        ),
                      ),
                    ),
                  ),
                  // Bottom-right
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: CatppuccinMocha.green, width: 4),
                          right: BorderSide(color: CatppuccinMocha.green, width: 4),
                        ),
                        borderRadius: const BorderRadius.only(
                          bottomRight: Radius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Instructions
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: CatppuccinMocha.mantle.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Align QR code within frame',
                  style: TextStyle(
                    color: CatppuccinMocha.text,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
