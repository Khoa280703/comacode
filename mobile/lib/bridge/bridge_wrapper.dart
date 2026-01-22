import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riverpod/riverpod.dart';
import 'ffi_helpers.dart';
import '../models/dir_entry.dart';

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
      await RustLib.instance.api.mobileBridgeApiConnectToHost(
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
      await RustLib.instance.api.mobileBridgeApiSendTerminalCommand(
        command: command,
      );
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
      await RustLib.instance.api.mobileBridgeApiResizePty(
        rows: rows,
        cols: cols,
      );
    } catch (e) {
      throw Exception('Resize failed: $e');
    }
  }

  /// Receive next terminal event from server
  ///
  /// Call này trong loop để stream terminal output
  Future<TerminalEvent> receiveEvent() async {
    try {
      return await RustLib.instance.api.mobileBridgeApiReceiveTerminalEvent();
    } catch (e) {
      throw Exception('Receive event failed: $e');
    }
  }

  /// Disconnect from host
  Future<void> disconnect() async {
    try {
      await RustLib.instance.api.mobileBridgeApiDisconnectFromHost();
    } catch (e) {
      throw Exception('Disconnect failed: $e');
    }
  }

  /// Check if connected
  Future<bool> isConnected() async {
    try {
      return await RustLib.instance.api.mobileBridgeApiIsConnected();
    } catch (e) {
      return false;
    }
  }

  // ===== VFS (Virtual File System) Methods - Phase VFS-2 =====

  /// List directory entries from remote server
  ///
  /// Sends ListDir request and receives all chunks.
  /// Returns list of directory entries sorted (folders first, then alphabetically).
  Future<List<VfsEntry>> listDirectory(String path) async {
    try {
      debugPrint('📁 [BridgeWrapper] listDirectory: $path');

      // Request listing
      await RustLib.instance.api.mobileBridgeApiRequestListDir(path: path);

      // Receive chunks until has_more == false
      final entries = <VfsEntry>[];
      bool hasMore = true;

      // Poll for chunks with timeout
      int attempts = 0;
      const maxAttempts = 200; // 10 seconds max

      while (hasMore && attempts < maxAttempts) {
        await Future.delayed(const Duration(milliseconds: 50));

        final chunkResult = await RustLib.instance.api
            .mobileBridgeApiReceiveDirChunk();
        if (chunkResult == null) {
          attempts++;
          continue;
        }

        final chunk = chunkResult as (int, List<dynamic>, bool);
        final chunkIndex = chunk.$1;
        final chunkEntries = chunk.$2;
        hasMore = chunk.$3;

        debugPrint(
          '📥 [BridgeWrapper] Received chunk $chunkIndex with ${chunkEntries.length} entries, has_more=$hasMore',
        );

        // Convert FFI DirEntry to VfsEntry
        for (final entry in chunkEntries) {
          if (entry is DirEntry) {
            entries.add(VfsEntry.fromFrb(entry));
          }
        }

        attempts = 0; // Reset attempts on successful receive
      }

      if (attempts >= maxAttempts) {
        debugPrint('⚠️ [BridgeWrapper] Timeout waiting for chunks');
      }

      debugPrint(
        '✅ [BridgeWrapper] listDirectory completed: ${entries.length} entries',
      );
      return entries;
    } catch (e) {
      debugPrint('❌ [BridgeWrapper] listDirectory error: $e');
      rethrow;
    }
  }

  /// Parse QR payload from JSON string
  ///
  /// Parses QR code content to get connection details
  Future<QrPayload> parseQrPayload(String json) async {
    try {
      return await RustLib.instance.api.mobileBridgeApiParseQrPayload(
        json: json,
      );
    } catch (e) {
      throw Exception('Invalid QR payload: $e');
    }
  }
}
