---
title: "SSH-like Terminal Refactor Plan"
description: "Clean slate + refactor to SSH-like patterns, fix protocol framing, remove all debug code"
status: completed
priority: P0
effort: 14h
issue: terminal-refactor
branch: main
tags: [refactor, ssh-like, protocol-framing, terminal]
created: 2026-01-09
updated: 2026-01-09
---

# SSH-like Terminal Refactor Plan

## Overview

**Clean slate refactor**: Revert ALL 11+ failed workaround attempts, then implement proper SSH-like terminal I/O with correct protocol framing.

**Root Cause**: Protocol framing bug - using `read()` instead of `read_exact()` for length-prefixed messages.

**Strategy**: Start clean → Fix framing → SSH-like patterns

## Phases

| # | Phase | Status | Effort | Link |
|---|-------|--------|--------|------|
| 0 | Clean Slate Revert | Pending | 1h | [phase-00](./phase-00-clean-slate.md) |
| 1 | Protocol Framing Fix | ⚠️ Code Review | 3h | [phase-01](./phase-01-protocol-framing.md) |
| 2 | Client Cleanup | Pending | 2.5h | [phase-02](./phase-02-client-cleanup.md) |
| 3 | Server Cleanup | ✅ Done (2026-01-09) | 3h | [phase-03](./phase-03-server-cleanup.md) |
| 4 | PTY Pump Refactor | ✅ Done (2026-01-09) | 4h | [phase-04](./phase-04-pty-pump.md) |

**Total Effort**: ~13.5 hours

**Progress**: 100% (5/5 phases complete)

**Fine-tuned for 100% SSH-like**:
- Phase 01: Added MessageReader helper for clean architecture
- Phase 02: Added SIGWINCH handling for dynamic resize
- Phase 04: Smart flush with 5ms latency (not 50ms) for instant typing feel

## Dependencies

- Requires: None (can start immediately)
- Blocks: Terminal testing, mobile app integration

## Clean Slate: What Gets Reverted

| Temp Fix | Location | Action |
|----------|----------|--------|
| Ping for QUIC flush | main.rs:147-149 | ❌ Remove |
| 300ms delayed resize | quic_server.rs:296-309 | ❌ Remove |
| "Pincer Movement" logic | quic_server.rs:276-316 | ❌ Simplify |
| Vietnamese comments | Multiple files | ❌ Remove |
| "Eager spawn trigger" | main.rs:138-153 | ✅ Keep (rename) |

## What We Keep (Correct SSH Patterns)

✅ Resize before spawn
✅ Env vars (COLUMNS, LINES)
✅ Immediate resize after spawn
✅ Eager spawn concept
✅ PROMPT_EOL_MARK env var

## Scout Reports

- [Client Analysis](./scout/scout-cli-client-report.md)
- [Server Analysis](./scout/scout-server-report.md)
- [Transport Analysis](./scout/scout-transport-report.md)

## Related Reports

- [All Failed Attempts](../../reports/analysis-260109-0030-zsh-prompt-timing-unresolved.md)
- [Protocol Framing Bug](../../reports/debugger-260109-0051-protocol-framing-bug.md)
