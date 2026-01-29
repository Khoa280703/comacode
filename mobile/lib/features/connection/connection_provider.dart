import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../bridge/bridge_wrapper.dart';
import '../../core/storage.dart';

/// Connection state for Comacode
///
/// Phase 04: Mobile App
/// Manages QUIC connection state with TOFU auto-trust
class ConnectionProvider extends ChangeNotifier {
  bool _isConnected = false;
  bool _isConnecting = false;
  QrPayload? _currentHost;
  String? _error;
  final List<String> _terminalOutput = [];
  final BridgeWrapper _bridge = BridgeWrapper();

  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  QrPayload? get currentHost => _currentHost;
  String? get error => _error;
  List<String> get terminalOutput => List.unmodifiable(_terminalOutput);

  /// Check if has any saved hosts
  Future<bool> hasSavedHosts() async {
    return await AppStorage.hasHosts();
  }

  /// Connect using scanned/saved payload (auto-trust TOFU)
  ///
  /// Flow:
  /// 1. Parse QR string to QrPayload
  /// 2. Call Rust Bridge to connect
  /// 3. If successful, persist credentials (TOFU)
  /// 4. Enable wakelock
  Future<void> connectWithQrString(String qrJson) async {
    try {
      _setConnecting(true);
      _clearError();

      // Parse QR payload
      final payload = QrPayload.fromJson(qrJson);

      // Call Rust Bridge to connect
      await _bridge.connect(
        host: payload.ip,
        port: payload.port,
        token: payload.token,
        fingerprint: payload.fingerprint,
      );

      // If successful, persist credentials (TOFU)
      await AppStorage.saveHost(payload);

      _isConnected = true;
      _currentHost = payload;

      // Keep screen on during session
      await WakelockPlus.enable();

      _addTerminalOutput('Connected to ${payload.ip}:${payload.port}');
      _addTerminalOutput('Certificate fingerprint: ${payload.fingerprint}');
      _addTerminalOutput('\$ '); // Shell prompt

      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isConnected = false;
      _currentHost = null;
      notifyListeners();
      rethrow;
    } finally {
      _setConnecting(false);
    }
  }

  /// Auto-reconnect to last host
  Future<void> reconnectLast() async {
    final last = await AppStorage.getLastHost();
    if (last != null) {
      await connectWithQrString(last.toJson());
    } else {
      throw Exception('No saved host found');
    }
  }

  /// Disconnect from host
  Future<void> disconnect() async {
    try {
      await _bridge.disconnect();
    } catch (_) {
      // Ignore disconnect errors
    }

    _isConnected = false;
    _currentHost = null;

    // Disable wakelock
    await WakelockPlus.disable();

    // Clear terminal output
    _terminalOutput.clear();

    notifyListeners();
  }

  /// Send command to terminal
  void sendCommand(String command) {
    if (!_isConnected) {
      _error = 'Not connected';
      notifyListeners();
      return;
    }

    // Add command to output
    _addTerminalOutput(command);

    // TODO: Send via Rust Bridge
    // In real implementation:
    // await ComacodeBridge.sendCommand(command);

    // Echo the command (simulated)
    _addTerminalOutput('\$ ');
  }

  /// Add line to terminal output
  void _addTerminalOutput(String line) {
    _terminalOutput.add(line);
    notifyListeners();
  }

  /// Clear terminal output
  void clearTerminal() {
    _terminalOutput.clear();
    _addTerminalOutput('\$ ');
    notifyListeners();
  }

  /// Set connecting state
  void _setConnecting(bool connecting) {
    _isConnecting = connecting;
    notifyListeners();
  }

  /// Clear error
  void _clearError() {
    _error = null;
    notifyListeners();
  }

  /// Get display name for current host
  String? get hostDisplayName => _currentHost?.displayName;
}
