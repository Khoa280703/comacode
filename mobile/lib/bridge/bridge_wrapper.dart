import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riverpod/riverpod.dart';
import 'ffi_helpers.dart';
import '../models/dir_entry.dart';
import 'api.dart' as frb_api;

part 'bridge_wrapper.g.dart';

/// Riverpod provider cho BridgeWrapper
///
/// Phase 06: Refactor from static methods to provider pattern
/// để dễ test và integrate với Riverpod state management
@riverpod
BridgeWrapper bridgeWrapper(Ref ref) {
  return BridgeWrapper();
}

/// Flutter Rust Bridge wrapper
///
/// Wrapper around FRB-generated functions with error handling
/// và instance methods (không static) để dễ test/mock
class BridgeWrapper {
  /// Connect to remote host
  ///
  /// Uses QUIC protocol với TOFU fingerprint verification
  Future<void> connect({
    required String host,
    required int port,
    required String token,
    required String fingerprint,
  }) async {
    try {
      await frb_api.connectToHost(
        host: host,
        port: port,
        authToken: token,
        fingerprint: fingerprint,
      );
    } catch (e) {
      throw Exception('Connection failed: $e');
    }
  }

  /// Send command to remote terminal
  Future<void> sendCommand(String command) async {
    try {
      debugPrint('🔵 [BridgeWrapper] sendCommand called: "$command"');
      await frb_api.sendTerminalCommand(command: command);
      debugPrint('✅ [BridgeWrapper] sendCommand completed');
    } catch (e) {
      debugPrint('❌ [BridgeWrapper] sendCommand error: $e');
      throw Exception('Send command failed: $e');
    }
  }

  /// Resize PTY (for screen rotation support)
  ///
  /// Phase 06: Critical for screen rotation
  /// Send resize event to server để update PTY size
  Future<void> resizePty({required int rows, required int cols}) async {
    try {
      await frb_api.resizePty(rows: rows, cols: cols);
    } catch (e) {
      throw Exception('Resize failed: $e');
    }
  }

  /// Receive next terminal event from server
  ///
  /// Call này trong loop để stream terminal output
  Future<TerminalEvent> receiveEvent() async {
    try {
      return await frb_api.receiveTerminalEvent();
    } catch (e) {
      throw Exception('Receive event failed: $e');
    }
  }

  /// Disconnect from host
  Future<void> disconnect() async {
    try {
      await frb_api.disconnectFromHost();
    } catch (e) {
      throw Exception('Disconnect failed: $e');
    }
  }

  /// Check if connected
  Future<bool> isConnected() async {
    try {
      return await frb_api.isConnected();
    } catch (e) {
      return false;
    }
  }

  // ===== VFS (Virtual File System) Methods =====

  /// List directory entries from remote server using Stream API
  ///
  /// Phase VFS-Fix: Stream now properly awaits all data before emitting.
  /// The Rust side collects all entries, then sends single chunk.
  /// This fixes the race condition where onDone fired before onData.
  ///
  /// Returns a Stream that emits a single chunk with all entries.
  Stream<List<VfsEntry>> listDirectory(String path) {
    debugPrint('📁 [BridgeWrapper] listDirectory: $path');
    // Map DirEntry → VfsEntry
    return frb_api.streamListDir(path: path).map(
      (dirEntries) => dirEntries.map((e) => VfsEntry.fromFrb(e)).toList(),
    );
  }

  /// Parse QR payload from JSON string
  ///
  /// Parses QR code content to get connection details
  Future<QrPayload> parseQrPayload(String json) async {
    try {
      return await frb_api.parseQrPayload(json: json);
    } catch (e) {
      throw Exception('Invalid QR payload: $e');
    }
  }
}
