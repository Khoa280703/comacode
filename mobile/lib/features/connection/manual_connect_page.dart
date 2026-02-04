import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'connection_providers.dart';
import '../project/project_picker_page.dart';
import '../../core/theme.dart';

/// Manual Connect Page - For simulator development
///
/// Allows entering connection details manually when QR scanning
/// is not available (e.g., iOS simulator without camera)
class ManualConnectPage extends ConsumerStatefulWidget {
  const ManualConnectPage({super.key});

  @override
  ConsumerState<ManualConnectPage> createState() => _ManualConnectPageState();
}

class _ManualConnectPageState extends ConsumerState<ManualConnectPage> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController(text: '127.0.0.1');
  final _portController = TextEditingController(text: '8443');
  final _tokenController = TextEditingController();
  final _fingerprintController = TextEditingController();

  bool _isConnecting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    _fingerprintController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      // Build JSON payload manually matching QrPayload.toJson() format
      final qrJson = '''
{
  "ip": "${_hostController.text}",
  "port": ${int.parse(_portController.text)},
  "fingerprint": "${_fingerprintController.text}",
  "token": "${_tokenController.text}",
  "protocol_version": 1
}''';

      await ref.read(connectionStateProvider.notifier).connect(qrJson);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ProjectPickerPage()),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CatppuccinMocha.base,
      appBar: AppBar(
        title: const Text('Manual Connect'),
        backgroundColor: CatppuccinMocha.mantle,
        foregroundColor: CatppuccinMocha.text,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Icon
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: CatppuccinMocha.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.settings_input_hdmi,
                      size: 40,
                      color: CatppuccinMocha.mauve,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                const Text(
                  'Connect to Host',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: CatppuccinMocha.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter connection details manually',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: CatppuccinMocha.subtext0,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 32),

                // Host field
                TextFormField(
                  controller: _hostController,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(color: CatppuccinMocha.text),
                  decoration: const InputDecoration(
                    labelText: 'Host',
                    hintText: '127.0.0.1 or IP address (NOT localhost)',
                    prefixIcon: Icon(Icons.computer, color: CatppuccinMocha.subtext0),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a host';
                    }
                    // Warn if using localhost (won't work with SocketAddr::parse)
                    if (value == 'localhost') {
                      return 'Use 127.0.0.1 instead of localhost';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Port field
                TextFormField(
                  controller: _portController,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: CatppuccinMocha.text),
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    hintText: '8443',
                    prefixIcon: Icon(Icons.numbers, color: CatppuccinMocha.subtext0),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a port';
                    }
                    final port = int.tryParse(value);
                    if (port == null || port < 1 || port > 65535) {
                      return 'Port must be 1-65535';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Token field
                TextFormField(
                  controller: _tokenController,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(color: CatppuccinMocha.text),
                  decoration: const InputDecoration(
                    labelText: 'Auth Token',
                    hintText: 'Enter authentication token',
                    prefixIcon: Icon(Icons.key, color: CatppuccinMocha.subtext0),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a token';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Fingerprint field
                TextFormField(
                  controller: _fingerprintController,
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(color: CatppuccinMocha.text),
                  decoration: const InputDecoration(
                    labelText: 'Fingerprint',
                    hintText: 'Server certificate fingerprint',
                    prefixIcon: Icon(Icons.fingerprint, color: CatppuccinMocha.subtext0),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a fingerprint';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Error message
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: CatppuccinMocha.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: CatppuccinMocha.red, width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: CatppuccinMocha.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: CatppuccinMocha.red, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Connect button
                ElevatedButton(
                  onPressed: _isConnecting ? null : _connect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CatppuccinMocha.mauve,
                    foregroundColor: CatppuccinMocha.crust,
                    disabledBackgroundColor: CatppuccinMocha.surface0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isConnecting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: CatppuccinMocha.crust,
                          ),
                        )
                      : const Text(
                          'Connect',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
                const SizedBox(height: 16),

                // Help text
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: CatppuccinMocha.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: CatppuccinMocha.blue, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Where to find these values?',
                            style: TextStyle(
                              color: CatppuccinMocha.blue,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Run the host agent and check the terminal output for the QR code details.',
                        style: TextStyle(
                          color: CatppuccinMocha.subtext0,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• Use 127.0.0.1 for localhost (NOT "localhost")',
                        style: TextStyle(
                          color: CatppuccinMocha.yellow,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        '• Fingerprint format: XX:XX:XX:... (hex pairs)',
                        style: TextStyle(
                          color: CatppuccinMocha.subtext0,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
