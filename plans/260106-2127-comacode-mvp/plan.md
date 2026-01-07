---
title: "Comacode MVP - Zero-Latency Remote Terminal Control"
description: "Cross-platform remote terminal app with Rust core, Flutter UI, QUIC protocol for Vibe Coding"
status: pending
priority: P1
effort: 60h
branch: main
tags: [rust, flutter, quic, mvp, terminal, remote-control]
created: 2026-01-06
---

# Comacode MVP Implementation Plan

## Overview
Zero-latency remote terminal control for Vibe Coding. Shared Rust Core + Flutter UI + QUIC Protocol.

## Architecture
```
Mobile (Flutter UI) <--FFI--> Rust Core <--QUIC--> Rust Agent <--PTY--> Terminal
```

## Phases Overview
| Phase | Focus | Effort | Priority |
|-------|-------|--------|----------|
| [01](./phase-01-project-setup.md) | Project Structure & Tooling | 4h | P0 |
| [02](./phase-02-rust-core.md) | Shared Rust Core + FRB Setup | 8h | P0 |
| [03](./phase-03-host-agent.md) | PC Host Binary with PTY | 12h | P0 |
| [04](./phase-04-mobile-app.md) | Flutter App + Terminal UI | 16h | P0 |
| [05](./phase-05-network-protocol.md) | QUIC Protocol Implementation | 10h | P0 |
| [06](./phase-06-discovery-auth.md) | mDNS Discovery + Auth | 6h | P1 |
| [07](./phase-07-testing-deploy.md) | E2E Testing + Builds | 4h | P1 |

## Tech Stack
- **Core**: Rust (no GC, memory safe)
- **Bridge**: flutter_rust_bridge v2
- **Protocol**: QUIC (quinn crate, UDP-based)
- **Terminal**: portable-pty (cross-platform)
- **Serialization**: Postcard (binary, zero-copy)
- **UI**: Flutter + xterm.dart (60fps render)
- **Discovery**: mDNS (mdns-sd)

## MVP Success Criteria
- [ ] Mobile types command → PC executes <100ms (local network)
- [ ] Terminal output streams back to mobile in real-time
- [ ] Auto-discovery via mDNS (no IP input)
- [ ] Secure connection (TLS handshake)
- [ ] iOS + Android + Windows + macOS + Linux support

## Design System
**Developer Dark Theme** (Catppuccin Mocha):
- Background: `#1E1E2E` (Base)
- Surface: `#313244` (Surface0)
- Primary: `#CBA6F7` (Mauve)
- Text: `#CDD6F4` (Text)
- Green: `#A6E3A1` (Green)
- Red: `#F38BA8` (Red)
- Yellow: `#F9E2AF` (Yellow)

## Quick Links
- [Idea Doc](../../idea.md) - Original vision
- [Development Rules](../../.claude/workflows/development-rules.md)
- [Primary Workflow](../../.claude/workflows/primary-workflow.md)

## Timeline
- **Week 1**: Phases 01-03 (Setup + Core + Host)
- **Week 2**: Phases 04-05 (Mobile + Network)
- **Week 3**: Phases 06-07 (Discovery + Testing)

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| QUIC NAT traversal fail | High | Test on real networks, fallback to TCP relay |
| Flutter-Rust FFI complexity | Medium | Use FRB v2 codegen, document patterns |
| PTY Windows compatibility | Medium | Use portable-pty, test on Windows early |
| Mobile battery drain | Medium | Optimize QUIC keep-alive, use background jobs |

## Open Questions
- Authentication method? (Simple password vs public key)
- Relay server for non-LAN? (Phase 2 consideration)
- Session persistence? (Reconnect to existing PTY)

---

**Next Steps**: Start with [Phase 01: Project Setup](./phase-01-project-setup.md)
