import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../bridge/bridge_wrapper.dart';
import '../../core/storage.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../bridge/third_party/mobile_bridge/api.dart' as frb;

part 'connection_providers.g.dart';

/// Connection status enum
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Connection model with current state
class ConnectionModel {
  final ConnectionStatus status;
  final QrPayload? currentHost; // Dart model from storage.dart
  final String? errorMessage;

  const ConnectionModel({
    required this.status,
    this.currentHost,
    this.errorMessage,
  });

  factory ConnectionModel.disconnected() {
    return const ConnectionModel(status: ConnectionStatus.disconnected);
  }

  factory ConnectionModel.connecting() {
    return const ConnectionModel(status: ConnectionStatus.connecting);
  }

  factory ConnectionModel.connected(QrPayload host) {
    return ConnectionModel(
      status: ConnectionStatus.connected,
      currentHost: host,
    );
  }

  factory ConnectionModel.error(String message) {
    return ConnectionModel(
      status: ConnectionStatus.error,
      errorMessage: message,
    );
  }

  bool get isConnected => status == ConnectionStatus.connected;
  bool get isConnecting => status == ConnectionStatus.connecting;
  bool get isDisconnected => status == ConnectionStatus.disconnected;
  bool get hasError => status == ConnectionStatus.error;

  String? get hostDisplayName => currentHost?.displayName;
}

/// Terminal output state
class TerminalOutputModel {
  final List<String> lines;

  const TerminalOutputModel({required this.lines});

  factory TerminalOutputModel.initial() {
    return const TerminalOutputModel(lines: []);
  }

  TerminalOutputModel copyWith({List<String>? lines}) {
    return TerminalOutputModel(lines: lines ?? this.lines);
  }

  int get length => lines.length;
}

/// Riverpod provider for connection state
///
/// Phase 06: Refactor từ ChangeNotifier sang Riverpod
/// Dùng @riverpod annotation với code generation
@riverpod
class ConnectionState extends _$ConnectionState {
  @override
  ConnectionModel build() {
    return ConnectionModel.disconnected();
  }

  /// Connect using QR payload
  ///
  /// Flow:
  /// 1. Set connecting state
  /// 2. Parse QR string to Dart QrPayload (for storage/UI)
  /// 3. Parse QR string to FRB QrPayload (for connection)
  /// 4. Call Rust Bridge to connect
  /// 5. If success, persist credentials (TOFU)
  /// 6. Enable wakelock
  Future<void> connect(String qrJson) async {
    state = ConnectionModel.connecting();

    try {
      // Parse to Dart model first (for storage and UI)
      final dartPayload = QrPayload.fromJson(qrJson);

      // Parse to FRB opaque type
      final bridge = ref.read(bridgeWrapperProvider);
      final frbPayload = await bridge.parseQrPayload(qrJson);

      // Connect via Rust Bridge using FRB API getters
      await bridge.connect(
        host: frb.getQrIp(payload: frbPayload),
        port: frb.getQrPort(payload: frbPayload),
        token: frb.getQrToken(payload: frbPayload),
        fingerprint: frb.getQrFingerprint(payload: frbPayload),
      );

      // Persist credentials (TOFU) - use Dart model
      await AppStorage.saveHost(dartPayload);

      // Enable wakelock (keep screen on during session)
      await WakelockPlus.enable();

      state = ConnectionModel.connected(dartPayload);
    } catch (e) {
      state = ConnectionModel.error(e.toString());
      rethrow;
    }
  }

  /// Auto-reconnect to last saved host
  Future<void> reconnectLast() async {
    final last = await AppStorage.getLastHost();
    if (last != null) {
      await connect(last.toJson());
    } else {
      state = ConnectionModel.error('No saved host found');
      throw Exception('No saved host found');
    }
  }

  /// Disconnect from host
  Future<void> disconnect() async {
    try {
      final bridge = ref.read(bridgeWrapperProvider);
      await bridge.disconnect();
    } catch (_) {
      // Ignore disconnect errors
    } finally {
      // Disable wakelock
      await WakelockPlus.disable();

      // Reset state
      state = ConnectionModel.disconnected();
    }
  }

  /// Send command to terminal
  Future<void> sendCommand(String command) async {
    if (!state.isConnected) {
      state = ConnectionModel.error('Not connected');
      return;
    }

    try {
      final bridge = ref.read(bridgeWrapperProvider);
      await bridge.sendCommand(command);
    } catch (e) {
      state = ConnectionModel.error(e.toString());
    }
  }

  /// Check if has any saved hosts
  Future<bool> hasSavedHosts() async {
    return await AppStorage.hasHosts();
  }
}

/// Riverpod provider for terminal output
///
/// Stores terminal output lines
@riverpod
class TerminalOutput extends _$TerminalOutput {
  @override
  TerminalOutputModel build() {
    return TerminalOutputModel.initial();
  }

  /// Add line to terminal output
  void addLine(String line) {
    final newLines = [...state.lines, line];
    state = state.copyWith(lines: newLines);
  }

  /// Add multiple lines at once
  void addLines(List<String> lines) {
    final newLines = [...state.lines, ...lines];
    state = state.copyWith(lines: newLines);
  }

  /// Clear terminal output
  void clear() {
    state = const TerminalOutputModel(lines: []);
  }
}
