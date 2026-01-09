# Plan Summary: Level 2 Web Dashboard

**Plan ID**: 260108-0746-level2-web-dashboard
**Created**: 2026-01-08
**Status**: Pending Approval
**Effort**: 8 hours
**Priority**: P1 (High)

---

## Objective

Replace terminal-based QR code display with beautiful, user-friendly web dashboard that auto-opens in browser when user double-clicks the binary.

---

## Problem

**Current Pain Points**:
- ASCII QR in terminal hard to scan
- Requires terminal knowledge
- No connection status feedback
- Intimidating for non-technical users

---

## Solution

**Level 2: Web Dashboard**
1. Double-click binary → Browser auto-opens to `http://127.0.0.1:3721`
2. Beautiful QR code page (Catppuccin Mocha theme)
3. Real-time connection status via SSE
4. Cross-platform (macOS, Windows, Linux)

---

## Tech Stack

- **Web Server**: Axum 0.7 (async, lightweight)
- **QR Generation**: qrcode-generator 4.1 (SVG output)
- **Browser Automation**: open 5.0 (cross-platform)
- **Real-time Updates**: SSE (Server-Sent Events)

---

## Implementation Phases

### Phase 1: Foundation (2h)
- Add dependencies to `Cargo.toml`
- Create `web_ui.rs` module
- Implement QR generator (SVG format)

### Phase 2: Web Server (2h)
- Axum routes: `/`, `/api/qr`, `/api/status`
- HTML template with Catppuccin Mocha theme
- SSE endpoint for status updates

### Phase 3: Browser Auto-Open (1h)
- Cross-platform browser launch
- Integration with `main.rs`
- Delay for server bind

### Phase 4: Real-time Status (2h)
- SSE broadcasting from `quic_server`
- Frontend SSE client
- Status states: Waiting, Connected, Disconnected

### Phase 5: Polish (1h)
- Port conflict handling (auto-increment)
- Browser close handling (keep server running)
- Error display in UI

---

## Success Criteria

- [ ] Double-click binary → Browser opens automatically
- [ ] QR displays clearly (SVG, 400x400px)
- [ ] Mobile app can scan and connect
- [ ] Status updates in real-time
- [ ] Binary size < 3MB
- [ ] Cross-platform compatibility

---

## Key Decisions

### Q1: SSE vs WebSocket?
**Decision**: SSE (simpler, unidirectional fits use case)

### Q2: Browser close behavior?
**Decision**: Keep server running (allows re-opening browser)

### Q3: Port conflict handling?
**Decision**: Auto-increment port (3721, 3722, 3723...)

### Q4: System tray integration?
**Decision**: Defer to Phase 3 (Level 3)

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Browser fails to open | Terminal QR fallback + log error |
| Port in use | Auto-increment with logging |
| SSE not supported | Polling endpoint fallback |
| Binary size increase | LTO + strip symbols (target < 3MB) |

---

## Open Questions

**Resolved** (see plan for details):
- SSE vs WebSocket → SSE
- Browser close behavior → Keep running
- Port conflicts → Auto-increment
- System tray → Defer to Level 3

---

## Next Steps

1. **Review Plan**: Approve plan and provide feedback
2. **Start Implementation**: Begin with Phase 1 (Foundation)
3. **Testing**: Manual testing on macOS (primary dev platform)
4. **Documentation**: Update README and roadmap

---

## Files

- **Plan**: `plans/260108-0746-level2-web-dashboard/plan.md`
- **This Report**: `plans/reports/planner-260108-0746-level2-web-dashboard.md`

---

**Prepared by**: Planner Subagent
**Date**: 2026-01-08
**Contact**: Comacode Development Team
