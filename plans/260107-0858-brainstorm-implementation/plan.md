---
title: "Comacode MVP Implementation Plan"
description: "6-phase implementation based on brainstorm decisions - core enhancements, streaming refactor, security, cert persistence, macOS build, Windows support"
status: pending
priority: P0
effort: 28h
branch: main
tags: [mvp, implementation, security, cross-platform]
created: 2026-01-07
---

## Overview

Implementation plan cho Comacode MVP dựa trên brainstorm decisions. Tổng effort: **28h**.

## Phases Summary

| Phase | Focus | Priority | Effort | File |
|-------|-------|----------|--------|------|
| **01** | Core Enhancements | P0 | 3h | `phase-01-core-enhancements.md` |
| **02** | Output Streaming Refactor | P0 | 6h | `phase-02-output-streaming.md` |
| **03** | Security Hardening | P0 | 6h | `phase-03-security-hardening.md` |
| **04** | Certificate Persistence + TOFU | P0 | 5h | `phase-04-cert-persistence.md` |
| **05** | macOS Build + Testing | P1 | 4h | `phase-05-macos-build.md` |
| **06** | Windows Cross-Platform | P2 | 4h | `phase-06-windows-cross.md` |

## Key Decisions Applied

**Architecture**:
- Channel-based streaming (mpsc::channel(1024)) thay vì Arc<Mutex>
- Strict handshake protocol (no backward compatibility)
- Snapshot resync cho error recovery

**Security**:
- 32-byte token authentication
- Rate limiting với governor crate
- TOFU verification với QR code

**Platform**:
- macOS first, Windows ready
- Manual dogfooding thay vì automated tests
- Code signing deferred

## Dependencies

```
Phase 01 → Phase 02 → Phase 03 → Phase 04 → Phase 05 → Phase 06
```

**Critical Path**: Phases 01-04 phải complete trước macOS testing (Phase 05).

## Acceptance Criteria

MVP complete khi:
1. ✅ Version constants sync across core/mobile/host
2. ✅ Channel-based streaming hoạt động với backpressure
3. ✅ Token auth + rate limiting enabled
4. ✅ Cert persist + TOFU flow functional
5. ✅ macOS binary chạy stable qua dogfooding
6. ✅ Windows cross-compilation successful

## Unresolved Questions

1. **QR code format**: JSON raw hay base64 encoding? (Resolve Phase 04)
2. **Rate limit config**: 5 attempts/min có quá strict không? (Resolve Phase 03)
3. **Snapshot buffer size**: 1000 lines có đủ không? (Resolve Phase 02)
4. **Windows 7/8 support**: ConPTY fallback có cần không? (Resolve Phase 06)
