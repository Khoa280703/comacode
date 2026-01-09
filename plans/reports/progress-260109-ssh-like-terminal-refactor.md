# SSH-like Terminal Refactor - Progress Report

**Plan**: `260109-0109-ssh-like-terminal-refactor`
**Status**: In Progress (2/5 phases complete)
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
| 2 | Client Cleanup | ⏳ Pending | - | SIGWINCH handling, remove debug code |
| 3 | Server Cleanup | ⏳ Pending | - | Extract spawn helper, remove dupes |
| 4 | PTY Pump Refactor | ⏳ Pending | - | Smart flush with 5ms latency |

**Overall Progress**: 40% (2/5 phases)

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
(Pending commit after user approval)
```

---

## Phase 02: Client Cleanup ⏳

**Status**: Pending

### Planned Tasks
- Remove remaining Vietnamese comments
- Add SIGWINCH handling for dynamic terminal resize
- Fix /exit command handling
- Fix terminal reset sequence

**Estimated**: 2.5h

---

## Phase 03: Server Cleanup ⏳

**Status**: Pending

### Planned Tasks
- Extract duplicate spawn logic to shared function
- Remove remaining duplicate code

**Estimated**: 3h

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
Modified files (staged):
  - crates/cli_client/src/main.rs
  - crates/cli_client/src/message_reader.rs (new)
  - crates/hostagent/src/quic_server.rs
```

---

## Next Steps

1. Commit Phase 01 changes
2. Start Phase 02: Client Cleanup
3. Add SIGWINCH handling for dynamic resize

---

## References

- [Plan](../260109-0109-ssh-like-terminal-refactor/plan.md)
- [Phase 01](../260109-0109-ssh-like-terminal-refactor/phase-01-protocol-framing.md)
- [Phase 02](../260109-0109-ssh-like-terminal-refactor/phase-02-client-cleanup.md)
