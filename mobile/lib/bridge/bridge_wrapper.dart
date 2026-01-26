import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riverpod/riverpod.dart';
import 'ffi_helpers.dart';
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
  /// Phase VFS-Fix: Return raw stream to avoid .map() breaking Rust stream.
  /// The transformation to VfsEntry happens in the notifier instead.
  /// This fixes the bug where .map() silently fails with RustStreamSink.
  ///
  /// Returns a Stream that emits List of DirEntry (raw FRB type).
  Stream<List<DirEntry>> listDirectory(String path) {
    debugPrint('📁 [BridgeWrapper] listDirectory: $path');
    // Return raw stream - transform happens in vfs_notifier
    return frb_api.streamListDir(path: path);
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

  // ===== Session Management (Phase 05) =====
  // Note: FRB bindings not regenerated yet, using placeholder implementation
  // TODO: Replace with actual FRB calls when bindings are updated

  /// Create new session on backend
  Future<void> createSession({
    required String projectPath,
    required String sessionId,
  }) async {
    debugPrint('📝 [BridgeWrapper] createSession: $sessionId at $projectPath');
    // TODO: Call FRB when bindings regenerated
    // await frb_api.createSession(projectPath: projectPath, sessionId: sessionId);
  }

  /// Check if session exists (for re-attach)
  Future<bool> checkSession(String sessionId) async {
    debugPrint('🔍 [BridgeWrapper] checkSession: $sessionId');
    // TODO: Call FRB when bindings regenerated
    // return await frb_api.checkSession(sessionId: sessionId);
    return false; // Placeholder
  }

  /// Switch active session
  Future<void> switchSession(String sessionId) async {
    debugPrint('🔄 [BridgeWrapper] switchSession: $sessionId');
    // TODO: Call FRB when bindings regenerated
    // await frb_api.switchSession(sessionId: sessionId);
  }

  /// Close session
  Future<void> closeSession(String sessionId) async {
    debugPrint('❌ [BridgeWrapper] closeSession: $sessionId');
    // TODO: Call FRB when bindings regenerated
    // await frb_api.closeSession(sessionId: sessionId);
  }

  /// List all active sessions
  Future<List<String>> listSessions() async {
    debugPrint('📋 [BridgeWrapper] listSessions');
    // TODO: Call FRB when bindings regenerated
    // return await frb_api.listSessions();
    return []; // Placeholder
  }
}
