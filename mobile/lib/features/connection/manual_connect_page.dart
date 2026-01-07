import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'connection_provider.dart';

/// Manual connection page (fallback when QR scanner unavailable)
///
/// Phase 04: Mobile App
/// Allows manual entry of connection parameters
class ManualConnectPage extends StatefulWidget {
  const ManualConnectPage({super.key});

  @override
  State<ManualConnectPage> createState() => _ManualConnectPageState();
}

class _ManualConnectPageState extends State<ManualConnectPage> {
  final _formKey = GlobalKey<FormState>();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '8443');
  final _tokenController = TextEditingController();
  final _fingerprintController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    _fingerprintController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Build QR JSON string format
      final qrJson = '''
{
  "ip": "${_ipController.text}",
  "port": ${int.parse(_portController.text)},
  "fingerprint": "${_fingerprintController.text}",
  "token": "${_tokenController.text}",
  "protocol_version": 1
}''';

      if (mounted) {
        final connectionProvider = context.read<ConnectionProvider>();
        await connectionProvider.connectWithQrString(qrJson);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manual Connect'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter connection details from your host terminal',
                style: TextStyle(
                  color: Color(0xFF6C7086),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // IP Address
              TextFormField(
                controller: _ipController,
                decoration: const InputDecoration(
                  labelText: 'Host IP',
                  hintText: '192.168.1.1',
                  prefixIcon: Icon(Icons.computer),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter host IP address';
                  }
                  // Basic IP validation
                  final parts = value.split('.');
                  if (parts.length != 4) {
                    return 'Invalid IP address';
                  }
                  for (final part in parts) {
                    final num = int.tryParse(part);
                    if (num == null || num < 0 || num > 255) {
                      return 'Invalid IP address';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Port
              TextFormField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: '8443',
                  prefixIcon: Icon(Icons.settings_ethernet),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter port number';
                  }
                  final port = int.tryParse(value);
                  if (port == null || port < 1 || port > 65535) {
                    return 'Invalid port (1-65535)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Auth Token
              TextFormField(
                controller: _tokenController,
                decoration: const InputDecoration(
                  labelText: 'Auth Token',
                  hintText: '64-character hex token',
                  prefixIcon: Icon(Icons.vpn_key),
                ),
                maxLength: 64,
                textCapitalization: TextCapitalization.none,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter authentication token';
                  }
                  if (value.length != 64) {
                    return 'Token must be 64 characters';
                  }
                  // Verify hex
                  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
                    return 'Token must be hexadecimal';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Certificate Fingerprint
              TextFormField(
                controller: _fingerprintController,
                decoration: const InputDecoration(
                  labelText: 'Certificate Fingerprint',
                  hintText: 'AA:BB:CC:DD:...',
                  prefixIcon: Icon(Icons.fingerprint),
                ),
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  UpperCaseTextFormatter(),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter certificate fingerprint';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Connect button
              ElevatedButton(
                onPressed: _isLoading ? null : _connect,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Connect', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uppercase text formatter for fingerprint input
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
