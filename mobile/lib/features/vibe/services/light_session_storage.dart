import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Lightweight session storage with debounce write and size limit
///
/// Strategy: "Tail Keepers"
/// - Debounce write: 1s
/// - Max file size: 500KB
/// - Trim to: 250KB (keep last 50%)
class LightSessionStorage {
  static const int _maxFileSize = 500 * 1024; // 500KB
  static const int _trimTarget = 250 * 1024; // 250KB
  static const int _streamChunkSize = 4096; // 4KB
  static const Duration _debounceInterval = Duration(seconds: 1);

  String? _sessionId;
  File? _storageFile;
  final StringBuffer _writeBuffer = StringBuffer();
  Timer? _debounceTimer;
  bool _isDisposed = false;
  bool _isWriting = false; // Mutex lock to prevent race condition

  /// Initialize storage for a session
  ///
  /// Creates storage file path: {appDocDir}/sessions/{sessionId}.txt
  /// Throws [ArgumentError] if sessionId contains invalid characters
  Future<void> init(String sessionId) async {
    if (_isDisposed) return;

    // Security: Validate sessionId to prevent directory traversal
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(sessionId)) {
      debugPrint('[LightStorage] Invalid sessionId: $sessionId');
      throw ArgumentError('Invalid sessionId: must contain only alphanumeric, underscore, or hyphen');
    }

    // Flush previous session if any
    if (_sessionId != null && _sessionId != sessionId) {
      await _flushToDisk();
    }

    _sessionId = sessionId;

    final appDir = await getApplicationDocumentsDirectory();
    final sessionsDir = Directory('${appDir.path}/sessions');

    // Create sessions directory if not exists
    if (!await sessionsDir.exists()) {
      await sessionsDir.create(recursive: true);
    }

    _storageFile = File('${sessionsDir.path}/$sessionId.txt');

    debugPrint('[LightStorage] Initialized for session: $sessionId');
  }

  /// Append data to buffer, trigger debounce timer
  ///
  /// Data is buffered in memory for up to 1s before flushing to disk
  void append(String data) {
    if (_isDisposed || data.isEmpty) return;

    _writeBuffer.write(data);

    // Cancel existing timer and start new one (debounce)
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceInterval, () {
      _flushToDisk();
    });
  }

  /// Flush buffer to disk asynchronously
  ///
  /// After write, check file size and trim if exceeded
  /// Uses mutex lock to prevent race condition
  Future<void> _flushToDisk() async {
    if (_isDisposed || _storageFile == null) return;
    if (_writeBuffer.isEmpty) return;

    // CRITICAL: Mutex lock to prevent race condition
    // If already writing (or trimming), skip this flush
    // Data remains in buffer and will be written next cycle
    if (_isWriting) return;

    _isWriting = true; // Lock

    final data = _writeBuffer.toString();
    _writeBuffer.clear();

    try {
      // Append to file (create if not exists)
      await _storageFile!.writeAsString(
        data,
        mode: FileMode.append,
        flush: true,
      );

      // Check size and trim if needed
      final stat = await _storageFile!.stat();
      if (stat.size > _maxFileSize) {
        await _trimFile();
      }
    } catch (e) {
      debugPrint('[LightStorage] Flush failed: $e');
      // Restore data to buffer for retry
      _writeBuffer.write(data);
    } finally {
      _isWriting = false; // Unlock
    }
  }

  /// Trim file to keep only last [_trimTarget] bytes
  ///
  /// Uses byte offset to avoid loading entire file into memory
  /// Called from within _flushToDisk so lock is already held
  Future<void> _trimFile() async {
    if (_storageFile == null) return;

    try {
      final stat = await _storageFile!.stat();
      if (stat.size <= _maxFileSize) return;

      final bytesToSkip = stat.size - _trimTarget;

      // Read file from offset
      final raf = await _storageFile!.open(mode: FileMode.read);
      try {
        await raf.setPosition(bytesToSkip);
        final remainingBytes =
            await raf.read(_trimTarget + 1024); // read a bit extra
        await raf.close();

        // Use utf8.decode for proper UTF-8 handling
        final text = utf8.decode(remainingBytes, allowMalformed: true);

        // Find first complete line (skip partial)
        final firstNewline = text.indexOf('\n');
        final cleanText =
            firstNewline >= 0 ? text.substring(firstNewline + 1) : text;

        // Write trimmed content
        await _storageFile!.writeAsString(cleanText, flush: true);

        debugPrint(
            '[LightStorage] Trimmed file: ${stat.size} -> ${cleanText.length} bytes');
      } catch (e) {
        await raf.close();
        rethrow;
      }
    } catch (e) {
      debugPrint('[LightStorage] Trim failed: $e');
    }
  }

  /// Load session history as a stream for instant first paint
  ///
  /// Returns `Stream<String>` that yields chunks of 4KB
  /// Uses utf8.decode for proper Unicode handling
  /// If file doesn't exist, returns empty stream
  Stream<String> load() async* {
    if (_storageFile == null) return;

    final file = _storageFile!;
    if (!await file.exists()) return;

    try {
      final raf = await file.open(mode: FileMode.read);
      try {
        final stat = await file.stat();
        int bytesRead = 0;

        while (bytesRead < stat.size) {
          final chunk = await raf.read(_streamChunkSize);
          if (chunk.isEmpty) break;

          bytesRead += chunk.length;

          // Use utf8.decode for proper Unicode handling
          yield utf8.decode(chunk, allowMalformed: true);
        }
      } finally {
        await raf.close();
      }
    } catch (e) {
      debugPrint('[LightStorage] Load failed: $e');
    }
  }

  /// Delete storage file (called when user clears terminal)
  Future<void> clear() async {
    if (_storageFile == null) return;

    // Cancel pending writes
    _debounceTimer?.cancel();
    _writeBuffer.clear();

    try {
      if (await _storageFile!.exists()) {
        await _storageFile!.delete();
        debugPrint('[LightStorage] Cleared session storage');
      }
    } catch (e) {
      debugPrint('[LightStorage] Clear failed: $e');
    }
  }

  /// Dispose storage, flush pending data, cancel timers
  Future<void> dispose() async {
    if (_isDisposed) return;

    // Cancel timer but do final flush BEFORE setting disposed flag
    _debounceTimer?.cancel();
    _debounceTimer = null;

    // Final flush with timeout to prevent hang
    try {
      await _flushToDisk().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          debugPrint('[LightStorage] Dispose flush timeout');
        },
      );
    } catch (e) {
      debugPrint('[LightStorage] Dispose flush failed: $e');
    }

    // Set disposed AFTER flush completes
    _isDisposed = true;
    _storageFile = null;
    _sessionId = null;
  }

  /// Flush immediately (called on AppLifecycleState.paused)
  Future<void> flushOnPause() async {
    _debounceTimer?.cancel();
    await _flushToDisk();
  }
}
