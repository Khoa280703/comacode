---
title: "Comacode MVP - Implementation Plan Report"
date: 2026-01-06
author: "Planner Agent"
tags: [comacode, mvp, rust, flutter, quic]
---

# Comacode MVP Implementation Plan Report

## Summary

Comprehensive implementation plan created for Comacode - zero-latency remote terminal control app for Vibe Coding.

**Tech Stack Decision**:
- **Core**: Rust (shared codebase, no GC, memory safe)
- **Mobile**: Flutter (iOS + Android)
- **Protocol**: QUIC via quinn (UDP, avoids TCP HoL blocking)
- **Terminal**: portable-pty (cross-platform PTY)
- **Bridge**: flutter_rust_bridge v2 (FFI automation)
- **Discovery**: mDNS (zero-config)

**Total Estimated Effort**: 60 hours

## Phase Breakdown

| Phase | Focus | Effort | Priority | Status |
|-------|-------|--------|----------|--------|
| 01 | Project Setup & Tooling | 4h | P0 | Pending |
| 02 | Shared Rust Core | 8h | P0 | Pending |
| 03 | Host Agent (PC Binary) | 12h | P0 | Pending |
| 04 | Mobile App (Flutter) | 16h | P0 | Pending |
| 05 | Network Protocol (QUIC) | 10h | P0 | Pending |
| 06 | Discovery & Auth | 6h | P1 | Pending |
| 07 | Testing & Deploy | 4h | P1 | Pending |

## Architecture Overview

```
Mobile Device                    PC Host
┌─────────────────┐             ┌─────────────────┐
│  Flutter UI     │             │  Rust Agent     │
│  (xterm.dart)   │             │  (portable-pty) │
├─────────────────�             ├─────────────────┤
│  Rust Core      │◄─QUIC─────▶│  Rust Core      │
│  (via FRB)      │             │  (shared)       │
└─────────────────┘             └─────────────────┘
```

## Design System

**Catppuccin Mocha Theme** (Developer Dark):
- Background: `#1E1E2E` (Base)
- Surface: `#313244` (Surface0)
- Primary: `#CBA6F7` (Mauve)
- Text: `#CDD6F4` (Text)
- Green: `#A6E3A1` (Green)
- Red: `#F38BA8` (Red)

## Key Technical Decisions

### 1. Shared Rust Core
**Rationale**: Single codebase ensures protocol consistency, no serialization bugs between platforms.

**Benefits**:
- Type safety across FFI boundary
- Memory safety (no crashes from unsafe code)
- Zero-copy deserialization with Postcard

### 2. QUIC over TCP
**Rationale**: QUIC eliminates head-of-line blocking, survives network switching (WiFi → LTE).

**Benefits**:
- Multiple streams without blocking
- Built-in TLS 1.3
- 0-RTT connection resume
- Better on unreliable networks

### 3. flutter_rust_bridge v2
**Rationale**: Automated FFI codegen reduces manual glue code.

**Benefits**:
- Type-safe Dart API
- Async stream support
- No manual C header maintenance

### 4. portable-pty
**Rationale**: Cross-platform PTY support without OS-specific code.

**Benefits**:
- Works on Windows/macOS/Linux
- Handles shell detection
- Manages PTY size control

## MVP Success Criteria

- [ ] **Latency**: <100ms command-to-output on local network
- [ ] **Discovery**: Auto-discover hosts via mDNS (no IP entry)
- [ ] **Security**: Password auth (PKI in Phase 2)
- [ ] **Platforms**: iOS + Android + Windows + macOS + Linux
- [ ] **Reliability**: Auto-reconnect on network change

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| QUIC blocked by firewall | High | Document ports, TCP fallback in Phase 2 |
| Mobile battery drain | Medium | Optimize keep-alive, background tasks |
| PTY Windows compatibility | Medium | Test early on Windows, use portable-pty |
| Flutter-Rust FFI complexity | Medium | Use FRB v2, document patterns |

## Timeline

**Week 1** (20h):
- Phase 01: Project Setup (4h)
- Phase 02: Rust Core (8h)
- Phase 03: Host Agent (8h, remaining 4h in Week 2)

**Week 2** (26h):
- Phase 03: Host Agent completion (4h)
- Phase 04: Mobile App (16h)
- Phase 05: Network Protocol (6h, remaining 4h in Week 3)

**Week 3** (14h):
- Phase 05: Network Protocol completion (4h)
- Phase 06: Discovery & Auth (6h)
- Phase 07: Testing & Deploy (4h)

## Open Questions

1. **Authentication**: MVP uses password. Should Phase 2 use PKI or OAuth?
2. **Relay Server**: Should we build relay for non-LAN access?
3. **Session Persistence**: Reconnect to existing PTY or spawn new?
4. **Monetization**: Freemium or paid-only model?

## Next Steps

1. **Immediate**: Start Phase 01 - Project Setup
2. **Parallel**: Begin iOS/Android dev setup while CI/CD builds
3. **Documentation**: Update docs/ with architecture decisions
4. **Review**: Validate plan with real-world testing

## Files Created

- `/plans/260106-2127-comacode-mvp/plan.md` - Overview
- `/plans/260106-2127-comacode-mvp/phase-01-project-setup.md` - Setup
- `/plans/260106-2127-comacode-mvp/phase-02-rust-core.md` - Core
- `/plans/260106-2127-comacode-mvp/phase-03-host-agent.md` - Host
- `/plans/260106-2127-comacode-mvp/phase-04-mobile-app.md` - Mobile
- `/plans/260106-2127-comacode-mvp/phase-05-network-protocol.md` - QUIC
- `/plans/260106-2127-comacode-mvp/phase-06-discovery-auth.md` - mDNS
- `/plans/260106-2127-comacode-mvp/phase-07-testing-deploy.md` - E2E

## Conclusion

Plan follows YAGNI/KISS/DRY principles. Progressive disclosure keeps each phase focused. MVP achievable in ~3 weeks with focused development. Architecture supports future enhancements (file browser, plugins, relay).

**Recommendation**: Execute Phase 01-03 (host-side) first to validate PTY + QUIC integration before building mobile UI.
