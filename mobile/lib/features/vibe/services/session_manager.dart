import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';

import '../models/session_status.dart';
import '../models/vibe_session.dart';

/// Session state for multi-session management
class SessionState {
  final Map<String, VibeSession> sessions;
  final String? activeSessionId;
  final String? error;

  const SessionState({
    this.sessions = const {},
    this.activeSessionId,
    this.error,
  });

  VibeSession? get activeSession =>
      activeSessionId != null ? sessions[activeSessionId] : null;

  List<VibeSession> get sessionList => sessions.values.toList()
    ..sort((a, b) => b.lastActive.compareTo(a.lastActive));

  SessionState copyWith({
    Map<String, VibeSession>? sessions,
    String? activeSessionId,
    String? error,
  }) {
    return SessionState(
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      error: error,
    );
  }
}

/// Session manager provider
///
/// Phase 02: Multi-Session Tab Architecture
/// Manages multiple PTY sessions with persistence
final sessionManagerProvider =
    StateNotifierProvider<SessionManager, SessionState>((ref) {
  return SessionManager();
});

/// Session manager for multi-PTY support
///
/// Features:
/// - Max 5 sessions limit
/// - 30-minute idle timeout
/// - Persistence to shared_preferences
class SessionManager extends StateNotifier<SessionState> {
  static const String _keySessions = 'vibe_sessions';
  static const String _keyActive = 'vibe_active_session';
  static const int _maxSessions = 5;
  // ignore: unused_field
  static const int _idleTimeoutMinutes = 30;

  Timer? _idleCheckTimer;
  SharedPreferences? _prefs;

  SessionManager() : super(const SessionState()) {
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadSessions();
    _startIdleCheck();
  }

  /// Start idle check timer
  void _startIdleCheck() {
    _idleCheckTimer?.cancel();
    _idleCheckTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _checkIdleSessions(),
    );
  }

  /// Check and close idle sessions
  void _checkIdleSessions() {
    final staleSessions = <String>[];
    for (final session in state.sessions.values) {
      if (session.isStale && session.id != state.activeSessionId) {
        staleSessions.add(session.id);
      }
    }
    for (final id in staleSessions) {
      closeSession(id);
    }
  }

  /// Create new session
  Future<bool> createSession({
    required String projectPath,
    required String projectName,
  }) async {
    // Check limit
    if (state.sessions.length >= _maxSessions) {
      state = state.copyWith(error: 'Max sessions ($_maxSessions) reached');
      return false;
    }

    // Create new terminal for this session
    final terminal = Terminal();

    final session = VibeSession.create(
      projectName: projectName,
      projectPath: projectPath,
      terminal: terminal,
    );

    final newSessions = Map<String, VibeSession>.from(state.sessions);
    newSessions[session.id] = session;

    state = state.copyWith(
      sessions: newSessions,
      activeSessionId: session.id,
      error: null,
    );

    await _saveSessions();
    return true;
  }

  /// Switch active session
  void switchSession(String sessionId) {
    if (!state.sessions.containsKey(sessionId)) {
      state = state.copyWith(error: 'Session not found');
      return;
    }

    final session = state.sessions[sessionId]!;
    final updated = session.touch();

    final newSessions = Map<String, VibeSession>.from(state.sessions);
    newSessions[sessionId] = updated;

    state = state.copyWith(
      sessions: newSessions,
      activeSessionId: sessionId,
      error: null,
    );

    _saveSessions();
  }

  /// Close session
  Future<void> closeSession(String sessionId) async {
    final newSessions = Map<String, VibeSession>.from(state.sessions);
    newSessions.remove(sessionId);

    String? newActiveId = state.activeSessionId;
    if (newActiveId == sessionId) {
      newActiveId = newSessions.isEmpty ? null : newSessions.keys.first;
    }

    state = state.copyWith(
      sessions: newSessions,
      activeSessionId: newActiveId,
    );

    await _saveSessions();
  }

  /// Rename session
  void renameSession(String sessionId, String newName) {
    final session = state.sessions[sessionId];
    if (session == null) return;

    final newSessions = Map<String, VibeSession>.from(state.sessions);
    newSessions[sessionId] = session.copyWith(projectName: newName);

    state = state.copyWith(sessions: newSessions);
    _saveSessions();
  }

  /// Update session status
  void updateStatus(String sessionId, SessionStatus status) {
    final session = state.sessions[sessionId];
    if (session == null) return;

    final newSessions = Map<String, VibeSession>.from(state.sessions);
    newSessions[sessionId] = session.copyWith(
      status: status,
      lastActive: DateTime.now(),
    );

    state = state.copyWith(sessions: newSessions);
  }

  /// Clear error state
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Save sessions to preferences
  Future<void> _saveSessions() async {
    final prefs = _prefs;
    if (prefs == null) return;

    try {
      // Save session metadata (without Terminal which isn't serializable)
      final sessionsJson = <String, dynamic>{};
      for (final session in state.sessions.values) {
        sessionsJson[session.id] = session.toJson();
      }
      await prefs.setString(_keySessions, jsonEncode(sessionsJson));

      if (state.activeSessionId != null) {
        await prefs.setString(_keyActive, state.activeSessionId!);
      } else {
        await prefs.remove(_keyActive);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to save sessions: $e');
    }
  }

  /// Load sessions from preferences
  Future<void> _loadSessions() async {
    final prefs = _prefs;
    if (prefs == null) return;

    try {
      final sessionsJsonStr = prefs.getString(_keySessions);
      if (sessionsJsonStr == null) return;

      final sessionsJson = jsonDecode(sessionsJsonStr) as Map<String, dynamic>;
      final activeId = prefs.getString(_keyActive);

      final restoredSessions = <String, VibeSession>{};

      for (final entry in sessionsJson.entries) {
        // Create new terminal for restored session
        final terminal = Terminal();
        final session = VibeSession.fromJson(
          entry.value as Map<String, dynamic>,
          terminal,
        );
        restoredSessions[session.id] = session;
      }

      state = SessionState(
        sessions: restoredSessions,
        activeSessionId:
            restoredSessions.containsKey(activeId) ? activeId : null,
      );
    } catch (e) {
      debugPrint('⚠️ Failed to load sessions: $e');
    }
  }

  @override
  void dispose() {
    _idleCheckTimer?.cancel();
    super.dispose();
  }
}
