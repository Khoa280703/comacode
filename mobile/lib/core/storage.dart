import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// QR Payload model for host pairing
///
/// Matches the Rust QrPayload struct format
class QrPayload {
  final String ip;
  final int port;
  final String fingerprint;
  final String token;
  final int protocolVersion;

  QrPayload({
    required this.ip,
    required this.port,
    required this.fingerprint,
    required this.token,
    required this.protocolVersion,
  });

  /// Parse QR payload from JSON string
  factory QrPayload.fromJson(String jsonStr) {
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    return QrPayload(
      ip: json['ip'] as String,
      port: json['port'] as int,
      fingerprint: json['fingerprint'] as String,
      token: json['token'] as String,
      protocolVersion: json['protocol_version'] as int? ?? 1,
    );
  }

  /// Convert to JSON
  String toJson() {
    return jsonEncode({
      'ip': ip,
      'port': port,
      'fingerprint': fingerprint,
      'token': token,
      'protocol_version': protocolVersion,
    });
  }

  /// Display name for this host
  String get displayName => 'Host at $ip:$port';

  /// Unique key for storage
  String get storageKey => 'host_$fingerprint';
}

/// Secure storage wrapper for Comacode
///
/// Phase 04: Mobile App
/// Uses flutter_secure_storage for TOFU credential persistence
class AppStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  /// Save verified host (TOFU - auto-trust)
  ///
  /// After successful connection, save credentials for auto-reconnect
  static Future<void> saveHost(QrPayload payload) async {
    try {
      await _storage.write(key: payload.storageKey, value: payload.toJson());
      // Mark as last used
      await _storage.write(key: 'last_host', value: payload.fingerprint);
    } catch (e) {
      throw Exception('Failed to save host: $e');
    }
  }

  /// Get last connected host
  ///
  /// Returns the most recently used host for auto-reconnect
  static Future<QrPayload?> getLastHost() async {
    try {
      final fp = await _storage.read(key: 'last_host');
      if (fp == null) return null;

      final jsonStr = await _storage.read(key: 'host_$fp');
      if (jsonStr == null) return null;

      return QrPayload.fromJson(jsonStr);
    } catch (e) {
      return null;
    }
  }

  /// Get all saved hosts
  static Future<List<QrPayload>> getAllHosts() async {
    try {
      final allKeys = await _storage.readAll();
      final hosts = <QrPayload>[];

      for (final key in allKeys.keys) {
        if (key.startsWith('host_')) {
          final jsonStr = allKeys[key];
          if (jsonStr != null) {
            try {
              hosts.add(QrPayload.fromJson(jsonStr));
            } catch (_) {
              // Skip invalid entries
            }
          }
        }
      }

      return hosts;
    } catch (e) {
      return [];
    }
  }

  /// Delete specific host
  static Future<void> deleteHost(String fingerprint) async {
    await _storage.delete(key: 'host_$fingerprint');

    // If this was the last host, clear that reference
    final lastHost = await _storage.read(key: 'last_host');
    if (lastHost == fingerprint) {
      await _storage.delete(key: 'last_host');
    }
  }

  /// Clear all saved hosts
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  /// Check if any hosts are saved
  static Future<bool> hasHosts() async {
    final allKeys = await _storage.readAll();
    return allKeys.keys.any((key) => key.startsWith('host_'));
  }

  /// Save preference
  static Future<void> setPref(String key, String value) async {
    await _storage.write(key: 'pref_$key', value: value);
  }

  /// Get preference
  static Future<String?> getPref(String key) async {
    return await _storage.read(key: 'pref_$key');
  }

  /// Delete preference
  static Future<void> deletePref(String key) async {
    await _storage.delete(key: 'pref_$key');
  }
}
