# SSH-like Terminal Refactor - Progress Report

**Plan**: `260109-0109-ssh-like-terminal-refactor`
**Status**: In Progress (4/5 phases complete)
**Last Updated**: 2026-01-09

---

## Overview

Clean slate refactor để fix terminal I/O theo pattern SSH, sửa protocol framing bug, xoá toàn bộ debug code.

**Root Cause**: Protocol framing bug - dùng `read()` thay vì `read_exact()` cho messages có length prefix.

---

## Phase Progress

| Phase | Name | Status | Date | Notes |
|-------|------|--------|------|-------|
| 0 | Clean Slate Revert | ✅ Done | 2026-01-09 | Removed ping workaround, Vietnamese comments, emoji |
| 1 | Protocol Framing Fix | ✅ Done | 2026-01-09 | Added MessageReader, read_exact() pattern |
| 2 | Client Cleanup | ✅ Done | 2026-01-09 | SIGWINCH handling, raw mode warning |
| 3 | Server Cleanup | ✅ Done | 2026-01-09 | spawn_session_with_config() helper, handler cleanup |
| 4 | PTY Pump Refactor | ⏳ Pending | - | Smart flush with 5ms latency |

**Overall Progress**: 80% (4/5 phases)

---

## Phase 00: Clean Slate Revert ✅

**Completed**: 2026-01-09

### Changes
- Removed ping workaround from `main.rs:150-152`
- Removed all Vietnamese comments and emoji output
- Simplified Input/Command handlers in `quic_server.rs`
- Kept correct SSH patterns: resize before spawn, env vars, eager spawn

### Files Modified
- `crates/cli_client/src/main.rs`
- `crates/hostagent/src/quic_server.rs`

### Commit
```
f166be6 refactor(terminal): phase 00 clean slate revert
```

---

## Phase 01: Protocol Framing Fix ✅

**Completed**: 2026-01-09

### Root Cause Fixed
Protocol framing bug: `read()` trả về partial data → `MessageCodec::decode()` fail

### Changes
1. **NEW**: `crates/cli_client/src/message_reader.rs`
   - MessageReader helper với `read_exact()` pattern
   - DoS protection: 16MB message size limit

2. **MODIFIED**: `crates/cli_client/src/main.rs`
   - Handshake dùng MessageReader
   - Recv loop dùng `reader.read_message()` trực tiếp

3. **MODIFIED**: `crates/hostagent/src/quic_server.rs`
   - `handle_stream()` dùng `read_exact()` cho length prefix
   - `read_exact()` cho payload
   - Size validation trước khi allocate buffer

### Protocol Format
```
[4 bytes length (big endian)] [N bytes payload]
```

### Files Modified
- `crates/cli_client/src/message_reader.rs` (NEW)
- `crates/cli_client/src/main.rs`
- `crates/hostagent/src/quic_server.rs`

### Test Results
- ✅ Compilation passed (cli_client + hostagent)
- ✅ Code review: 0 critical issues

### Commit
```
203d0a8 refactor(terminal): phase 01 protocol framing fix
```

---

## Phase 02: Client Cleanup ✅

**Completed**: 2026-01-09

### Changes
1. **Raw mode warning** - Hiển thị error details khi raw mode fail
2. **SIGWINCH handler** - Dynamic terminal resize support
   - Spawns async task để listen cho window change signals
   - Gửi Resize message tự động khi user resize terminal
   - Hỗ trợ vim/htop resize dynamics

### Files Modified
- `crates/cli_client/src/main.rs`
- Added import: `tokio::signal::unix::{signal, SignalKind}`

### Test Results
- ✅ Compilation passed (cli_client)
- ✅ Clippy: 0 warnings
- ✅ Code review: 0 critical issues

### Commit
```
f2392f9 refactor(terminal): phase 02 client cleanup + SIGWINCH support
```

---

## Phase 03: Server Cleanup ✅

**Completed**: 2026-01-09

### Changes
1. **spawn_session_with_config() helper** - Extract duplicate spawn logic
   - Consolidated PTY spawn code from Input/Command handlers
   - Single source of truth for session initialization
   - Config struct with all spawn parameters

2. **Handler simplification** - Input/Command cleanup
   - Both handlers use spawn_session_with_config()
   - Removed ~60 lines of duplicate code
   - Consistent error handling

3. **Logging cleanup** - debug → trace
   - Spawn details demoted to trace level
   - Reduced log noise in production

### Files Modified
- `crates/hostagent/src/quic_server.rs`

### Code Review
- ✅ Compilation passed (hostagent)
- ✅ Clippy: 0 warnings
- ✅ 0 critical issues

### Commit
```
[COMMIT_HASH] refactor(terminal): phase 03 server cleanup + spawn helper
```

---

## Phase 04: PTY Pump Refactor ⏳

**Status**: Pending

### Planned Tasks
- Smart flush with 5ms latency (not 50ms!)
- Immediate send for small reads (typing)
- Batch for large reads (bulk output)
- Fix get_pty_reader to clone receiver

**Estimated**: 4h

---

## Git Status

```
Branch: main
Last commits:
  [COMMIT_HASH] refactor(terminal): phase 03 server cleanup + spawn helper
  f2392f9 refactor(terminal): phase 02 client cleanup + SIGWINCH support
  203d0a8 refactor(terminal): phase 01 protocol framing fix
  f166be6 refactor(terminal): phase 00 clean slate revert
```

---

## Next Steps

1. ✅ Phase 00: Clean Slate Revert - Done
2. ✅ Phase 01: Protocol Framing Fix - Done
3. ✅ Phase 02: Client Cleanup - Done
4. ✅ Phase 03: Server Cleanup - Done
5. ⏳ Phase 04: PTY Pump Refactor - Final phase (20% remaining)

---

## References

- [Plan](../260109-0109-ssh-like-terminal-refactor/plan.md)
- [Phase 01](../260109-0109-ssh-like-terminal-refactor/phase-01-protocol-framing.md)
- [Phase 02](../260109-0109-ssh-like-terminal-refactor/phase-02-client-cleanup.md)
- [Phase 03](../260109-0109-ssh-like-terminal-refactor/phase-03-server-cleanup.md)
- [Phase 04](../260109-0109-ssh-like-terminal-refactor/phase-04-pty-pump.md)
