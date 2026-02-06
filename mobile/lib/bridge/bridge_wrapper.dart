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
      debugPrint('[BridgeWrapper] sendCommand called: "$command"');
      await frb_api.sendTerminalCommand(command: command);
      debugPrint('[BridgeWrapper] sendCommand completed');
    } catch (e) {
      debugPrint('[BridgeWrapper] sendCommand error: $e');
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
      // DEBUG: Log call to receiveEvent (throttled to first 5 calls)
      if (_receiveEventCallCount < 5) {
        debugPrint(
          '🔌 [BridgeWrapper] Calling frb_api.receiveTerminalEvent() #${_receiveEventCallCount + 1}',
        );
      }
      _receiveEventCallCount++;

      final event = await frb_api.receiveTerminalEvent();

      // DEBUG: Log result (throttled to first 5 calls)
      if (_receiveEventCallCount <= 5) {
        debugPrint(
          '📬 [BridgeWrapper] receiveTerminalEvent() returned event type: ${event.runtimeType}',
        );
      }

      return event;
    } catch (e) {
      debugPrint('💥 [BridgeWrapper] receiveEvent EXCEPTION: $e');
      throw Exception('Receive event failed: $e');
    }
  }

  int _receiveEventCallCount = 0;

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

  /// Send batched keystrokes (SSH Terminal Mode - Phase 1)
  ///
  /// Sends keystrokes with sequence tracking for latency measurement.
  /// More efficient than individual sendCommand() calls.
  Future<void> sendKeyBatch({
    required List<int> keys,
    required int sequenceNum,
  }) async {
    try {
      debugPrint(
        '[BridgeWrapper] sendKeyBatch: seq=$sequenceNum, ${keys.length} bytes',
      );
      await frb_api.sendKeyBatch(keys: keys, sequenceNum: sequenceNum);
    } catch (e) {
      debugPrint('[BridgeWrapper] sendKeyBatch error: $e');
      throw Exception('Send key batch failed: $e');
    }
  }

  /// Poll for KeyBatchAck (SSH Terminal Mode - Phase 2)
  ///
  /// Returns the highest sequence number acknowledged by server.
  /// Returns 0 if no pending acknowledgments.
  Future<int> pollKeyBatchAck() async {
    try {
      return await frb_api.pollKeyBatchAck();
    } catch (e) {
      debugPrint('[BridgeWrapper] pollKeyBatchAck error: $e');
      return 0;
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
    debugPrint('[BridgeWrapper] listDirectory: $path');
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
  // Note: FRB bindings regenerated - now calls actual FRB functions

  /// Create new session on backend
  Future<void> createSession({
    required String projectPath,
    required String sessionId,
  }) async {
    try {
      await frb_api.createSession(
        projectPath: projectPath,
        sessionId: sessionId,
      );
    } catch (e) {
      throw Exception('Failed to create session: $e');
    }
  }

  /// Check if session exists (for re-attach)
  Future<bool> checkSession(String sessionId) async {
    try {
      await frb_api.checkSession(sessionId: sessionId);
      return true; // If no error, session exists
    } catch (e) {
      return false; // Error means session doesn't exist
    }
  }

  /// Switch active session
  Future<void> switchSession(String sessionId) async {
    try {
      await frb_api.switchSession(sessionId: sessionId);
    } catch (e) {
      throw Exception('Failed to switch session: $e');
    }
  }

  /// Close session
  Future<void> closeSession(String sessionId) async {
    try {
      await frb_api.closeSession(sessionId: sessionId);
    } catch (e) {
      throw Exception('Failed to close session: $e');
    }
  }

  /// List all active sessions
  Future<List<String>> listSessions() async {
    // TODO: Implement when FRB bindings support return value
    // For now, return empty list
    return [];
  }

  // ===== File Viewer (Phase: File Viewer Feature) =====

  /// Read file content from remote server
  ///
  /// Uses request/poll pattern (same as VFS listing).
  /// Returns FileContentData with path, content, size, truncated.
  /// Returns null if timeout (3 seconds) or file not found.
  Future<frb_api.FileContentData?> readFile(
    String path, {
    int maxSize = 1024 * 1024, // 1MB default
  }) async {
    try {
      debugPrint('[BridgeWrapper] readFile: $path (maxSize: $maxSize)');

      // Send request
      await frb_api.requestReadFile(path: path, maxSize: BigInt.from(maxSize));

      // Poll for response (with timeout)
      const maxAttempts = 150; // 3 seconds at 20ms intervals
      const pollInterval = Duration(milliseconds: 20);

      for (var i = 0; i < maxAttempts; i++) {
        await Future.delayed(pollInterval);

        final result = await frb_api.receiveFileContent();
        if (result != null) {
          debugPrint('[BridgeWrapper] readFile success: ${result.size} bytes');
          return result;
        }
      }

      debugPrint('[BridgeWrapper] readFile timeout after 3s');
      return null;
    } catch (e) {
      debugPrint('[BridgeWrapper] readFile error: $e');
      throw Exception('Read file failed: $e');
    }
  }
}
